#import <ImageIO/ImageIO.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Lyrics/Lyrics.h"
#import "LyricCards.h"
#include <math.h>

static const NSUInteger kMaxLines = 6, kMaxCharacters = 280;

@interface SGLyricCardEditor : UITableViewController
- (instancetype)initWithTrack:(SPTPlayerTrack *)track lines:(NSArray<SGKaraokeLine *> *)lines;
@end

@implementation SGLyricCardEditor {
    NSString *_song, *_artist;
    NSArray<NSString *> *_lines;
    NSMutableIndexSet *_selected;
    UIImage *_artwork, *_rendered;
    UIImageView *_preview;
    UILabel *_status;
    UISegmentedControl *_styles;
    NSURLSessionDataTask *_artTask;
}

- (instancetype)initWithTrack:(SPTPlayerTrack *)track lines:(NSArray<SGKaraokeLine *> *)lines {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Lyric card";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _song = [track.trackTitle copy] ?: @"Unknown song"; _artist = [track.artistName copy] ?: @"";
    NSMutableArray *texts = [NSMutableArray array];
    NSInteger lead = SGKaraokeLeadLine(lines, SGKaraokePositionMs());
    NSUInteger initial = 0;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *text = [SGKaraokeLineText(lines[i]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!text.length || [text isEqualToString:@"♪"] || [text isEqualToString:@"♫"]) continue;
        if ((NSInteger)i == lead) initial = texts.count;
        [texts addObject:text];
    }
    _lines = texts; _selected = [NSMutableIndexSet indexSet];
    if (_lines.count && _lines[initial].length <= kMaxCharacters) [_selected addIndex:initial];
    // Artwork belongs to this snapshot of the song. A track change never swaps the card's metadata.
    NSDictionary *metadata = track.metadata;
    NSURL *url;
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url", @"image_small_url"]) {
        NSString *value = metadata[field];
        if (![value isKindOfClass:NSString.class]) continue;
        if ([value hasPrefix:@"spotify:image:"]) value = [@"https://i.scdn.co/image/" stringByAppendingString:[value substringFromIndex:14]];
        NSURL *candidate = [NSURL URLWithString:value];
        if ([candidate.scheme isEqualToString:@"https"] && [candidate.host isEqualToString:@"i.scdn.co"]) { url = candidate; break; }
    }
    if (url) {
        __weak SGLyricCardEditor *weakSelf = self;
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url]; request.timeoutInterval = 12;
        _artTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data.length || data.length > 5 * 1024 * 1024) return;
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
            if (!source) return;
            NSDictionary *options = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @1080,
                (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES};
            CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
            UIImage *artwork = image ? [UIImage imageWithCGImage:image] : nil;
            if (image) CGImageRelease(image); CFRelease(source);
            dispatch_async(dispatch_get_main_queue(), ^{
                SGLyricCardEditor *editor = weakSelf; if (!editor || !artwork) return;
                editor->_artwork = artwork;
                if (editor.isViewLoaded) [editor updatePreview];
            });
        }];
        [_artTask resume];
    }
    return self;
}
- (void)dealloc { [_artTask cancel]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Share" style:UIBarButtonItemStyleDone target:self action:@selector(share)];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    UIView *header = [UIView new];
    _preview = [UIImageView new]; _preview.contentMode = UIViewContentModeScaleAspectFit;
    _preview.isAccessibilityElement = YES; _preview.accessibilityLabel = @"Lyric card preview";
    _preview.layer.cornerRadius = 14; _preview.clipsToBounds = YES;
    [header addSubview:_preview];
    _styles = [[UISegmentedControl alloc] initWithItems:@[@"Midnight", @"Paper", @"Artwork"]];
    _styles.selectedSegmentIndex = 0;
    _styles.accessibilityLabel = @"Card style";
    [_styles addTarget:self action:@selector(updatePreview) forControlEvents:UIControlEventValueChanged];
    [header addSubview:_styles];
    _status = [UILabel new]; _status.numberOfLines = 0;
    _status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _status.adjustsFontForContentSizeCategory = YES; _status.textColor = UIColor.secondaryLabelColor;
    [header addSubview:_status]; self.tableView.tableHeaderView = header;
    [self updatePreview];
}
- (NSArray<NSString *> *)selection {
    NSMutableArray *out = [NSMutableArray array];
    [_selected enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) { [out addObject:_lines[idx]]; }];
    return out;
}
- (void)updatePreview {
    NSArray *selection = [self selection];
    _rendered = SGLyricCardImage(_song, _artist, selection, _artwork, _styles.selectedSegmentIndex);
    _preview.image = _rendered;
    _preview.accessibilityValue = [selection componentsJoinedByString:@", "];
    _status.text = !selection.count ? @"Select up to 6 lines below." : !_rendered ? @"Choose fewer or shorter lines so every word fits." : @"Select up to 6 lines · exports at 1080 × 1350";
    self.navigationItem.rightBarButtonItem.enabled = _rendered != nil;
    [self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    CGFloat width = self.tableView.bounds.size.width;
    CGFloat cardWidth = MAX(1, MIN(260, width - 64));
    _preview.frame = CGRectMake((width - cardWidth) / 2, 16, cardWidth, cardWidth * 1.25);
    _styles.frame = CGRectMake(20, CGRectGetMaxY(_preview.frame) + 20, MAX(1, width - 40), 36);
    CGFloat statusHeight = [_status sizeThatFits:CGSizeMake(MAX(1, width - 40), CGFLOAT_MAX)].height;
    _status.frame = CGRectMake(20, CGRectGetMaxY(_styles.frame) + 12, MAX(1, width - 40), statusHeight);
    CGFloat height = CGRectGetMaxY(_status.frame) + 12;
    if (fabs(header.frame.size.height - height) > 0.5 || header.frame.size.width != width) {
        header.frame = CGRectMake(0, 0, width, height); self.tableView.tableHeaderView = header;
    }
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return _lines.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"line"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"line"];
    UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
    content.text = _lines[(NSUInteger)path.row]; content.textProperties.numberOfLines = 0;
    cell.contentConfiguration = content;
    BOOL selected = [_selected containsIndex:(NSUInteger)path.row];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    NSUInteger index = (NSUInteger)path.row;
    if ([_selected containsIndex:index]) [_selected removeIndex:index];
    else {
        NSUInteger length = [[self selection] componentsJoinedByString:@"\n"].length + _lines[index].length + (_selected.count ? 1 : 0);
        if (_selected.count >= kMaxLines || length > kMaxCharacters) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Keep the card readable" message:@"Choose up to 6 lines and 280 characters. Deselect a line to make room." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil]; return;
        }
        [_selected addIndex:index];
    }
    [table reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    [self updatePreview];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)share {
    if (!_rendered) return;
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[_rendered] applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:share animated:YES completion:nil];
}
@end

void SGPresentLyricCard(UIViewController *presenter, SPTPlayerTrack *track) {
    NSString *uri = SGURIString(track.URI);
    NSString *identifier = [uri hasPrefix:@"spotify:track:"] ? [uri substringFromIndex:14] : nil;
    NSArray *lines = identifier ? SGKaraokeLinesForTrack(identifier) : nil;
    if (!lines.count) {
        if (identifier) SGKaraokeRequestLyrics(identifier);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No lyrics to share yet" message:identifier ? @"Lyrics have been requested. Try again once they appear for this song." : @"Play a song with lyrics first." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil]; return;
    }
    SGLyricCardEditor *editor = [[SGLyricCardEditor alloc] initWithTrack:track lines:lines];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
    navigation.sheetPresentationController.prefersGrabberVisible = YES;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
void SGPresentPlayingLyricCard(void) { SGPresentLyricCard(SGTopController(), SGPlayerState().track); }
