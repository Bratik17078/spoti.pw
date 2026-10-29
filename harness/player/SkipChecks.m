// Drive the real coordinator with a player that acknowledges commands only when told. A burst
// must not issue overlapping commands, lose its destination, or continue after the context changed.
#import <Foundation/Foundation.h>
#import "Headers/SPTPlayer.h"

@interface SGRPlayerSkipQueue : NSObject
- (instancetype)initWithPlayer:(id)player;
- (BOOL)requestNext:(BOOL)next dragging:(BOOL)dragging;
- (void)check;
- (void)reset;
@end

@interface SGRSkipTestTrack : SPTPlayerTrack
@property (nonatomic, copy) NSString *testURI;
@end
@implementation SGRSkipTestTrack
- (id)URI { return _testURI; }
@end

@interface SGRSkipTestState : SPTPlayerState
@property (nonatomic, strong) SPTPlayerTrack *testTrack;
@property (nonatomic, copy) NSArray *testFuture, *testReverse;
@property (nonatomic, copy) NSString *testContext;
@property (nonatomic) BOOL testLoading;
@property (nonatomic) double testPosition;
@end
@implementation SGRSkipTestState
- (SPTPlayerTrack *)track { return _testTrack; }
- (NSArray *)future { return _testFuture; }
- (NSArray *)reverse { return _testReverse; }
- (id)contextURI { return _testContext; }
- (BOOL)isLoading { return _testLoading; }
- (double)position { return _testPosition; }
@end

@interface SGRSkipTestPlayer : NSObject
@property (nonatomic, strong) SGRSkipTestState *state;
@property (nonatomic, copy) NSArray *tracks;
@property (nonatomic, strong) SPTPlayerTrack *pending;
@property (nonatomic) NSUInteger commands, index;
- (void)acknowledge;
@end
@implementation SGRSkipTestPlayer
- (instancetype)init {
    if (!(self = [super init])) return nil;
    NSMutableArray *tracks = [NSMutableArray array];
    for (NSString *name in @[@"A", @"B", @"C", @"D"]) {
        SGRSkipTestTrack *track = [SGRSkipTestTrack new];
        track.testURI = name;
        [tracks addObject:track];
    }
    _tracks = tracks;
    [self acknowledge];
    return self;
}
- (void)acknowledge {
    if (_pending) _index = [_tracks indexOfObjectIdenticalTo:_pending];
    _pending = nil;
    SGRSkipTestState *state = [SGRSkipTestState new];
    state.testTrack = _tracks[_index];
    state.testFuture = [_tracks subarrayWithRange:NSMakeRange(_index + 1, _tracks.count - _index - 1)];
    state.testReverse = [[_tracks subarrayWithRange:NSMakeRange(0, _index)] reverseObjectEnumerator].allObjects;
    state.testContext = @"queue";
    _state = state;
}
- (id)skipToNextTrackWithOptions:(id)options track:(SPTPlayerTrack *)track {
    NSCAssert(!_pending, @"overlapping playback commands");
    _commands++;
    _pending = track;
    return nil;
}
- (id)skipToPreviousTrackWithOptions:(id)options {
    NSCAssert(!_pending, @"overlapping playback commands");
    _commands++;
    _pending = _state.testPosition > 3 ? _state.track : _state.reverse.firstObject;
    return nil;
}
@end

void SGRHarnessCheckSkipping(void) {
    SGRSkipTestPlayer *player = [SGRSkipTestPlayer new];
    SGRPlayerSkipQueue *queue = [[SGRPlayerSkipQueue alloc] initWithPlayer:player];
    for (NSUInteger i = 0; i < 3; i++) NSCAssert([queue requestNext:YES dragging:YES], @"handled swipe");
    NSCAssert(player.commands == 1 && player.pending == player.tracks[1], @"only first command sent");
    [queue check];
    NSCAssert(player.commands == 1, @"unchanged state must not acknowledge");
    [player acknowledge];
    player.state.testLoading = YES;
    [queue check];
    NSCAssert(player.commands == 1, @"loading state must not acknowledge");
    player.state.testLoading = NO;
    [queue check];
    NSCAssert(player.commands == 2 && player.pending == player.tracks[3], @"burst selects D, not B");
    [player acknowledge];
    [queue check];
    [queue reset];

    // Reverse direction before the first command has finished: the last selection wins.
    player = [SGRSkipTestPlayer new];
    queue = [[SGRPlayerSkipQueue alloc] initWithPlayer:player];
    [queue requestNext:YES dragging:YES];
    [queue requestNext:YES dragging:YES];
    [queue requestNext:NO dragging:YES];
    [player acknowledge];
    [queue check];
    NSCAssert(player.index == 1 && player.commands == 1, @"reversal settles at B without an extra skip");
    [queue reset];

    // A backward swipe after the intro must continue past Previous's restart behavior.
    player.index = 3;
    [player acknowledge];
    player.state.testPosition = 20;
    queue = [[SGRPlayerSkipQueue alloc] initWithPlayer:player];
    [queue requestNext:NO dragging:YES];
    [queue requestNext:NO dragging:YES];
    [player acknowledge]; // restart D
    [queue check];
    NSCAssert(player.pending == player.tracks[2], @"restart acknowledged before stepping to C");
    [player acknowledge];
    [queue check];
    NSCAssert(player.pending == player.tracks[1], @"second backward selection retained");
    [player acknowledge];
    [queue check];
    [queue reset];

    player = [SGRSkipTestPlayer new];
    queue = [[SGRPlayerSkipQueue alloc] initWithPlayer:player];
    [queue requestNext:YES dragging:YES];
    [queue requestNext:YES dragging:YES];
    [player acknowledge];
    player.state.testContext = @"other playlist";
    [queue check];
    NSCAssert(player.commands == 1, @"context change cancels the old destination");
    [queue reset];
    NSLog(@"[harness] rapid skip checks: PASS");
}
