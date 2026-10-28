#import "IslandLyrics.h"

// Keep a source's split syllables together, but do not merge an entire unspaced sentence into one word.
static NSString *wordAt(NSArray<SGKaraokeWord *> *words, NSUInteger index, NSUInteger *after) {
    if (index >= words.count) { *after = words.count; return @""; }
    if (SGKaraokeUnspacedScript(words[index].text)) {
        *after = index + 1;
        return words[index].text ?: @"";
    }
    while (index > 0 && words[index].joined && !SGKaraokeUnspacedScript(words[index - 1].text)) index--;
    NSMutableString *text = [NSMutableString stringWithString:words[index].text ?: @""];
    NSUInteger end = index + 1;
    while (end < words.count && words[end].joined && !SGKaraokeUnspacedScript(words[end].text)) {
        [text appendString:words[end].text ?: @""];
        end++;
    }
    *after = end;
    return text;
}

void SGIslandLyricWords(SGKaraokeLine *line, NSInteger ms, NSString **current, NSString **next) {
    *current = @"♪";
    *next = @"";
    if (!line.words.count || line.timing == SGKaraokeTimingNone || ms < line.start) return;
    NSInteger index = 0;
    if (line.timing == SGKaraokeTimingWords) {
        NSInteger active = -1, previous = -1;
        for (NSUInteger i = 0; i < line.words.count; i++) {
            SGKaraokeWord *word = line.words[i];
            if (word.start > ms) continue;
            if (previous < 0 || word.start >= line.words[(NSUInteger)previous].start) previous = (NSInteger)i;
            if (ms < word.end && (active < 0 || word.start > line.words[(NSUInteger)active].start)) active = (NSInteger)i;
        }
        // During a small gap hold the last word, and never reveal a future one as the current word.
        index = active >= 0 ? active : previous;
        if (index < 0) return;
    }
    NSUInteger after;
    *current = wordAt(line.words, (NSUInteger)index, &after);
    while (after < line.words.count) {
        NSUInteger first = after;
        NSString *candidate = wordAt(line.words, first, &after);
        BOOL upcoming = line.timing == SGKaraokeTimingLine;
        for (NSUInteger i = first; i < after && !upcoming; i++) {
            SGKaraokeWord *word = line.words[i];
            upcoming = word.start > ms || word.end > ms;
        }
        if (upcoming) { *next = candidate; break; }
    }
}
