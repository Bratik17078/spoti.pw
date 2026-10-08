// Head gestures from compatible AirPods and Beats headphones. The motion manager only provides
// samples while a supported headset is reporting head motion, which keeps this separate from the
// iPhone's own motion sensors.
#import <UIKit/UIKit.h>
#import "Shared/Gestures/Gestures.h"

#define SGKeyHeadGestures @"spotifyglass.headGestures"
#define SGKeyHeadGestureNodAction @"spotifyglass.headGestures.nodAction"
#define SGKeyHeadGestureShakeAction @"spotifyglass.headGestures.shakeAction"

typedef NS_ENUM(NSInteger, SGHeadGesture) {
    SGHeadGestureNod = 0,
    SGHeadGestureShake,
};

// The same action list as player double taps. Invalid saved values safely mean Nothing.
SGGestureAction SGHeadGestureAction(SGHeadGesture gesture);
NSString *SGHeadGestureStatus(void);
// Re-evaluates the listener immediately after the settings switch changes or a route changes.
void SGHeadGesturesRefresh(void);

// The practice page receives normalized head position on the main thread: -1...1 across and down.
// Opening it suspends actions, so practising can never change the current song.
void SGHeadGesturesBeginPractice(void (^handler)(CGFloat horizontal, CGFloat vertical, BOOL connected));
void SGHeadGesturesEndPractice(void);

UIViewController *SGHeadGesturesSettingsPage(void);
