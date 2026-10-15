#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SGRBackgrounds.h"
#import "SGRTokens.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>

NSNotificationName const SGRBackgroundDidChangeNotification = @"spotifyglass.redesign.backgroundChanged";
NSString *const SGRBackgroundHome = @"home";
NSString *const SGRBackgroundPlaylists = @"playlists";
NSString *const SGRBackgroundLikedSongs = @"likedSongs";
static NSString *const kPrefix = @"spotifyglass.redesign.backgrounds.photo.";
static char kPickerKey, kPhotoKey;
static NSMutableDictionary<NSString *, NSString *> *sg_imports;

static NSString *keyFor(NSString *scope) { return [kPrefix stringByAppendingString:scope]; }
static NSDictionary *recordFor(NSString *scope) {
    id record = scope.length ? [NSUserDefaults.standardUserDefaults objectForKey:keyFor(scope)] : nil;
    return [record isKindOfClass:NSDictionary.class] ? record : nil;
}
static NSString *fileFor(NSString *scope) {
    id value = recordFor(scope)[@"file"];
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *file = value;
    // Only files created by this feature may be read or removed, never an arbitrary stored path.
    if (![file.pathExtension isEqualToString:@"jpg"]
        || ![file.lastPathComponent isEqualToString:file]) return nil;
    return [[NSUUID alloc] initWithUUIDString:[file stringByDeletingPathExtension]] ? file : nil;
}
static NSURL *directory(void) {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [support URLByAppendingPathComponent:@"spoti.pw/Backgrounds" isDirectory:YES];
}
static NSCache<NSString *, UIImage *> *images(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 4; cache.totalCostLimit = 24 * 1024 * 1024; });
    return cache;
}
static void changed(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGRBackgroundDidChangeNotification object:nil];
}
BOOL SGRBackgroundHasPhoto(NSString *scope) { return fileFor(scope) != nil; }
NSString *SGRBackgroundScopeForPlaylist(NSString *uri, BOOL liked) {
    if (liked) return SGRBackgroundLikedSongs;
    if (SGInt(SGRKeyPlaylistBackgroundMode, 0) == 1 && uri.length) return [@"playlist." stringByAppendingString:uri];
    return SGRBackgroundPlaylists;
}
static void removeFile(NSString *file) {
    if (!file) return;
    [images() removeObjectForKey:file];
    NSURL *url = [directory() URLByAppendingPathComponent:file];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [NSFileManager.defaultManager removeItemAtURL:url error:nil]; });
}
static void clearPhoto(NSString *scope) {
    NSString *old = fileFor(scope);
    [sg_imports removeObjectForKey:scope];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:keyFor([@"pending." stringByAppendingString:scope])];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:keyFor(scope)];
    removeFile(old);
    changed();
}
// Decodes and applies orientation without ever expanding a full-resolution camera photo in memory.
static UIImage *thumbnail(NSURL *url) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;
    NSDictionary *options = @{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge id)kCGImageSourceCreateThumbnailWithTransform: @YES, (__bridge id)kCGImageSourceThumbnailMaxPixelSize: @1280,
        (__bridge id)kCGImageSourceShouldCacheImmediately: @YES};
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    UIImage *image = cg ? [UIImage imageWithCGImage:cg] : nil;
    if (cg) CGImageRelease(cg);
    return image;
}
static void loadPhoto(NSString *file, void (^done)(UIImage *)) {
    UIImage *cached = [images() objectForKey:file];
    if (cached) { done(cached); return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *image = thumbnail([directory() URLByAppendingPathComponent:file]);
        if (image) [images() setObject:image forKey:file cost:(NSUInteger)(image.size.width * image.size.height * 4)];
        dispatch_async(dispatch_get_main_queue(), ^{ done(image); });
    });
}

@interface SGRBackgroundPicker : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *scope, *name;
@property (nonatomic, weak) UIViewController *owner;
@end
@implementation SGRBackgroundPicker
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (!provider) { [picker dismissViewControllerAnimated:YES completion:nil]; return; }
    __weak UIViewController *owner = self.owner;
    __block BOOL dismissed = NO, failed = NO;
    void (^offerFailure)(void) = ^{
        if (!dismissed || !failed || !owner.viewIfLoaded.window || owner.presentedViewController) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn’t load photo"
            message:@"Please try another photo. Your current background is still saved." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [owner presentViewController:alert animated:YES completion:nil];
    };
    [picker dismissViewControllerAnimated:YES completion:^{ dismissed = YES; offerFailure(); }];
    NSString *scope = self.scope, *name = self.name, *token = NSUUID.UUID.UUIDString;
    if (!sg_imports) sg_imports = [NSMutableDictionary dictionary];
    sg_imports[scope] = token;
    NSString *pendingKey = keyFor([@"pending." stringByAppendingString:scope]);
    [NSUserDefaults.standardUserDefaults setObject:token forKey:pendingKey];
    changed();
    NSString *type = UTTypeImage.identifier;
    for (NSString *identifier in provider.registeredTypeIdentifiers) {
        if ([[UTType typeWithIdentifier:identifier] conformsToType:UTTypeImage]) { type = identifier; break; }
    }
    // The temporary file is valid only inside this callback. Read, downsample and encode it there,
    // on the provider's worker, before returning; UIKit views and preferences stay on the main queue.
    [provider loadFileRepresentationForTypeIdentifier:type completionHandler:^(NSURL *url, NSError *error) {
        @autoreleasepool {
            UIImage *image = !error && url ? thumbnail(url) : nil;
            NSData *jpeg = image ? UIImageJPEGRepresentation(image, 0.88) : nil;
            NSString *file = [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"jpg"];
            NSURL *folder = directory(), *destination = [folder URLByAppendingPathComponent:file];
            BOOL saved = jpeg.length && [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil]
                      && [jpeg writeToURL:destination options:NSDataWritingAtomic error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![sg_imports[scope] isEqualToString:token]
                    || ![[NSUserDefaults.standardUserDefaults stringForKey:pendingKey] isEqualToString:token]) {
                    if ([sg_imports[scope] isEqualToString:token]) [sg_imports removeObjectForKey:scope];
                    if (saved) removeFile(file);
                    changed();
                    return;
                }
                [sg_imports removeObjectForKey:scope];
                [NSUserDefaults.standardUserDefaults removeObjectForKey:pendingKey];
                if (saved) {
                    NSString *old = fileFor(scope);
                    [images() setObject:image forKey:file cost:(NSUInteger)(image.size.width * image.size.height * 4)];
                    [NSUserDefaults.standardUserDefaults setObject:@{@"file": file, @"name": name ?: scope} forKey:keyFor(scope)];
                    removeFile(old);
                } else { failed = YES; offerFailure(); }
                changed();
            });
        }
    }];
}
@end
static void pickPhoto(NSString *scope, NSString *title) {
    UIViewController *owner = SGTopController();
    if (!owner || owner.presentedViewController) return;
    PHPickerConfiguration *configuration = [PHPickerConfiguration new];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    SGRBackgroundPicker *delegate = [SGRBackgroundPicker new];
    delegate.scope = scope; delegate.name = title; delegate.owner = owner;
    picker.delegate = delegate;
    objc_setAssociatedObject(picker, &kPickerKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [owner presentViewController:picker animated:YES completion:nil];
}
void SGRChooseBackground(NSString *scope, NSString *title) {
    if (!scope.length) return;
    if (!SGRBackgroundHasPhoto(scope) && !sg_imports[scope]) { pickPhoto(scope, title); return; }
    UIViewController *owner = SGTopController();
    if (!owner || owner.presentedViewController) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak UIAlertController *weakSheet = sheet;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Choose photo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSheet dismissViewControllerAnimated:YES completion:^{ pickPhoto(scope, title); }];
    }]];
    NSString *restore = [scope hasPrefix:@"playlist."] ? @"Use default background" : @"Use original background";
    [sheet addAction:[UIAlertAction actionWithTitle:restore style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { clearPhoto(scope); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = owner.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(owner.view.bounds), CGRectGetMidY(owner.view.bounds), 1, 1);
    sheet.popoverPresentationController.permittedArrowDirections = 0;
    [owner presentViewController:sheet animated:YES completion:nil];
}
static SGModRow *photoRow(NSString *scope, NSString *title) {
    return SGWithSymbol(SGStatActionRow(title, nil, ^NSString *{
        return sg_imports[scope] ? @"Importing…" : SGRBackgroundHasPhoto(scope) ? @"Photo" : [scope hasPrefix:@"playlist."] ? @"Default" : @"Original";
    }, ^{ SGRChooseBackground(scope, title); }), @"photo");
}
static UIViewController *individualPhotos(void) {
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    NSDictionary *saved = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
    NSString *prefix = [kPrefix stringByAppendingString:@"playlist."];
    for (NSString *key in [saved.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![key hasPrefix:prefix]) continue;
        NSString *scope = [key substringFromIndex:kPrefix.length];
        if (!SGRBackgroundHasPhoto(scope)) continue;
        id title = recordFor(scope)[@"name"];
        [rows addObject:photoRow(scope, [title isKindOfClass:NSString.class] ? title : @"Playlist")];
    }
    return [[SGModPage alloc] initWithTitle:@"Individual playlists" intro:@"Open a playlist’s ⋯ menu and choose Background to set its photo. Saved photos can be changed or removed here."
        sections:rows.count ? @[SGSection(nil, rows)] : @[] footer:nil];
}
UIViewController *SGRBackgroundsPage(void) {
    SGModRow *mode = SGChoiceRow(@"Playlist backgrounds", nil, SGRKeyPlaylistBackgroundMode, @[@"One photo for all", @"Individual photos"], 0);
    mode.chosen = ^(NSInteger index) { changed(); };
    SGModRow *individual = SGPageRow(@"Individual playlists", ^UIViewController *{ return individualPhotos(); });
    individual.visible = ^BOOL { return SGInt(SGRKeyPlaylistBackgroundMode, 0) == 1; };
    return [[SGModPage alloc] initWithTitle:@"Backgrounds" intro:@"Choose a photo from Photos. Backgrounds apply immediately. Individual playlists use the default photo until you choose their own."
        sections:@[SGSection(nil, @[photoRow(SGRBackgroundHome, @"Home"), photoRow(SGRBackgroundLikedSongs, @"Liked Songs")]),
                   SGSection(@"Playlists", @[mode, photoRow(SGRBackgroundPlaylists, @"Default playlist photo"), individual])] footer:nil];
}

@interface SGRPhotoBackgroundView : UIView
@property (nonatomic, copy) NSString *scope;
@end
@implementation SGRPhotoBackgroundView {
    UIImageView *_picture;
    CALayer *_shade;
    NSString *_file;
    NSUInteger _generation;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO; self.accessibilityElementsHidden = YES;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; self.clipsToBounds = YES; self.hidden = YES;
    _picture = [[UIImageView alloc] initWithFrame:self.bounds];
    _picture.contentMode = UIViewContentModeScaleAspectFill; _picture.clipsToBounds = YES;
    [self addSubview:_picture];
    _shade = [CALayer layer]; [self.layer addSublayer:_shade];
    for (NSNotificationName name in @[SGRBackgroundDidChangeNotification, NSUserDefaultsDidChangeNotification, UIAccessibilityDarkerSystemColorsStatusDidChangeNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshSoon) name:name object:nil];
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)setScope:(NSString *)scope {
    if ([_scope isEqualToString:scope]) return;
    _generation++;
    _scope = [scope copy]; _file = nil; _picture.image = nil; self.hidden = YES;
    [self refresh];
}
- (void)refreshSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; [self.superview setNeedsLayout]; });
}
- (void)refresh {
    [self setNeedsLayout];
    if (!self.window) return;
    NSString *file = fileFor(_scope);
    if ((_file == file) || [_file isEqualToString:file]) return;
    _file = file;
    NSUInteger generation = ++_generation;
    if (!file) { _picture.image = nil; self.hidden = YES; return; }
    __weak SGRPhotoBackgroundView *weakSelf = self;
    loadPhoto(file, ^(UIImage *image) {
        SGRPhotoBackgroundView *view = weakSelf;
        if (!view || generation != view->_generation) return;
        BOOL animated = view.window && !view.hidden;
        if (animated) [UIView transitionWithView:view->_picture duration:SGRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve
            animations:^{ view->_picture.image = image; } completion:nil];
        else view->_picture.image = image;
        view.hidden = image == nil;
    });
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self refresh];
    else {
        // Navigation stacks retain old pages. Keep their preference, not a camera-sized decoded
        // image per playlist; the bounded cache supplies the image when the page returns.
        _generation++; _file = nil; _picture.image = nil; self.hidden = YES;
    }
}
- (void)layoutSubviews {
    [super layoutSubviews]; _picture.frame = self.bounds;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _shade.frame = self.bounds;
    // A white photo tops out at sRGB 0.30, keeping the redesign's 65%-white secondary text legible.
    _shade.backgroundColor = [UIColor colorWithWhite:0 alpha:SGRIncreaseContrast() ? 0.82 : 0.70].CGColor;
    [CATransaction commit];
}
@end
UIView *SGRInstallPhotoBackground(UIView *page, NSString *scope, NSUInteger index) {
    if (!page) return nil;
    SGRPhotoBackgroundView *photo = objc_getAssociatedObject(page, &kPhotoKey);
    if (!photo) {
        photo = [[SGRPhotoBackgroundView alloc] initWithFrame:page.bounds];
        objc_setAssociatedObject(page, &kPhotoKey, photo, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    photo.scope = scope;
    if (photo.superview != page) [page insertSubview:photo atIndex:MIN(index, page.subviews.count)];
    else if ([page.subviews indexOfObject:photo] != index) [page insertSubview:photo atIndex:MIN(index, page.subviews.count - 1)];
    if (!CGRectEqualToRect(photo.frame, page.bounds)) photo.frame = page.bounds;
    return photo;
}
