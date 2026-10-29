// Rapid skips are a destination in a snapshot of the queue, not several commands against the same
// stale player state. Keep one command in flight; further taps/swipes move the destination. Once
// the player acknowledges it, jump straight to the latest future track (the same API LiveActivity
// uses), or walk history one acknowledged step at a time. Never retry a command that timed out.
//
// Selectors are already used by Shared/LiveActivity and Shared/Gestures and declared in Headers/.
// No collection-view delegate is replaced: Spotify retains its paging, accessibility and gestures.
#import "Core/SGCore.h"
#import "Headers/SPTNowPlayingPlaybackController.h"
#import "Shared/Player/PlayerState.h"

static char kSkipQueueKey;

@interface SGRPlayerSkipQueue : NSObject
- (instancetype)initWithPlayer:(id)player;
- (BOOL)requestNext:(BOOL)next dragging:(BOOL)dragging;
@end

@implementation SGRPlayerSkipQueue {
    __weak id<SPTPlayer> _player;
    NSArray<SPTPlayerTrack *> *_tracks;
    NSString *_context;
    NSInteger _current, _destination, _sent;
    BOOL _inFlight, _restarting, _mayRestart;
    SPTPlayerState *_issuedState;
    CFTimeInterval _sentAt;
    NSTimer *_timer;
}

- (instancetype)initWithPlayer:(id)player {
    if (!(self = [super init])) return nil;
    _player = player;
    return self;
}

- (void)reset {
    [_timer invalidate];
    _timer = nil;
    _tracks = nil;
    _context = nil;
    _issuedState = nil;
    _inFlight = _restarting = _mayRestart = NO;
}

- (BOOL)takeSnapshot:(SPTPlayerState *)state {
    Class trackClass = NSClassFromString(@"SPTPlayerTrack");
    if (![state.track isKindOfClass:trackClass]) return NO;
    NSMutableArray *tracks = [NSMutableArray array];
    NSArray *reverse = [state.reverse isKindOfClass:NSArray.class] ? state.reverse : @[];
    for (id track in reverse.reverseObjectEnumerator) {
        if ([track isKindOfClass:trackClass]) [tracks addObject:track];
    }
    _current = _destination = (NSInteger)tracks.count;
    [tracks addObject:state.track];
    NSArray *future = [state.future isKindOfClass:NSArray.class] ? state.future : @[];
    for (id track in future) {
        if ([track isKindOfClass:trackClass]) [tracks addObject:track];
    }
    _tracks = tracks;
    _context = SGURIString(state.contextURI);
    return YES;
}

- (BOOL)requestNext:(BOOL)next dragging:(BOOL)dragging {
    // Do not swallow an unsupported player's action. All coordinator state and player commands run
    // on main; Spotify's own path remains available for a background caller.
    id<SPTPlayer> player = _player;
    if (!NSThread.isMainThread || ![player respondsToSelector:@selector(state)]
        || ![player respondsToSelector:@selector(skipToNextTrackWithOptions:track:)]
        || ![player respondsToSelector:@selector(skipToPreviousTrackWithOptions:)]) return NO;
    SPTPlayerState *state = player.state;
    NSString *context = SGURIString(state.contextURI);
    if (_tracks && !(_context == context || [_context isEqualToString:context])) [self reset];
    if (!_tracks && ![self takeSnapshot:state]) return NO;

    // A lone Previous tap retains Spotify's restart-current-song behavior. Swiping backwards always
    // selects the previous cover. Further input during a restart is still relative to this track.
    BOOL restart = !next && !dragging && !_inFlight && state.position > 3;
    NSInteger wanted = _destination + (next ? 1 : -1);
    if (!restart && (wanted < 0 || wanted >= (NSInteger)_tracks.count)) {
        if (_inFlight) return YES; // the known end of this queue, with a command still outstanding
        [self reset];
        return NO; // preserve Spotify's repeat/autoplay handling beyond the snapshot
    }
    if (!restart) _destination = wanted;
    if (!_inFlight) [self sendRestart:restart];
    if (_tracks && !_timer) {
        __weak SGRPlayerSkipQueue *weakSelf = self;
        _timer = [NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) {
            SGRPlayerSkipQueue *queue = weakSelf;
            if (queue) [queue check];
            else [timer invalidate];
        }];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    }
    return YES;
}

- (void)sendRestart:(BOOL)restart {
    id<SPTPlayer> player = _player;
    SPTPlayerState *state = player.state;
    if (!restart && _destination == _current) { [self reset]; return; }
    _restarting = restart;
    _issuedState = state;
    _mayRestart = !restart && _destination < _current && state.position > 3;
    _sent = restart ? _current : _destination > _current ? _destination : _current - 1;
    _sentAt = CACurrentMediaTime();
    _inFlight = YES; // set before issuing: an observer may run synchronously
    if (_sent > _current) {
        SPTPlayerTrack *target = _tracks[(NSUInteger)_sent];
        // Use the fresh queue object, not a stale object after Spotify rebuilt the queue.
        NSArray *future = [state.future isKindOfClass:NSArray.class] ? state.future : @[];
        NSUInteger index = [future indexOfObjectIdenticalTo:target];
        if (index == NSNotFound) {
            NSString *uri = SGURIString(target.URI);
            for (NSUInteger i = 0; i < future.count; i++) {
                id candidate = future[i];
                if ([candidate respondsToSelector:@selector(URI)] && [SGURIString([candidate URI]) isEqualToString:uri]) {
                    index = i;
                    break;
                }
            }
        }
        if (index == NSNotFound) { [self reset]; return; }
        [player skipToNextTrackWithOptions:nil track:future[index]];
    } else {
        [player skipToPreviousTrackWithOptions:nil];
    }
}

- (void)check {
    id<SPTPlayer> player = _player;
    if (!player || !_tracks) { [self reset]; return; }
    SPTPlayerState *state = player.state;
    NSString *context = SGURIString(state.contextURI);
    if (!(_context == context || [_context isEqualToString:context])) { [self reset]; return; }
    NSString *expected = SGURIString(_tracks[(NSUInteger)_sent].URI);
    NSString *actual = SGURIString(state.track.URI);
    // Consecutive queue entries can be the same song. A position update on the old entry must not
    // acknowledge the new one merely because its URI matches.
    BOOL changedEntry = _sent == _current || state.track != _issuedState.track;
    if (state != _issuedState && changedEntry && !state.isLoading && [actual isEqualToString:expected] && (!_restarting || state.position < 1)) {
        _current = _sent;
        _inFlight = _restarting = NO;
        [self sendRestart:NO];
    } else if (_mayRestart && state != _issuedState && !state.isLoading && state.position < 1
               && [actual isEqualToString:SGURIString(_tracks[(NSUInteger)_current].URI)]) {
        // Previous may first restart the current track. A swipe chose the previous cover, so send
        // the history step only after that restart was acknowledged, never alongside a seek.
        _mayRestart = NO;
        _issuedState = state;
        _sentAt = CACurrentMediaTime();
        [player skipToPreviousTrackWithOptions:nil];
    } else if (CACurrentMediaTime() - _sentAt > 6) {
        SGLog(@"redesign skip: player did not acknowledge %@; pending selection cleared", expected);
        [self reset];
    }
}

- (void)dealloc {
    [_timer invalidate];
}

@end

%hook SPTNowPlayingPlaybackControllerImplementation
- (id)initWithPlayer:(id)player testManager:(id)manager inStreamClient:(id)client {
    id controller = %orig;
    if (controller) objc_setAssociatedObject(controller, &kSkipQueueKey,
        [[SGRPlayerSkipQueue alloc] initWithPlayer:player], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return controller;
}
- (void)skipToNextWhileDragging:(BOOL)dragging {
    SGRPlayerSkipQueue *queue = objc_getAssociatedObject(self, &kSkipQueueKey);
    if (![queue requestNext:YES dragging:dragging]) %orig;
}
- (void)skipToPreviousWhileDragging:(BOOL)dragging {
    SGRPlayerSkipQueue *queue = objc_getAssociatedObject(self, &kSkipQueueKey);
    if (![queue requestNext:NO dragging:dragging]) %orig;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"SPTNowPlayingPlaybackControllerImplementation"]);
}
