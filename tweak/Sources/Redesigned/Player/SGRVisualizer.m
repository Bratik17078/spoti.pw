#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/PlayerEvents.h"
#import "Shared/AudioVisualization/Visualization.h"
#import "Redesigned/Kit/SGRTokens.h"
#include <math.h>
#include <string.h>
#import "SGRVisualizer.h"

static NSNotificationName const SGRVisualizerSettingsChanged = @"spotifyglass.redesign.visualizerChanged";

// A display link retains its target. Keep that target separate so removing the player frees its view.
@interface SGRVisualizerClock : NSObject
@property (nonatomic, weak) SGRVisualizer *view;
- (void)tick:(CADisplayLink *)link;
@end
@interface SGRVisualizer () <SGPlayerStateObserver>
- (void)tick:(CADisplayLink *)link;
- (void)schedule;
@end
@implementation SGRVisualizerClock
- (void)tick:(CADisplayLink *)link { [self.view tick:link]; }
@end

@implementation SGRVisualizer {
    CADisplayLink *_link;
    CAShapeLayer *_shape;
    SGSpectrumFrame _frame;
    float _levels[SGSpectrumBands];
    double _heardAt, _drawnAt;
    NSInteger _style;
    CGFloat _intensity;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _shape = [CAShapeLayer layer]; _shape.lineCap = kCALineCapRound; _shape.lineJoin = kCALineJoinRound;
    _shape.fillColor = UIColor.clearColor.CGColor;
    [self.layer addSublayer:_shape];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
        UIAccessibilityReduceMotionStatusDidChangeNotification, NSProcessInfoPowerStateDidChangeNotification,
        SGPlayerTransitionNotification, SGPlayerTransitionEndedNotification, SGRVisualizerSettingsChanged]) {
        [center addObserver:self selector:@selector(changed:) name:name object:nil];
    }
    SGAddPlayerStateObserver(self);
    return self;
}
- (void)dealloc { [_link invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)didMoveToWindow { [super didMoveToWindow]; [self schedule]; }
- (void)setPlayerVisible:(BOOL)visible { _playerVisible = visible; [self schedule]; }
- (void)playerStateDidChange:(SPTPlayerState *)state { [self schedule]; }
- (void)changed:(NSNotification *)note {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self changed:note]; });
        return;
    }
    if ([note.name isEqualToString:UIApplicationWillResignActiveNotification]) { [self stop]; return; }
    [self schedule];
}
- (void)stop {
    [_link invalidate]; _link = nil;
    SGVisualizationSetListening(NO);
    _shape.path = nil; _heardAt = _drawnAt = 0;
    memset(&_frame, 0, sizeof _frame); memset(_levels, 0, sizeof _levels);
}
- (void)schedule {
    BOOL runs = self.playerVisible && self.window && SGFlag(SGRKeyVisualizer, NO)
        && UIApplication.sharedApplication.applicationState == UIApplicationStateActive
        && SGPlayerState().isPlaying && !SGPlayerState().isPaused
        && !UIAccessibilityIsReduceMotionEnabled() && !NSProcessInfo.processInfo.lowPowerModeEnabled
        && !SGPlayerTransitionEnds();
    if (!runs) { [self stop]; return; }
    _style = SGInt(SGRKeyVisualizerStyle, 0);
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyVisualizerIntensity];
    double intensity = [stored respondsToSelector:@selector(doubleValue)] ? [stored doubleValue] : 0.5;
    _intensity = isfinite(intensity) ? MIN(1, MAX(0.1, intensity)) : 0.5;
    _shape.strokeColor = [SGRAccent() colorWithAlphaComponent:0.12 + 0.26 * _intensity].CGColor;
    if (_link) return;
    SGVisualizationSetListening(YES);
    SGRVisualizerClock *clock = [SGRVisualizerClock new]; clock.view = self;
    _link = [CADisplayLink displayLinkWithTarget:clock selector:@selector(tick:)];
    // Never cap the app's refresh rate at 60 during the player's 120 Hz interaction.
    _link.preferredFrameRateRange = CAFrameRateRangeMake(30, 120, 120);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)layoutSubviews { [super layoutSubviews]; _shape.frame = self.bounds; }
- (void)tick:(CADisplayLink *)link {
    // The display link follows the display's rate; analysis and path updates need only 30 Hz.
    double now = CACurrentMediaTime();
    if (now - _drawnAt < 1.0 / 30) return;
    double elapsed = _drawnAt ? MIN(0.1, now - _drawnAt) : 1.0 / 30; _drawnAt = now;
    SGVisualizationRead(&_frame, now, &_heardAt);
    BOOL fresh = _heardAt > 0 && now - _heardAt < 0.25;
    CGFloat width = self.bounds.size.width, height = MIN(self.bounds.size.height, 950);
    CGFloat baseline = height * 0.51, amplitude = height * (0.05 + 0.13 * _intensity);
    UIBezierPath *path = [UIBezierPath bezierPath];
    if (_style == 1) {
        _shape.lineWidth = 2;
        if (fresh) for (unsigned i = 0; i < SGSpectrumWaveSamples; i++) {
            CGPoint point = CGPointMake(width * i / (SGSpectrumWaveSamples - 1), baseline + _frame.wave[i] * amplitude);
            if (i == 0) [path moveToPoint:point]; else [path addLineToPoint:point];
        }
    } else {
        CGFloat step = width / (SGSpectrumBands + 1);
        _shape.lineWidth = MAX(2, step * 0.38);
        for (unsigned i = 0; i < SGSpectrumBands; i++) {
            float target = fresh ? _frame.bands[i] : 0;
            double time = target > _levels[i] ? 0.045 : 0.18;
            _levels[i] += (target - _levels[i]) * (1 - exp(-elapsed / time));
            CGFloat extent = _levels[i] * amplitude;
            if (extent < 0.5) continue;
            CGFloat x = (i + 1) * step;
            [path moveToPoint:CGPointMake(x, baseline - extent)];
            [path addLineToPoint:CGPointMake(x, baseline + extent)];
        }
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _shape.path = path.CGPath;
    [CATransaction commit];
}
@end

static void notify(void) { [NSNotificationCenter.defaultCenter postNotificationName:SGRVisualizerSettingsChanged object:nil]; }
SGModSection *SGRVisualizerSection(void) {
    SGModRow *enabled = SGOptionRow(@"Music visualizer", @"Audio-reactive shapes behind the artwork", SGRKeyVisualizer);
    enabled.changed = ^(BOOL on) { notify(); };
    SGModRow *style = SGChoiceRow(@"Style", nil, SGRKeyVisualizerStyle, @[@"Spectrum", @"Waveform"], 0);
    style.chosen = ^(NSInteger index) { notify(); };
    SGModRow *intensity = SGSliderRow(@"Intensity", nil, 10, 100, 5, ^double {
        id value = [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyVisualizerIntensity];
        double amount = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.5;
        return isfinite(amount) ? MIN(100, MAX(10, amount * 100)) : 50;
    }, ^(double value) {
        [NSUserDefaults.standardUserDefaults setDouble:value / 100 forKey:SGRKeyVisualizerIntensity]; notify();
    }, ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value]; });
    style.visible = intensity.visible = ^BOOL { return SGFlag(SGRKeyVisualizer, NO); };
    return SGNotedSection(@"Visualizer", @[enabled, style, intensity], @"Applies immediately. Uses audio played by this iPhone; remote Spotify Connect playback has no visualizer. Rests while paused, off screen, in Low Power Mode or with Reduce Motion.");
}
