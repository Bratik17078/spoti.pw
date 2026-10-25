#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "PlaybackRules.h"
#include <math.h>

NSNotificationName const SGPlaybackRulesDidChangeNotification = @"spotifyglass.playbackRulesChanged";

static NSString *normalized(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSArray *parts = [text.lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
}

NSArray<NSDictionary *> *SGPlaybackRules(void) {
    NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:SGKeyPlaybackRuleList];
    NSMutableArray *valid = [NSMutableArray array];
    for (id item in stored) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *rule = item;
        if (![rule[@"id"] isKindOfClass:NSString.class] || ![rule[@"uri"] isKindOfClass:NSString.class]
            || ![rule[@"title"] isKindOfClass:NSString.class] || ![rule[@"kind"] isKindOfClass:NSNumber.class]) continue;
        NSInteger kind = [rule[@"kind"] integerValue];
        if (kind < SGPlaybackRuleTrack || kind > SGPlaybackRuleBreak) continue;
        if (kind == SGPlaybackRuleVersion && (![rule[@"artistURI"] isKindOfClass:NSString.class] || ![rule[@"version"] isKindOfClass:NSString.class])) continue;
        if (kind == SGPlaybackRuleBreak && (![rule[@"until"] isKindOfClass:NSNumber.class] || !isfinite([rule[@"until"] doubleValue]))) continue;
        [valid addObject:rule];
    }
    return valid;
}

static void save(NSArray *rules) {
    [NSUserDefaults.standardUserDefaults setObject:rules forKey:SGKeyPlaybackRuleList];
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlaybackRulesDidChangeNotification object:nil];
}

NSDictionary *SGPlaybackRuleForTrack(SPTPlayerTrack *track, NSDate *now) {
    if (!SGFlag(SGKeyPlaybackRules, NO)) return nil;
    NSString *uri = SGURIString(track.URI);
    if (![uri hasPrefix:@"spotify:track:"]) return nil;
    NSString *artist = SGURIString(track.artistURI), *title = normalized(track.trackTitle);
    for (NSDictionary *rule in SGPlaybackRules()) {
        NSInteger kind = [rule[@"kind"] integerValue];
        if (kind == SGPlaybackRuleBreak && [rule[@"until"] doubleValue] <= now.timeIntervalSince1970) continue;
        if (kind == SGPlaybackRuleVersion) {
            if (title.length && [rule[@"artistURI"] isEqual:artist] && [rule[@"version"] isEqual:title]) return rule;
        } else if ([rule[@"uri"] isEqual:uri]) return rule;
    }
    return nil;
}

void SGAddPlaybackRule(SPTPlayerTrack *track, SGPlaybackRuleKind kind) {
    NSString *uri = SGURIString(track.URI);
    if (![uri hasPrefix:@"spotify:track:"] || kind < SGPlaybackRuleTrack || kind > SGPlaybackRuleBreak) return;
    NSString *artistURI = SGURIString(track.artistURI) ?: @"", *version = normalized(track.trackTitle);
    if (kind == SGPlaybackRuleVersion && (!artistURI.length || !version.length)) return;
    NSMutableArray *rules = [SGPlaybackRules() mutableCopy];
    NSIndexSet *duplicates = [rules indexesOfObjectsPassingTest:^BOOL(NSDictionary *rule, NSUInteger idx, BOOL *stop) {
        if ([rule[@"kind"] integerValue] != kind) return NO;
        return kind == SGPlaybackRuleVersion ? [rule[@"artistURI"] isEqual:artistURI] && [rule[@"version"] isEqual:version] : [rule[@"uri"] isEqual:uri];
    }];
    [rules removeObjectsAtIndexes:duplicates];
    NSMutableDictionary *rule = [@{@"id": NSUUID.UUID.UUIDString, @"kind": @(kind), @"uri": uri,
        @"title": track.trackTitle ?: uri, @"artist": track.artistName ?: @"", @"artistURI": artistURI, @"version": version} mutableCopy];
    if (kind == SGPlaybackRuleBreak) rule[@"until"] = @([NSDate dateWithTimeIntervalSinceNow:30 * 24 * 60 * 60].timeIntervalSince1970);
    [rules addObject:rule];
    SGSetEnabled(SGKeyPlaybackRules, YES);
    save(rules);
}

void SGRemovePlaybackRule(NSString *identifier) {
    NSMutableArray *rules = [SGPlaybackRules() mutableCopy];
    [rules filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *rule, NSDictionary *bindings) {
        return ![rule[@"id"] isEqual:identifier];
    }]];
    save(rules);
}

void SGPresentPlaybackRuleActions(UIViewController *presenter, SPTPlayerTrack *track, UIView *source) {
    if (![SGURIString(track.URI) hasPrefix:@"spotify:track:"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Play a song first" message:@"Playback rules apply to music tracks." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:track.trackTitle message:@"Rules apply immediately. Remove them in Player → Playback rules. Version rules match the exact title and main artist across releases." preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles = @[@"Skip this track", @"Skip this version across releases", @"Take a 30-day break"];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { SGAddPlaybackRule(track, (SGPlaybackRuleKind)idx); }];
        if (idx == SGPlaybackRuleVersion) action.enabled = SGURIString(track.artistURI).length && track.trackTitle.length;
        [sheet addAction:action];
    }];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = source ?: presenter.view;
    sheet.popoverPresentationController.sourceRect = source ? source.bounds : CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
    [presenter presentViewController:sheet animated:YES completion:nil];
}
