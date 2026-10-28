// The Live Activity page (App/ModSettings.x links it from the root, under either look).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "LiveActivity.h"

static NSArray<NSString *> *viewNames(void) {
    return @[@"Lyrics", @"Queue", @"Control menu"];
}

<<<<<<< HEAD
<<<<<<< HEAD
SGModRow *SGDynamicIslandLyricsRow(void) {
    if (@available(iOS 17.0, *)) {
        SGModRow *row = SGOptionRow(@"Dynamic Island lyrics", @"Full synced lines in an expanding panel inside Spotify.", SGKeyDynamicIslandLyrics);
        row.info = @"While Spotify is open, a black capsule below the Island automatically expands to show the current and next synced lines. Tap or swipe up to collapse it; tap to reopen. Outside Spotify, the system Live Activity shows compact lyrics and a Lock Screen card. Live Activities must be allowed in iOS Settings; the in-app panel works independently. Applies immediately.";
        row.changed = ^(BOOL on) { SGSetLiveActivityEnabled(SGFlag(SGKeyLiveActivity, NO)); };
        return row;
    }
    return SGStatRow(@"Dynamic Island lyrics", ^NSString *{ return @"Needs iOS 17"; });
}

SGModRow *SGLiveActivityStatusRow(void) {
    SGModRow *row = SGStatRow(@"System Live Activity", ^NSString *{ return SGLiveActivityStatus(); });
    row.visible = ^BOOL { return SGFlag(SGKeyLiveActivity, NO) || SGFlag(SGKeyDynamicIslandLyrics, NO); };
    return row;
}

=======
>>>>>>> parent of 98714e2 (heah)
=======
>>>>>>> parent of 98714e2 (heah)
UIViewController *SGLiveActivitySettingsPage(void) {
    SGModRow *on = SGOptionRow(@"Live Activity", nil, SGKeyLiveActivity);
    on.changed = ^(BOOL value) { SGSetLiveActivityEnabled(value); };
    SGModRow *view = SGChoiceRow(@"Shows", nil, SGKeyLiveActivityView, viewNames(), SGLiveActivityLyrics);
    return [[SGModPage alloc] initWithTitle:@"Live Activity" intro:nil sections:@[
        SGSection(nil, @[on, view]),
<<<<<<< HEAD
<<<<<<< HEAD
        SGSection(nil, @[SGDynamicIslandLyricsRow(), SGLiveActivityStatusRow()]),
=======
>>>>>>> parent of 98714e2 (heah)
=======
>>>>>>> parent of 98714e2 (heah)
    ] footer:nil];
}

NSString *SGLiveActivitySummary(void) {
    if (!SGFlag(SGKeyLiveActivity, NO)) return @"Off";
    NSInteger index = SGInt(SGKeyLiveActivityView, SGLiveActivityLyrics);
    NSArray<NSString *> *names = viewNames();
    return index >= 0 && index < (NSInteger)names.count ? names[index] : names.firstObject;
}
