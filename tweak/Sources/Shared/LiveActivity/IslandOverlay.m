#import "IslandOverlay.h"
#import <QuartzCore/QuartzCore.h>

@interface SGIslandPanel : UIControl
@property (nonatomic, strong, readonly) UILabel *line, *nextLine;
@property (nonatomic, strong, readonly) UIView *text;
- (void)refreshFonts;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

@implementation SGIslandPanel
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.backgroundColor = UIColor.blackColor;
    self.layer.borderWidth = 1 / UIScreen.mainScreen.scale;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    _text = [UIView new];
    _text.userInteractionEnabled = NO;
    [self addSubview:_text];
    _line = [UILabel new];
    _line.numberOfLines = 3;
    _line.textColor = UIColor.whiteColor;
    _nextLine = [UILabel new];
    _nextLine.numberOfLines = 1;
    _nextLine.textColor = [UIColor colorWithWhite:1 alpha:0.48];
    for (UILabel *label in @[_line, _nextLine]) {
        label.isAccessibilityElement = NO;
        [_text addSubview:label];
    }
    [self refreshFonts];
    return self;
}
- (void)refreshFonts {
    _line.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline]
        scaledFontForFont:[UIFont systemFontOfSize:20 weight:UIFontWeightSemibold] maximumPointSize:38];
    _nextLine.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline]
        scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightMedium] maximumPointSize:28];
    [self setNeedsLayout];
}
- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat room = MAX(1, width - 40);
    CGFloat line = MIN(ceil([_line sizeThatFits:CGSizeMake(room, CGFLOAT_MAX)].height), ceil(_line.font.lineHeight * 3));
    CGFloat next = _nextLine.text.length ? ceil(_nextLine.font.lineHeight) + 8 : 0;
    return MAX(88, line + next + 36);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MAX(1, self.bounds.size.width - 40);
    CGFloat height = MIN(ceil([_line sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height), ceil(_line.font.lineHeight * 3));
    _text.frame = self.bounds;
    _line.frame = CGRectMake(20, 18, width, height);
    _nextLine.frame = CGRectMake(20, 18 + height + 8, width, ceil(_nextLine.font.lineHeight));
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // A collapsed 12pt capsule still has a 44pt touch target.
    return CGRectContainsPoint(CGRectInset(self.bounds, 0, -MAX(0, (44 - self.bounds.size.height) / 2)), point);
}
@end

@interface SGIslandOverlayController : UIViewController
@property (nonatomic, weak) UIWindow *contentWindow;
- (void)showTrack:(NSString *)track line:(NSString *)line next:(NSString *)next paused:(BOOL)paused;
- (void)refreshFonts;
@end

@implementation SGIslandOverlayController {
    SGIslandPanel *_panel;
    NSString *_track, *_line, *_next;
    BOOL _hasLine, _collapsed;
}
- (void)loadView {
    self.view = [UIView new];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _panel = [SGIslandPanel new];
    [_panel addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    UISwipeGestureRecognizer *up = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(collapse)];
    up.direction = UISwipeGestureRecognizerDirectionUp;
    [_panel addGestureRecognizer:up];
    [self.view addSubview:_panel];
}
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self placeAnimated:NO];
}
- (void)refreshFonts { [_panel refreshFonts]; [self placeAnimated:NO]; }
- (void)toggle { _collapsed = !_collapsed; [self placeAnimated:YES]; }
- (void)collapse { _collapsed = YES; [self placeAnimated:YES]; }
- (void)showTrack:(NSString *)track line:(NSString *)line next:(NSString *)next paused:(BOOL)paused {
    [self loadViewIfNeeded];
    if (![_track isEqualToString:track]) { _track = [track copy]; _collapsed = NO; }
    BOOL changed = ![_line isEqualToString:line] || ![_next isEqualToString:next];
    BOOL hadLine = _hasLine;
    _hasLine = line.length > 0 && ![line isEqualToString:@"♪"];
    if (changed) {
        if (hadLine && _hasLine && !UIAccessibilityIsReduceMotionEnabled()) {
            CATransition *fade = [CATransition animation];
            fade.type = kCATransitionFade;
            fade.duration = 0.16;
            [_panel.text.layer addAnimation:fade forKey:@"lyrics"];
        }
        _line = [line copy]; _next = [next copy];
        _panel.line.text = _hasLine ? line : @"";
        _panel.nextLine.text = _hasLine ? next : @"";
    }
    _panel.line.alpha = paused ? 0.65 : 1;
    [self placeAnimated:YES];
}
- (void)placeAnimated:(BOOL)animated {
    if (!_panel || !self.isViewLoaded) return;
    CGFloat width = MIN(440, self.view.bounds.size.width - 24);
    if (width <= 0) return;
    BOOL expanded = _hasLine && !_collapsed;
    CGFloat height = expanded ? [_panel heightForWidth:width] : 12;
    CGFloat top = self.contentWindow.safeAreaInsets.top + 6;
    height = MIN(height, MAX(44, self.view.bounds.size.height - top - 24));
    CGFloat side = expanded ? width : MIN(width, 240);
    CGRect frame = CGRectMake((self.view.bounds.size.width - side) / 2, top, side, height);
    _panel.accessibilityLabel = expanded ? _line : @"Show lyrics";
    _panel.accessibilityValue = expanded ? _next : nil;
    _panel.accessibilityHint = expanded ? @"Double-tap to collapse" : @"Double-tap to expand";
    BOOL geometryChanged = !CGRectEqualToRect(_panel.frame, frame);
    void (^place)(void) = ^{
        self->_panel.frame = frame;
        self->_panel.layer.cornerRadius = expanded ? 28 : 6;
        self->_panel.text.alpha = expanded ? 1 : 0;
    };
    if (!geometryChanged) return;
    if (!animated) [UIView performWithoutAnimation:place];
    else if (UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:place];
        CATransition *fade = [CATransition animation];
        fade.type = kCATransitionFade; fade.duration = 0.15;
        [_panel.layer addAnimation:fade forKey:@"expand"];
    } else {
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
            animations:place completion:nil];
    }
}
@end

// This window never becomes key. Only the panel takes touches; everything else reaches Spotify.
@interface SGIslandOverlayWindow : UIWindow @end
@implementation SGIslandOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self || hit == self.rootViewController.view ? nil : hit;
}
@end

static SGIslandOverlayWindow *sg_window;
static SGIslandOverlayController *sg_controller;

void SGIslandOverlayHide(void) {
    sg_window.hidden = YES;
    sg_window.rootViewController = nil;
    sg_window = nil;
    sg_controller = nil;
}

static UIWindow *contentWindow(void) {
    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window == sg_window || window.hidden || window.windowLevel != UIWindowLevelNormal) continue;
            if (window.isKeyWindow) return window;
            if (!fallback) fallback = window;
        }
    }
    return fallback;
}

void SGIslandOverlayShow(NSString *trackID, NSString *line, NSString *nextLine, BOOL paused) {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive
        || UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone) { SGIslandOverlayHide(); return; }
    UIWindow *content = contentWindow();
    if (!content || content.bounds.size.width >= content.bounds.size.height) { SGIslandOverlayHide(); return; }
    static dispatch_once_t observing;
    dispatch_once(&observing, ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *note) { SGIslandOverlayHide(); }];
        [center addObserverForName:UIContentSizeCategoryDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *note) { [sg_controller refreshFonts]; }];
        [center addObserverForName:UIAccessibilityBoldTextStatusDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *note) { [sg_controller refreshFonts]; }];
    });
    if (sg_window.windowScene != content.windowScene) SGIslandOverlayHide();
    if (!sg_window) {
        sg_window = [[SGIslandOverlayWindow alloc] initWithWindowScene:content.windowScene];
        sg_window.frame = content.bounds;
        sg_window.backgroundColor = UIColor.clearColor;
        sg_window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        sg_window.windowLevel = UIWindowLevelNormal + 1;
        sg_controller = [SGIslandOverlayController new];
        sg_controller.contentWindow = content;
        sg_window.rootViewController = sg_controller;
        sg_window.hidden = NO;
        [sg_controller.view layoutIfNeeded];
    }
    sg_controller.contentWindow = content;
    [sg_controller showTrack:trackID line:line next:nextLine paused:paused];
}
