// Exercises the actual compact-Island text selection without ActivityKit or a running player.
#import "Shared/LiveActivity/IslandLyrics.h"

static SGKaraokeWord *word(NSString *text, NSInteger start, NSInteger end, BOOL joined) {
    SGKaraokeWord *w = [SGKaraokeWord new];
    w.text = text; w.start = start; w.end = end; w.joined = joined;
    return w;
}

static BOOL check(SGKaraokeLine *line, NSInteger ms, NSString *want, NSString *wantNext) {
    NSString *current, *next;
    SGIslandLyricWords(line, ms, &current, &next);
    BOOL ok = [current isEqualToString:want] && [next isEqualToString:wantNext];
    if (!ok) NSLog(@"[harness] Island at %ld: %@ / %@; expected %@ / %@", (long)ms, current, next, want, wantNext);
    return ok;
}

BOOL SGCheckIslandLyrics(void) {
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.start = 100; line.end = 1700;
    line.words = @[word(@"We", 100, 400, NO), word(@"are", 500, 700, NO),
                   word(@"sing", 800, 950, NO), word(@"ing", 950, 1300, YES), word(@"now", 1400, 1700, NO)];
    BOOL ok = check(line, 99, @"♪", @"");
    ok &= check(line, 100, @"We", @"are");
    ok &= check(line, 450, @"We", @"are"); // hold through a gap
    ok &= check(line, 500, @"are", @"singing");
    ok &= check(line, 800, @"singing", @"now");
    ok &= check(line, 1000, @"singing", @"now"); // joined syllable, same complete word
    ok &= check(line, 1400, @"now", @"");
    ok &= check(line, 250, @"We", @"are"); // seeking back has no accumulated state
    line.timing = SGKaraokeTimingLine;
    ok &= check(line, 1000, @"We", @"are"); // no estimated word sync
    line.timing = SGKaraokeTimingNone;
    ok &= check(line, 1000, @"♪", @"");
    line.timing = SGKaraokeTimingWords;
    line.words = @[word(@"你", 100, 200, NO), word(@"好", 200, 300, YES)];
    ok &= check(line, 100, @"你", @"好");
    ok &= check(line, 200, @"好", @"");
    line.words = @[word(@"held", 100, 1000, NO), word(@"overlap", 500, 600, NO)];
    ok &= check(line, 550, @"overlap", @"");
    ok &= check(line, 700, @"held", @"");
    line.words = @[word(@"one", 100, 200, NO), word(@"two", 100, 300, NO)];
    ok &= check(line, 250, @"two", @"");
    ok &= check(line, 350, @"two", @"");
    ok &= check(nil, 100, @"♪", @"");
    NSLog(@"[harness] Island lyric checks -- %@", ok ? @"PASS" : @"FAIL");
    return ok;
}
