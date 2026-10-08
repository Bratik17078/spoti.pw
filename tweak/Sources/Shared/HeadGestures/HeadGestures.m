// Detect two nods or one left-right shake from CMHeadphoneMotionManager. This is deliberately
// driven only by headphone motion -- never CMMotionManager -- so moving the phone cannot trigger
// playback. Apple does not expose AirPods' in-ear sensor to third-party apps; an active headphone
// motion stream is therefore the public signal that a compatible pair is being worn and usable.
#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>
#import <math.h>
#import "Core/SGCore.h"
#import "HeadGestures.h"

static const CGFloat kGestureThreshold = 0.25;       // radians from the relaxed head position
static const NSTimeInterval kSequenceWindow = 1.45;
static const NSTimeInterval kCooldown = 1.7;

static CGFloat clamp(CGFloat value, CGFloat lower, CGFloat upper) {
    return MIN(MAX(value, lower), upper);
}

// Keeps angular differences continuous as yaw goes from pi to -pi.
static CGFloat angleDelta(CGFloat angle, CGFloat origin) {
    CGFloat delta = angle - origin;
    while (delta > M_PI) delta -= (CGFloat)(2 * M_PI);
    while (delta < -M_PI) delta += (CGFloat)(2 * M_PI);
    return delta;
}

SGGestureAction SGHeadGestureAction(SGHeadGesture gesture) {
    NSString *key = gesture == SGHeadGestureNod ? SGKeyHeadGestureNodAction : SGKeyHeadGestureShakeAction;
    NSInteger value = SGInt(key, SGGestureNothing);
    return value >= SGGestureNothing && value < (NSInteger)SGGestureActionNames().count
        ? (SGGestureAction)value : SGGestureNothing;
}

@interface SGHeadGestureEngine : NSObject <CMHeadphoneMotionManagerDelegate>
@property (nonatomic, strong) CMHeadphoneMotionManager *manager;
@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, copy) void (^practiceHandler)(CGFloat horizontal, CGFloat vertical, BOOL connected);
@property (nonatomic) NSInteger practiceCount;
@property (nonatomic) BOOL calibrated;
@property (nonatomic) CGFloat pitchOrigin, yawOrigin;
@property (nonatomic) NSInteger nodSign, shakeSign, nodPeaks, shakePeaks;
@property (nonatomic) NSTimeInterval nodPeakAt, shakePeakAt, lastActionAt;
@property (nonatomic, strong) NSDate *lastSampleAt;
@property (nonatomic) BOOL headphonesConnected;
- (void)refresh;
- (NSString *)status;
- (void)receivedPitch:(CGFloat)pitch yaw:(CGFloat)yaw;
- (void)observe:(CGFloat)value gesture:(SGHeadGesture)gesture;
@end

@implementation SGHeadGestureEngine

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _manager = [CMHeadphoneMotionManager new];
    _queue = [NSOperationQueue new];
    _queue.name = @"pw.spoti.head-gestures";
    _queue.maxConcurrentOperationCount = 1;
    _manager.delegate = self;
    [_manager startConnectionStatusUpdates];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(routeChanged:)
                                                 name:AVAudioSessionRouteChangeNotification object:nil];
    return self;
}

- (void)routeChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
}

- (void)headphoneMotionManagerDidConnect:(CMHeadphoneMotionManager *)manager {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.headphonesConnected = YES;
        [self refresh];
    });
}

- (void)headphoneMotionManagerDidDisconnect:(CMHeadphoneMotionManager *)manager {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.headphonesConnected = NO;
        self.calibrated = NO;
        self.nodPeaks = self.shakePeaks = 0;
        if (self.practiceHandler) self.practiceHandler(0, 0, NO);
    });
}

- (BOOL)shouldListen {
    return SGFlag(SGKeyHeadGestures, NO) || _practiceCount > 0;
}

- (void)refresh {
    if (![self shouldListen]) {
        if (_manager.deviceMotionActive) [_manager stopDeviceMotionUpdates];
        _calibrated = NO;
        return;
    }
    if (!_manager.deviceMotionAvailable || _manager.deviceMotionActive) return;
    _calibrated = NO;
    _manager.deviceMotionUpdateInterval = 1.0 / 60.0;
    __weak typeof(self) weakSelf = self;
    [_manager startDeviceMotionUpdatesToQueue:_queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (!motion || error) return;
        CGFloat pitch = motion.attitude.pitch;
        CGFloat yaw = motion.attitude.yaw;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf receivedPitch:pitch yaw:yaw]; });
    }];
}

- (NSString *)status {
    if (!_manager.deviceMotionAvailable || !_headphonesConnected) return @"No compatible AirPods detected";
    if (!_lastSampleAt || -[_lastSampleAt timeIntervalSinceNow] > 2) return @"Waiting for head motion";
    return @"Connected";
}

- (void)receivedPitch:(CGFloat)pitch yaw:(CGFloat)yaw {
    // A pair may already be connected before we begin listening, in which case the delegate does
    // not necessarily get a new connect edge. A genuine headphone-motion sample is definitive.
    _headphonesConnected = YES;
    _lastSampleAt = NSDate.date;
    if (!_calibrated) {
        _calibrated = YES;
        _pitchOrigin = pitch;
        _yawOrigin = yaw;
    }
    CGFloat relativePitch = angleDelta(pitch, _pitchOrigin);
    CGFloat relativeYaw = angleDelta(yaw, _yawOrigin);
    // Re-centre only while the head is at rest. It follows a comfortable new posture but never
    // eats the deliberate part of a nod or shake.
    if (fabs(relativePitch) < 0.07) _pitchOrigin += relativePitch * 0.012;
    if (fabs(relativeYaw) < 0.07) _yawOrigin += relativeYaw * 0.012;

    if (_practiceHandler) _practiceHandler(clamp(relativeYaw / 0.55, -1, 1), clamp(relativePitch / 0.55, -1, 1), YES);
    if (!SGFlag(SGKeyHeadGestures, NO) || _practiceCount > 0) return;
    [self observe:relativePitch gesture:SGHeadGestureNod];
    [self observe:relativeYaw gesture:SGHeadGestureShake];
}

- (void)observe:(CGFloat)value gesture:(SGHeadGesture)gesture {
    if (fabs(value) < kGestureThreshold) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSInteger sign = value > 0 ? 1 : -1;
    NSInteger *lastSign = gesture == SGHeadGestureNod ? &_nodSign : &_shakeSign;
    NSInteger *peaks = gesture == SGHeadGestureNod ? &_nodPeaks : &_shakePeaks;
    NSTimeInterval *lastPeakAt = gesture == SGHeadGestureNod ? &_nodPeakAt : &_shakePeakAt;
    if (sign == *lastSign) return;
    if (now - *lastPeakAt > kSequenceWindow) *peaks = 0;
    *lastSign = sign;
    *lastPeakAt = now;
    *peaks += 1;
    // A nod is down-up-down-up (two nods); a shake is left-right once. Each must be alternating.
    NSInteger requiredPeaks = gesture == SGHeadGestureNod ? 4 : 2;
    if (*peaks < requiredPeaks || now - _lastActionAt < kCooldown) return;
    _lastActionAt = now;
    *peaks = 0;
    SGGestureAction action = SGHeadGestureAction(gesture);
    if (action != SGGestureNothing) SGPerformGestureAction(action);
}

@end

static SGHeadGestureEngine *engine(void) {
    static SGHeadGestureEngine *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SGHeadGestureEngine new]; });
    return shared;
}

NSString *SGHeadGestureStatus(void) {
    return engine().status;
}

void SGHeadGesturesRefresh(void) {
    [engine() refresh];
}

void SGHeadGesturesBeginPractice(void (^handler)(CGFloat horizontal, CGFloat vertical, BOOL connected)) {
    SGHeadGestureEngine *shared = engine();
    shared.practiceCount += 1;
    shared.practiceHandler = handler;
    [shared refresh];
    if (handler) handler(0, 0, [shared.status isEqualToString:@"Connected"]);
}

void SGHeadGesturesEndPractice(void) {
    SGHeadGestureEngine *shared = engine();
    shared.practiceCount = MAX(0, shared.practiceCount - 1);
    if (!shared.practiceCount) shared.practiceHandler = nil;
    [shared refresh];
}

%ctor {
    // Route-change notifications wake the listener if AirPods connect later; no private Bluetooth or
    // in-ear APIs are used.
    [engine() refresh];
}
