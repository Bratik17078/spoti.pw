// Spicy Lyrics returns the best sync it has for Spotify's own 22-character track id. Unlike the
// sources searched by title, it can answer before the player has named a track. Its syllable shape
// carries genuine word timing, alternate vocal alignment, backing vocals and, on community work,
// the uploader and maker who must be credited where the lyrics are shown.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kAPI = @"https://api.spicylyrics.org/v1/lyrics/";
// A native app is a public client. Paste this app's publishable `sl_pk_...` key here and enable
// the dashboard's "no Origin header" option; do not put a secret `sl_sk_...` key in the tweak.
static NSString *const kAPIKey = @"sl_pk_REPLACE_WITH_YOUR_KEY";

static NSString *string(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSInteger milliseconds(id seconds) {
    return [seconds respondsToSelector:@selector(doubleValue)] ? (NSInteger)llround([seconds doubleValue] * 1000) : 0;
}

static SGKaraokeLine *lineFrom(id value, BOOL wordTimed) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *entry = value;
    NSArray *syllables = [entry[@"Syllables"] isKindOfClass:NSArray.class] ? entry[@"Syllables"] : nil;
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    for (NSDictionary *syllable in syllables) {
        if (![syllable isKindOfClass:NSDictionary.class]) continue;
        NSString *text = string(syllable[@"Text"]);
        if (!text.length) continue;
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = text;
        word.start = milliseconds(syllable[@"StartTime"]);
        word.end = MAX(word.start, milliseconds(syllable[@"EndTime"]));
        word.joined = [syllable[@"IsPartOfWord"] boolValue];
        [words addObject:word];
    }
    if (!words.count) {
        NSString *text = string(entry[@"Text"]);
        if (!text.length) return nil;
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = text;
        [words addObject:word];
    }
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = milliseconds(entry[@"StartTime"]);
    line.end = MAX(line.start, milliseconds(entry[@"EndTime"]));
    if (!line.start && words.firstObject.start) line.start = words.firstObject.start;
    if (!line.end && words.lastObject.end) line.end = words.lastObject.end;
    if (line.end < line.start) line.end = line.start;
    line.timing = wordTimed ? SGKaraokeTimingWords : line.start || line.end ? SGKaraokeTimingLine : SGKaraokeTimingNone;
    return line;
}

static SGKaraokeLine *pronunciationFrom(NSDictionary *entry, SGKaraokeLine *line) {
    NSString *whole = string(entry[@"TransliteratedText"]);
    if (!whole.length || [whole isEqualToString:SGKaraokeLineText(line)]) return nil;
    SGKaraokeWord *word = [SGKaraokeWord new];
    word.text = whole;
    word.start = line.start;
    word.end = line.end;
    SGKaraokeLine *pronunciation = [SGKaraokeLine new];
    pronunciation.words = @[word];
    pronunciation.start = line.start;
    pronunciation.end = line.end;
    pronunciation.timing = line.timing;
    return pronunciation;
}

static SGLyricsCredit *creditFrom(NSDictionary *body) {
    SGLyricsCredit *credit = [SGLyricsCredit new];
    NSString *source = string(body[@"source"]);
    credit.provider = [source isEqualToString:@"apple_music"] ? @"Apple Music"
                    : [source isEqualToString:@"spotify"] ? @"Spotify" : @"Spicy Lyrics";
    credit.required = YES;
    if (![source isEqualToString:@"spicy_lyrics"]) return credit;
    NSDictionary *attribution = [body[@"UploadAttribution"] isKindOfClass:NSDictionary.class] ? body[@"UploadAttribution"] : nil;
    NSDictionary *uploader = [attribution[@"Uploader"] isKindOfClass:NSDictionary.class] ? attribution[@"Uploader"] : nil;
    NSDictionary *maker = [attribution[@"Maker"] isKindOfClass:NSDictionary.class] ? attribution[@"Maker"] : nil;
    credit.uploader = string(uploader[@"username"]);
    credit.uploaderURL = string(uploader[@"url"]);
    credit.maker = string(maker[@"username"]);
    credit.makerURL = string(maker[@"url"]);
    return credit;
}

static SGLyricsResult *resultFrom(id root) {
    NSDictionary *envelope = [root isKindOfClass:NSDictionary.class] ? root : nil;
    NSDictionary *body = [envelope[@"Body"] isKindOfClass:NSDictionary.class] ? envelope[@"Body"] : nil;
    if ([envelope[@"Status"] integerValue] != 200 || !body) return nil;
    NSString *type = string(body[@"Type"]);
    BOOL wordTimed = [type isEqualToString:@"Syllable"];
    BOOL synced = wordTimed || [type isEqualToString:@"Line"];
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    for (NSDictionary *content in [body[@"Content"] isKindOfClass:NSArray.class] ? body[@"Content"] : @[]) {
        if (![content isKindOfClass:NSDictionary.class] || ![content[@"Type"] isEqual:@"Vocal"]) continue;
        SGKaraokeLine *line = lineFrom(content[@"Lead"], wordTimed);
        if (!line) continue;
        line.align = [content[@"OppositeAligned"] boolValue] ? SGKaraokeAlignTrailing : SGKaraokeAlignLeading;
        line.pronunciation = pronunciationFrom(content[@"Lead"], line);
        line.translation = string([content[@"Lead"] isKindOfClass:NSDictionary.class] ? content[@"Lead"][@"TranslatedText"] : nil);
        NSArray *background = [content[@"Background"] isKindOfClass:NSArray.class] ? content[@"Background"] : nil;
        line.backing = lineFrom(background.firstObject, wordTimed);
        line.backing.align = line.align;
        [lines addObject:line];
    }
    if (!lines.count) return nil;
    if (!synced) {
        for (SGKaraokeLine *line in lines) line.timing = SGKaraokeTimingNone;
    }
    SGLyricsResult *result = [SGLyricsResult new];
    result.synced = synced;
    result.wordTimed = wordTimed;
    result.karaokeLines = lines;
    NSArray<NSNumber *> *starts;
    NSArray<NSString *> *texts;
    SGLyricsPageLines(lines, &starts, &texts);
    result.starts = starts;
    result.texts = texts;
    result.credit = creditFrom(body);
    return result;
}

SGLyricsAsk SGSpicyLyricsAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (kAPIKey.length == 0 || [kAPIKey containsString:@"REPLACE_"]) {
        SGLog(@"spicylyrics: add this install's publishable API key before enabling the source");
        done(nil);
        return;
    }
    if (query.trackID.length != 22) {
        SGLog(@"spicylyrics: invalid Spotify track id %@", query.trackID);
        done(nil);
        return;
    }
    NSURL *url = [NSURL URLWithString:[kAPI stringByAppendingString:query.trackID]];
    SGLyricsGetJSON(url, @{@"Authorization": [@"Bearer " stringByAppendingString:kAPIKey]}, ^(id root) {
        SGLyricsResult *result = resultFrom(root);
        SGLog(@"spicylyrics: %@ gave %@", query.trackID, !result ? @"nothing"
              : result.wordTimed ? [NSString stringWithFormat:@"%lu word timed lines", (unsigned long)result.karaokeLines.count]
              : result.synced ? [NSString stringWithFormat:@"%lu line timed lines", (unsigned long)result.karaokeLines.count]
              : [NSString stringWithFormat:@"%lu untimed lines", (unsigned long)result.karaokeLines.count]);
        done(result);
    });
};
