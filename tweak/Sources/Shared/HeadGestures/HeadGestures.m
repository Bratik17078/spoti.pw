// Detect nods, shakes and head tilts from CMHeadphoneMotionManager. This is deliberately
// driven only by headphone motion -- never CMMotionManager -- so moving the phone cannot trigger
// playback. Apple does not expose AirPods' in-ear sensor to third-party apps; an active headphone
// motion stream is therefore the public signal that a compatible pair is being worn and usable.
#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>
#import <math.h>
#import "Core/SGCore.h"
#import "HeadGestures.h"

static const NSTimeInterval kNodWindow = 0.9;
static const NSTimeInterval kShakeWindow = 1.2;
static const NSTimeInterval kCooldown = 0.85;

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
    NSString *key;
    switch (gesture) {
        case SGHeadGestureNod: key = SGKeyHeadGestureNodAction; break;
        case SGHeadGestureShake: key = SGKeyHeadGestureShakeAction; break;
        case SGHeadGestureNodOnce: key = SGKeyHeadGestureNodOnceAction; break;
        case SGHeadGestureTiltLeft: key = SGKeyHeadGestureTiltLeftAction; break;
        case SGHeadGestureTiltRight: key = SGKeyHeadGestureTiltRightAction; break;
        default: return SGGestureNothing;
    }
    NSInteger value = SGInt(key, SGGestureNothing);
    return value >= SGGestureNothing && value < (NSInteger)SGGestureActionNames().count
        ? (SGGestureAction)value : SGGestureNothing;
}

NSInteger SGHeadGestureSensitivity(void) {
    return MAX(1, MIN(5, SGInt(SGKeyHeadGestureSensitivity, 2)));
}

// A higher sensitivity needs less head movement. The former fixed threshold was 0.25 rad;
// the new default is 0.36 rad, leaving normal posture changes alone.
static CGFloat threshold(void) {
    return (CGFloat)(0.48 - 0.06 * SGHeadGestureSensitivity());
}

@interface SGHeadGestureEngine : NSObject <CMHeadphoneMotionManagerDelegate>
@property (nonatomic, strong) CMHeadphoneMotionManager *manager;
@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, copy) void (^practiceHandler)(CGFloat horizontal, CGFloat vertical, BOOL connected);
@property (nonatomic) NSInteger practiceCount;
@property (nonatomic) BOOL calibrated;
@property (nonatomic) CGFloat pitchOrigin, yawOrigin, rollOrigin;
@property (nonatomic) BOOL nodExtended, shakeAwaitNeutral, tiltFired;
@property (nonatomic) NSInteger nodCount, shakeSign, tiltSign;
@property (nonatomic) NSUInteger nodToken;
@property (nonatomic) NSTimeInterval nodStartedAt, nodFirstAt, shakePeakAt, tiltStartedAt, lastActionAt;
@property (nonatomic, strong) NSDate *lastSampleAt;
@property (nonatomic) BOOL headphonesConnected;
- (void)refresh;
- (NSString *)status;
- (void)receivedPitch:(CGFloat)pitch yaw:(CGFloat)yaw roll:(CGFloat)roll;
- (void)observeNod:(CGFloat)pitch at:(NSTimeInterval)now threshold:(CGFloat)limit;
- (void)observeShake:(CGFloat)yaw at:(NSTimeInterval)now threshold:(CGFloat)limit;
- (void)observeTilt:(CGFloat)roll at:(NSTimeInterval)now threshold:(CGFloat)limit;
- (void)performGesture:(SGHeadGesture)gesture at:(NSTimeInterval)now;
- (void)recenter;
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
        [self recenter];
        if (self.practiceHandler) self.practiceHandler(0, 0, NO);
    });
}

- (BOOL)shouldListen {
    return SGFlag(SGKeyHeadGestures, NO) || _practiceCount > 0;
}

- (void)refresh {
    if (![self shouldListen]) {
        if (_manager.deviceMotionActive) [_manager stopDeviceMotionUpdates];
        [self recenter];
        return;
    }
    if (!_manager.deviceMotionAvailable || _manager.deviceMotionActive) return;
    [self recenter];
    __weak typeof(self) weakSelf = self;
    [_manager startDeviceMotionUpdatesToQueue:_queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (!motion || error) return;
        CGFloat pitch = motion.attitude.pitch;
        CGFloat yaw = motion.attitude.yaw;
        CGFloat roll = motion.attitude.roll;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf receivedPitch:pitch yaw:yaw roll:roll]; });
    }];
}

- (NSString *)status {
    if (!_manager.deviceMotionAvailable || !_headphonesConnected) return @"No compatible AirPods detected";
    if (!_lastSampleAt || -[_lastSampleAt timeIntervalSinceNow] > 2) return @"Waiting for head motion";
    return @"Connected";
}

- (void)recenter {
    _calibrated = NO;
    _nodExtended = NO;
    _nodCount = 0;
    _nodToken++;
    _shakeSign = 0;
    _shakeAwaitNeutral = NO;
    _tiltSign = 0;
    _tiltFired = NO;
}

- (void)receivedPitch:(CGFloat)pitch yaw:(CGFloat)yaw roll:(CGFloat)roll {
    // A pair may already be connected before we begin listening, in which case the delegate does
    // not necessarily get a new connect edge. A genuine headphone-motion sample is definitive.
    _headphonesConnected = YES;
    _lastSampleAt = NSDate.date;
    if (!_calibrated) {
        _calibrated = YES;
        _pitchOrigin = pitch;
        _yawOrigin = yaw;
        _rollOrigin = roll;
    }
    CGFloat relativePitch = angleDelta(pitch, _pitchOrigin);
    CGFloat relativeYaw = angleDelta(yaw, _yawOrigin);
    CGFloat relativeRoll = angleDelta(roll, _rollOrigin);
    // Re-centre only while the head is at rest. It follows a comfortable new posture but never
    // eats the deliberate part of a nod or shake.
    if (fabs(relativePitch) < 0.07) _pitchOrigin += relativePitch * 0.012;
    if (fabs(relativeYaw) < 0.07) _yawOrigin += relativeYaw * 0.012;
    if (fabs(relativeRoll) < 0.07) _rollOrigin += relativeRoll * 0.012;

    // A full sweep of the practice circle takes a deliberately broad movement. Calibration is
    // refreshed on entry and on Recenter, so the resting head starts at the middle.
    if (_practiceHandler) _practiceHandler(clamp(relativeYaw / 0.9, -1, 1), clamp(relativePitch / 0.9, -1, 1), YES);
    if (!SGFlag(SGKeyHeadGestures, NO) || _practiceCount > 0) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    CGFloat limit = threshold();
    [self observeNod:relativePitch at:now threshold:limit];
    [self observeShake:relativeYaw at:now threshold:limit];
    [self observeTilt:relativeRoll at:now threshold:limit];
}

- (void)performGesture:(SGHeadGesture)gesture at:(NSTimeInterval)now {
    SGGestureAction action = SGHeadGestureAction(gesture);
    if (action == SGGestureNothing || now - _lastActionAt < kCooldown) return;
    _lastActionAt = now;
    SGPerformGestureAction(action);
}

- (void)observeNod:(CGFloat)pitch at:(NSTimeInterval)now threshold:(CGFloat)limit {
    if (!_nodExtended) {
        if (fabs(pitch) >= limit) {
            _nodExtended = YES;
            _nodStartedAt = now;
        }
        return;
    }
    if (fabs(pitch) > limit * 0.4) return;
    _nodExtended = NO;
    if (now - _nodStartedAt > 1.1) return; // a held pose is not a nod
    if (_nodCount && now - _nodFirstAt <= kNodWindow) {
        _nodCount = 0;
        _nodToken++; // cancels the pending single nod
        [self performGesture:SGHeadGestureNod at:now];
        return;
    }
    _nodCount = 1;
    _nodFirstAt = now;
    if (SGHeadGestureAction(SGHeadGestureNod) == SGGestureNothing) {
        [self performGesture:SGHeadGestureNodOnce at:now];
        _nodCount = 0;
        return;
    }
    NSUInteger token = ++_nodToken;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kNodWindow * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGHeadGestureEngine *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.nodToken != token || !strongSelf.nodCount) return;
        strongSelf.nodCount = 0;
        if (SGFlag(SGKeyHeadGestures, NO) && !strongSelf.practiceCount) {
            [strongSelf performGesture:SGHeadGestureNodOnce at:[NSDate timeIntervalSinceReferenceDate]];
        }
    });
}

- (void)observeShake:(CGFloat)yaw at:(NSTimeInterval)now threshold:(CGFloat)limit {
    if (_shakeAwaitNeutral) {
        if (fabs(yaw) < limit * 0.4) {
            _shakeAwaitNeutral = NO;
            _shakeSign = 0;
        }
        return;
    }
    if (fabs(yaw) < limit) return;
    NSInteger sign = yaw > 0 ? 1 : -1;
    if (_shakeSign == sign) return;
    if (_shakeSign && now - _shakePeakAt <= kShakeWindow) {
        _shakeAwaitNeutral = YES;
        [self performGesture:SGHeadGestureShake at:now];
    }
    _shakeSign = sign;
    _shakePeakAt = now;
}

- (void)observeTilt:(CGFloat)roll at:(NSTimeInterval)now threshold:(CGFloat)limit {
    if (fabs(roll) < limit * 0.4) {
        _tiltSign = 0;
        _tiltFired = NO;
        return;
    }
    if (fabs(roll) < limit) return;
    NSInteger sign = roll > 0 ? 1 : -1;
    if (_tiltSign != sign) {
        _tiltSign = sign;
        _tiltStartedAt = now;
        _tiltFired = NO;
    }
    if (!_tiltFired && now - _tiltStartedAt >= 0.22) {
        _tiltFired = YES;
        [self performGesture:sign < 0 ? SGHeadGestureTiltLeft : SGHeadGestureTiltRight at:now];
    }
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
    [shared recenter];
    [shared refresh];
    if (handler) handler(0, 0, [shared.status isEqualToString:@"Connected"]);
}

void SGHeadGesturesEndPractice(void) {
    SGHeadGestureEngine *shared = engine();
    shared.practiceCount = MAX(0, shared.practiceCount - 1);
    if (!shared.practiceCount) shared.practiceHandler = nil;
    [shared recenter];
    [shared refresh];
}

void SGHeadGesturesRecenter(void) {
    SGHeadGestureEngine *shared = engine();
    [shared recenter];
    if (shared.practiceHandler) shared.practiceHandler(0, 0, [shared.status isEqualToString:@"Connected"]);
}
