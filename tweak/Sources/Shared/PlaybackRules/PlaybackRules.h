#import <UIKit/UIKit.h>
@class SPTPlayerTrack;

#define SGKeyPlaybackRules @"spotifyglass.playbackRules"
#define SGKeyPlaybackRuleList @"spotifyglass.playbackRules.list"
extern NSNotificationName const SGPlaybackRulesDidChangeNotification;

typedef NS_ENUM(NSInteger, SGPlaybackRuleKind) {
    SGPlaybackRuleTrack, SGPlaybackRuleVersion, SGPlaybackRuleBreak,
};

// Entries are property-list dictionaries. Version rules match an exact title and main artist URI,
// including live/remix/remaster suffixes; they never guess from a partial title.
NSArray<NSDictionary *> *SGPlaybackRules(void);
NSDictionary *SGPlaybackRuleForTrack(SPTPlayerTrack *track, NSDate *now);
void SGAddPlaybackRule(SPTPlayerTrack *track, SGPlaybackRuleKind kind);
void SGRemovePlaybackRule(NSString *identifier);
UIViewController *SGPlaybackRulesSettingsPage(void);
void SGPresentPlaybackRuleActions(UIViewController *presenter, SPTPlayerTrack *track, UIView *source);
