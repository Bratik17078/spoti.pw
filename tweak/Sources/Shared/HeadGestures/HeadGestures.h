// Head gestures from compatible AirPods and Beats headphones. The motion manager only provides
// samples while a supported headset is reporting head motion, which keeps this separate from the
// iPhone's own motion sensors.
#import <UIKit/UIKit.h>
#import "Shared/Gestures/Gestures.h"

#define SGKeyHeadGestures @"spotifyglass.headGestures"
#define SGKeyHeadGestureNodAction @"spotifyglass.headGestures.nodAction"
#define SGKeyHeadGestureShakeAction @"spotifyglass.headGestures.shakeAction"
#define SGKeyHeadGestureNodOnceAction @"spotifyglass.headGestures.nodOnceAction"
#define SGKeyHeadGestureTiltLeftAction @"spotifyglass.headGestures.tiltLeftAction"
#define SGKeyHeadGestureTiltRightAction @"spotifyglass.headGestures.tiltRightAction"
#define SGKeyHeadGestureSensitivity @"spotifyglass.headGestures.sensitivity"

typedef NS_ENUM(NSInteger, SGHeadGesture) {
    SGHeadGestureNod = 0,
    SGHeadGestureShake,
    SGHeadGestureNodOnce,
    SGHeadGestureTiltLeft,
    SGHeadGestureTiltRight,
};

// The same action list as player double taps. Invalid saved values safely mean Nothing.
SGGestureAction SGHeadGestureAction(SGHeadGesture gesture);
NSInteger SGHeadGestureSensitivity(void);  // 1–5; 2 is the calmer default
NSString *SGHeadGestureStatus(void);
// Re-evaluates the listener immediately after the settings switch changes or a route changes.
void SGHeadGesturesRefresh(void);

// The practice page receives normalized head position on the main thread: -1...1 across and down.
// Opening it suspends actions, so practising can never change the current song.
void SGHeadGesturesBeginPractice(void (^handler)(CGFloat horizontal, CGFloat vertical, BOOL connected));
void SGHeadGesturesEndPractice(void);
void SGHeadGesturesRecenter(void);

UIViewController *SGHeadGesturesSettingsPage(void);
