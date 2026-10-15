// The Live Activity page (App/ModSettings.x links it from the root, under either look).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "LiveActivity.h"

static NSArray<NSString *> *viewNames(void) {
    return @[@"Lyrics", @"Queue", @"Control menu"];
}

SGModRow *SGDynamicIslandLyricsRow(void) {
    if (@available(iOS 17.0, *)) {
        SGModRow *row = SGOptionRow(@"Dynamic Island lyrics", @"Sung words directly in the Island. Also shows a Lock Screen Live Activity.", SGKeyDynamicIslandLyrics);
        row.info = @"Shows the sung word and the next word directly in the Island as the song progresses, without a gesture. Songs timed only by line show a short opening phrase; songs without synced lyrics show a music note. iOS controls the available space and update delivery. Applies immediately; Live Activities must be allowed for Spotify in iOS Settings.";
        row.changed = ^(BOOL on) { SGSetLiveActivityEnabled(SGFlag(SGKeyLiveActivity, NO)); };
        return row;
    }
    return SGStatRow(@"Dynamic Island lyrics", ^NSString *{ return @"Needs iOS 17"; });
}

UIViewController *SGLiveActivitySettingsPage(void) {
    SGModRow *on = SGOptionRow(@"Live Activity", nil, SGKeyLiveActivity);
    on.changed = ^(BOOL value) { SGSetLiveActivityEnabled(value); };
    SGModRow *view = SGChoiceRow(@"Shows", nil, SGKeyLiveActivityView, viewNames(), SGLiveActivityLyrics);
    return [[SGModPage alloc] initWithTitle:@"Live Activity" intro:nil sections:@[
        SGSection(nil, @[on, view]),
        SGSection(nil, @[SGDynamicIslandLyricsRow()]),
    ] footer:nil];
}

NSString *SGLiveActivitySummary(void) {
    if (!SGFlag(SGKeyLiveActivity, NO))
        return SGFlag(SGKeyDynamicIslandLyrics, NO) ? @"Dynamic Island lyrics" : @"Off";
    NSInteger index = SGInt(SGKeyLiveActivityView, SGLiveActivityLyrics);
    NSArray<NSString *> *names = viewNames();
    return index >= 0 && index < (NSInteger)names.count ? names[index] : names.firstObject;
}
