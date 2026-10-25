// Skips a track by a blocked artist the moment the player moves onto it, whatever started it: the
// queue, autoplay, a radio or a tap. The track is read off SPTEsperantoPlayer, the app's player,
// which the now playing bar asks for its state from launch on; the full screen player's playback
// controller only exists while that player does, so it is the skip's first choice, not the source.
// Track changes come from the shared state observer and the lock screen's now playing info.
// A track is looked at once, so an update within it does not skip twice.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "ArtistBlock.h"
#import "Shared/PlaybackRules/PlaybackRules.h"
#import "Shared/Player/PlayerState.h"
#import "Headers/SPTPlayer.h"
#import "Headers/SPTNowPlayingPlaybackController.h"

static __weak id sg_player;
static __weak SPTNowPlayingPlaybackControllerImplementation *sg_controller;
static NSString *sg_seenTrack;
static CFTimeInterval sg_skipWindow;
static NSUInteger sg_skips;

static SPTPlayerTrack *playingTrack(BOOL explain) {
    id player = sg_player;
    SPTPlayerState *state = [player respondsToSelector:@selector(state)] ? [(id<SPTPlayer>)player state] : nil;
    SPTPlayerTrack *track = [state respondsToSelector:@selector(track)] ? state.track : nil;
    if (!track && explain) {
        SGLog(@"artist block: no track, player %@ state %@",
              player ? NSStringFromClass([player class]) : @"nil", state ? NSStringFromClass(state.class) : @"nil");
    }
    return track;
}

NSArray<NSDictionary *> *SGPlayingArtists(void) {
    SPTPlayerTrack *track = playingTrack(YES);
    NSArray<NSDictionary *> *artists = SGArtistsOfTrack(track);
    if (track && !artists.count) {
        SGLog(@"artist block: no artists in %@, artistURI %@ (%@)", NSStringFromClass(track.class),
              [track respondsToSelector:@selector(artistURI)] ? track.artistURI : @"-",
              [track respondsToSelector:@selector(artistURI)] ? NSStringFromClass([track.artistURI class]) : @"-");
    }
    return artists;
}

static NSString *trackKey(SPTPlayerTrack *track) {
    id uri = [track respondsToSelector:@selector(URI)] ? track.URI : nil;
    return [uri isKindOfClass:NSURL.class] ? ((NSURL *)uri).absoluteString : [uri description];
}

static NSDictionary *blockedArtistOf(SPTPlayerTrack *track) {
    NSArray<NSDictionary *> *artists = SGArtistsOfTrack(track);
    if (!SGFlag(SGKeyArtistBlockFeatured, NO) && artists.count > 1) artists = @[artists.firstObject];
    for (NSDictionary *artist in artists) {
        if (SGArtistBlocked(artist[SGArtistURI])) return artist;
    }
    return nil;
}

static void skip(SPTPlayerTrack *track, NSString *reason) {
    SPTNowPlayingPlaybackControllerImplementation *controller = sg_controller;
    id player = sg_player;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - sg_skipWindow > 15) { sg_skipWindow = now; sg_skips = 0; }
    // An all-blocked queue or repeat-one must not spin forever issuing commands to Spotify.
    if (++sg_skips > 12) {
        if ([player respondsToSelector:@selector(pause:)]) [(id<SPTPlayer>)player pause:nil];
        SGLog(@"playback rules: paused after 12 blocked tracks in 15 seconds; edit the queue or rules to continue");
        return;
    }
    if (controller.canSkipNext) {
        [controller skipToNextWhileDragging:NO];
    } else if ([player respondsToSelector:@selector(skipToNextTrack)]) {
        [(id<SPTPlayer>)player skipToNextTrack];
    } else {
        SGLog(@"playback rules: %@ cannot be skipped (%@)", track.trackTitle, reason);
        return;
    }
    SGLog(@"playback rules: skipped %@ (%@)", track.trackTitle, reason);
}

static void trackMayHaveChanged(void) {
    SPTPlayerTrack *track = playingTrack(NO);
    NSString *key = trackKey(track);
    if (!key || [key isEqualToString:sg_seenTrack]) return;
    sg_seenTrack = key;

    NSDictionary *rule = SGPlaybackRuleForTrack(track, NSDate.date);
    NSDictionary *artist = SGFlag(SGKeyArtistBlock, NO) ? blockedArtistOf(track) : nil;
    if (rule || artist) skip(track, rule ? @"saved rule" : artist[SGArtistName]);
}

@interface SGPlaybackSkipObserver : NSObject <SGPlayerStateObserver>
@end
@implementation SGPlaybackSkipObserver
- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (!SGFlag(SGKeyArtistBlock, NO) && !SGFlag(SGKeyPlaybackRules, NO)) return;
    dispatch_async(dispatch_get_main_queue(), ^{ trackMayHaveChanged(); });
}
@end
static SGPlaybackSkipObserver *sg_skipObserver;

%hook SPTEsperantoPlayer
- (id)state {
    if (!sg_player) {
        sg_player = self;
        SGLog(@"artist block: player found");
    }
    return %orig;
}
%end

%hook SPTNowPlayingPlaybackControllerImplementation
- (id)initWithPlayer:(id)player testManager:(id)manager inStreamClient:(id)client {
    id controller = %orig;
    sg_controller = controller;
    return controller;
}
%end

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    %orig;
    if (!SGFlag(SGKeyArtistBlock, NO) && !SGFlag(SGKeyPlaybackRules, NO)) return;
    dispatch_async(dispatch_get_main_queue(), ^{ trackMayHaveChanged(); });
}
%end

%ctor {
    %init;
    sg_skipObserver = [SGPlaybackSkipObserver new];
    SGAddPlayerStateObserver(sg_skipObserver);
    [NSNotificationCenter.defaultCenter addObserverForName:SGPlaybackRulesDidChangeNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            sg_seenTrack = nil;
            trackMayHaveChanged();
        }];
    SGRequireClasses(@[@"SPTEsperantoPlayer", @"SPTNowPlayingPlaybackControllerImplementation", @"MPNowPlayingInfoCenter"]);
}
