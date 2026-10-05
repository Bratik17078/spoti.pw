// Player redesign: Next and Previous move the song's title and artist the same way as the Lock
// Screen's now playing card. Spotify's cover is already a horizontal paging list, so it keeps its
// own directional movement; this fills in the metadata beside it instead of animating the cover a
// second time. Next sends the old words left and brings the new ones from the right, Previous mirrors
// that path. The artwork field keeps its own crossfade.
//
// The old information unit is snapshotted before Spotify changes it. Once the new track is reported,
// the snapshot leaves while an additive Core Animation brings the rebuilt unit in. The model transform
// is never changed, so PlayerLyrics.x can keep lifting that same unit and a layout pass cannot cut the
// transition short. A second skip replaces the pending snapshot and never locks the controls.
//
// Reduce Motion keeps the state change visible as a short crossfade without horizontal travel.
//
// Selectors: SPTNowPlayingPlaybackControllerImplementation's two skip selectors are declared in
// Headers/SPTNowPlayingPlaybackController.h and already driven by Shared/Gestures and ArtistBlock.
// View: trees/clean/player/01.txt:160 is InformationElementsUnit, with the title and artist together.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/PlayerState.h"
#import "Headers/SPTNowPlayingPlaybackController.h"

typedef NS_ENUM(NSInteger, SGRTrackDirection) {
    SGRTrackDirectionNone,
    SGRTrackDirectionPrevious = -1,
    SGRTrackDirectionNext = 1,
};

static const NSTimeInterval kTransitionTimeout = 2.5;
static const CGFloat kMinimumTravel = 24, kMaximumTravel = 40;
static NSString *const kArrivalAnimation = @"spotifyglass.trackArrival";

static __weak UIView *sg_information;
static UIView *sg_departing;
static NSString *sg_departingTrack, *sg_arrivingTrack;
static SGRTrackDirection sg_direction;
static NSUInteger sg_generation;
static BOOL sg_running;

static void clearPending(BOOL removeArrival) {
    if (removeArrival) [sg_information.layer removeAnimationForKey:kArrivalAnimation];
    [sg_departing removeFromSuperview];
    sg_departing = nil;
    sg_departingTrack = nil;
    sg_arrivingTrack = nil;
    sg_direction = SGRTrackDirectionNone;
    sg_running = NO;
}

static CGFloat travelFor(UIView *view) {
    return MIN(kMaximumTravel, MAX(kMinimumTravel, view.bounds.size.width * 0.09));
}

// The metadata's model state stays where layout put it. Only its presentation receives the arrival,
// which composes with the vertical transform used while lyrics are open.
static void animateArrival(UIView *view, CGFloat from, CFTimeInterval duration) {
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0;
    fade.toValue = @1;
    fade.duration = MIN(duration, 0.24);
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];

    NSMutableArray<CAAnimation *> *animations = [NSMutableArray arrayWithObject:fade];
    if (!SGRReduceMotion()) {
        CASpringAnimation *slide = [CASpringAnimation animationWithKeyPath:@"transform.translation.x"];
        slide.fromValue = @(from);
        slide.toValue = @0;
        slide.additive = YES;
        slide.mass = 1;
        slide.stiffness = 280;
        slide.damping = 34;
        slide.initialVelocity = 0;
        slide.duration = duration;
        [animations addObject:slide];
    }

    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = animations;
    group.duration = duration;
    [view.layer addAnimation:group forKey:kArrivalAnimation];
}

static void beginTransitionIfReady(void) {
    UIView *information = sg_information;
    UIView *departing = sg_departing;
    if (sg_running || !information.window || !departing.window || !sg_arrivingTrack.length) return;
    NSString *current = SGURIString(SGPlayerState().track.URI);
    if (![current isEqualToString:sg_arrivingTrack]) return;
    sg_running = YES;

    NSUInteger generation = sg_generation;
    CGFloat travel = travelFor(information);
    CGFloat arrival = sg_direction == SGRTrackDirectionNext ? travel : -travel;
    CGFloat departure = -arrival;
    NSTimeInterval duration = SGRReduceMotion() ? 0.2 : 0.38;
    animateArrival(information, arrival, duration);

    [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:1 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        departing.alpha = 0;
        if (!SGRReduceMotion()) departing.transform = CGAffineTransformMakeTranslation(departure, 0);
    } completion:^(BOOL finished) {
        if (sg_generation == generation) clearPending(NO);
        else [departing removeFromSuperview];
    }];
}

static void prepareTransition(SGRTrackDirection direction) {
    dispatch_block_t prepare = ^{
        UIView *information = sg_information;
        UIWindow *window = information.window;
        if (!information || !window || SGRPlayerIsTransitioning()) return;

        clearPending(YES);
        UIView *snapshot = [information snapshotViewAfterScreenUpdates:NO];
        NSString *track = SGURIString(SGPlayerState().track.URI);
        if (!snapshot || !track.length) return;
        snapshot.frame = [window convertRect:information.bounds fromView:information];
        snapshot.userInteractionEnabled = NO;
        [window addSubview:snapshot];

        sg_departing = snapshot;
        sg_departingTrack = track;
        sg_direction = direction;
        NSUInteger generation = ++sg_generation;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTransitionTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (sg_generation == generation && sg_departing) clearPending(YES);
        });
    };
    if (NSThread.isMainThread) prepare();
    else dispatch_async(dispatch_get_main_queue(), prepare);
}

@interface SGRPlayerTrackTransitionWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerTrackTransitionWatcher

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = SGURIString(state.track.URI);
    if (!sg_departing || !track.length || [track isEqualToString:sg_departingTrack]) return;
    sg_arrivingTrack = track;
    // Spotify rebuilds the two labels from this state on the same run-loop turn. The unit's layout
    // hook below normally starts the transition; this fallback covers a label update needing no layout.
    dispatch_async(dispatch_get_main_queue(), ^{
        [sg_information.superview layoutIfNeeded];
        beginTransitionIfReady();
    });
}

@end

static SGRPlayerTrackTransitionWatcher *sg_watcher;

%hook _TtC20NowPlaying_ModesImpl23InformationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_information = ((UIViewController *)self).viewIfLoaded;
    beginTransitionIfReady();
}
%end

%hook SPTNowPlayingPlaybackControllerImplementation
- (void)skipToNextWhileDragging:(BOOL)dragging {
    if (!dragging) prepareTransition(SGRTrackDirectionNext);
    %orig;
}
- (void)skipToPreviousWhileDragging:(BOOL)dragging {
    if (!dragging) prepareTransition(SGRTrackDirectionPrevious);
    %orig;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    sg_watcher = [SGRPlayerTrackTransitionWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
    SGRequireClasses(@[
        @"_TtC20NowPlaying_ModesImpl23InformationElementsUnit",
        @"SPTNowPlayingPlaybackControllerImplementation",
    ]);
}
