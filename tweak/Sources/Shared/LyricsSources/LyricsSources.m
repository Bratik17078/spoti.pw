// The walk: every source in the order the Lyrics page puts them in, the best answer winning rather
// than the first — a source with only plain text does not shut out a later one that times every word.
//
// Answering fast is what makes the lyrics card under the player appear at all. The card waits for
// Spotify's lyrics reply, which waits for the walk, and the player gives its cards only a fixed
// moment to load before it shows the list without them: a walk that asked every source one after
// another for word timing took five seconds and more, and the player sat unresponsive for all of it
// while the song played on. So the order is still the priority, as it reads on the Lyrics page — a
// source further down goes ahead only after those above have been given their moment — but a source
// that has not answered within kStagger is left out there and the next starts over it, and the walk
// answers within kWalkDeadline however many are still out. What arrives after that is merged and
// kept all the same, for the next time the track is asked for.
#import "Core/SGCore.h"
#import "LyricsSources.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Headers/SPTPlayer.h"
#import <stdatomic.h>

static const NSTimeInterval kTimeout = 6;
// One walk: the next source goes ahead kStagger after the last was asked when the last has not
// answered, and the walk as a whole answers within kWalkDeadline however many are still out.
static const NSTimeInterval kStagger = 0.4, kWalkDeadline = 1.8;
static const NSUInteger kKeptTracks = 40;

// What the switches were called while Musixmatch was the only source; read once, to carry an
// existing install's settings over to the order.
static NSString *const kLegacyMusixmatch = @"spotifyglass.musixmatchLyrics";
static NSString *const kLegacyAllTracks = @"spotifyglass.musixmatchAllTracks";
static NSString *const kLegacyNetEase = @"spotifyglass.neteaseWordTiming";

@implementation SGLyricsResult
@end

@implementation SGLyricsCredit
@end

@implementation SGLyricsQuery
@end

@implementation SGLyricsProvider
@end

#pragma mark - the requests the sources share

// Every request any source has lost to the network or to a server too busy to answer, counted so a
// walk can tell "no source has lyrics" from "a source could not say". Only the first is kept.
static _Atomic NSUInteger sg_failures;

BOOL SGLyricsReplyFailed(NSURLResponse *response, NSError *error) {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    return error || status == 429 || status >= 500;
}

void SGLyricsNoteReply(NSURLResponse *response, NSError *error) {
    if (SGLyricsReplyFailed(response, error)) atomic_fetch_add(&sg_failures, 1);
}

NSURL *SGLyricsURL(NSString *base, NSDictionary<NSString *, NSString *> *query) {
    NSURLComponents *url = [NSURLComponents componentsWithString:base];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }];
    url.queryItems = items;
    return url.URL;
}

static NSMutableURLRequest *requestFor(NSURL *url, NSDictionary<NSString *, NSString *> *headers) {
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kTimeout];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:name];
    }];
    return request;
}

// Hands the body over on URLSession's own queue; the wrappers below read it there, so a large reply
// is parsed off the main queue, and only then cross over to it, which is where the sources ask to
// be answered.
static void send(NSURLRequest *request, void (^done)(NSData *body)) {
    if (!request) {
        done(nil);
        return;
    }
    NSURL *url = request.URL;
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        SGLyricsNoteReply(response, error);
        if (error || status >= 400) SGLog(@"lyrics: %@ answered %ld, error %@", url.host, (long)status, error);
        done(status >= 400 ? nil : data);
    }] resume];
}

static id jsonIn(NSData *body) {
    return body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
}

void SGLyricsGetJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, void (^done)(id root)) {
    send(requestFor(url, headers), ^(NSData *body) {
        id root = jsonIn(body);
        dispatch_async(dispatch_get_main_queue(), ^{ done(root); });
    });
}

void SGLyricsGetText(NSURL *url, void (^done)(NSString *text)) {
    send(requestFor(url, nil), ^(NSData *body) {
        NSString *text = body.length ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(text); });
    });
}

void SGLyricsPostJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, id body, void (^done)(id root)) {
    NSData *written = [NSJSONSerialization isValidJSONObject:body]
        ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : nil;
    NSMutableURLRequest *request = written ? requestFor(url, headers) : nil;
    request.HTTPMethod = @"POST";
    request.HTTPBody = written;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    send(request, ^(NSData *answer) {
        id root = jsonIn(answer);
        dispatch_async(dispatch_get_main_queue(), ^{ done(root); });
    });
}

// A pause this long between two lines gets a ♪, so Spotify's page does not hold the last one.
static const NSInteger kBreakMs = 3000;

void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray<NSNumber *> *at = [NSMutableArray array];
    NSMutableArray<NSString *> *said = [NSMutableArray array];
    SGKaraokeLine *last = nil;
    for (SGKaraokeLine *line in lines) {
        if (last && line.start - last.end >= kBreakMs) {
            [at addObject:@(last.end)];
            [said addObject:@"♪"];
        }
        NSString *text = SGKaraokeLineText(line);
        // The backing vocals read on the same line on Spotify's own page, which has one row a line.
        if (line.backing) text = [text stringByAppendingFormat:@" %@", SGKaraokeLineText(line.backing)];
        [at addObject:@(line.start)];
        [said addObject:text];
        last = line;
    }
    if (last) {
        [at addObject:@(last.end)];
        [said addObject:@""];
    }
    *starts = at;
    *texts = said;
}

#pragma mark - which sources there are, and in what order

NSArray<SGLyricsProvider *> *SGLyricsAllProviders(void) {
    static NSArray<SGLyricsProvider *> *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLyricsProvider *(^make)(NSString *, NSString *, NSString *, SGLyricsAsk) =
        ^(NSString *key, NSString *name, NSString *detail, SGLyricsAsk ask) {
            SGLyricsProvider *provider = [SGLyricsProvider new];
            provider.key = key;
            provider.name = name;
            provider.detail = detail;
            // A source that matches by Spotify's own track id has everything it needs from the
            // start; the rest wait for the player to name the track before they can search.
            provider.needsName = ![key isEqualToString:@"musixmatch"] && ![key isEqualToString:@"spicylyrics"];
            provider.ask = ask;
            return provider;
        };
        all = @[
            make(@"binilyrics", @"BiniLyrics", @"Apple Music word timing", SGBiniLyricsAsk),
            make(@"spicylyrics", @"Spicy Lyrics", @"Community and commercial word timing", SGSpicyLyricsAsk),
            make(@"musixmatch", @"Musixmatch", @"Spotify's licensed catalogue", SGMusixmatchAsk),
            make(@"unison", @"Unison", @"Hand-timed, few tracks", SGUnisonAsk),
            make(@"netease", @"NetEase", @"Word timing, censored", SGNetEaseAsk),
            make(@"lrclib", @"LRCLIB", @"Line timing, open fallback", SGLrcLibAsk),
        ];
    });
    return all;
}

SGLyricsProvider *SGLyricsProviderFor(NSString *key) {
    for (SGLyricsProvider *provider in SGLyricsAllProviders()) {
        if ([provider.key isEqualToString:key]) return provider;
    }
    return nil;
}

// An install from before the order existed keeps what it had: the sources it was using, in the only
// order there was. Nothing is switched on for it that it had not already asked for.
static NSArray<NSString *> *fromLegacyKeys(void) {
    if (!SGFlag(kLegacyMusixmatch, NO)) return @[];
    NSMutableArray<NSString *> *order = [NSMutableArray arrayWithObject:@"musixmatch"];
    if (SGFlag(kLegacyNetEase, NO)) [order addObject:@"netease"];
    return order;
}

NSArray<NSString *> *SGLyricsOrder(void) {
    id stored = [NSUserDefaults.standardUserDefaults arrayForKey:SGKeyLyricsProviders];
    NSArray *keys = [stored isKindOfClass:NSArray.class] ? stored : fromLegacyKeys();
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (id key in keys) {
        if ([key isKindOfClass:NSString.class] && SGLyricsProviderFor(key) && ![order containsObject:key]) [order addObject:key];
    }
    return order;
}

void SGLyricsSetOrder(NSArray<NSString *> *keys) {
    [NSUserDefaults.standardUserDefaults setObject:keys ?: @[] forKey:SGKeyLyricsProviders];
}

BOOL SGLyricsEnabled(void) {
    return SGLyricsOrder().count > 0;
}

#pragma mark - what is known about the track

// The player knows every track it has played by name, which is what every source but Musixmatch
// searches by. The track is looked up by id rather than compared with the one playing now: a lyrics
// request often lands a beat before the player moves on to its track, and comparing then left the
// query nameless. What the player has not reported the query starts without, and it is filled in
// later — by the player, polled while the walk runs, and by the first source that matches by id.
// Only the missing parts are taken, so a query already named or taught is left alone.
static void learnFromPlayer(SGLyricsQuery *query) {
    SPTPlayerTrack *track = SGKaraokeTrackFor(query.trackID);
    if (!track) return;
    if (!query.title.length) query.title = track.trackTitle;
    if (!query.artist.length) query.artist = track.artistName;
    if (query.album.length && query.seconds > 0) return;
    NSDictionary<NSString *, NSString *> *metadata = track.metadata;
    id album = metadata[@"album_title"];
    id length = metadata[@"duration"];
    if (!query.album.length && [album isKindOfClass:NSString.class]) query.album = album;
    if (query.seconds <= 0 && [length respondsToSelector:@selector(integerValue)]) query.seconds = [length integerValue] / 1000;
}

static SGLyricsQuery *queryFor(NSString *trackID) {
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = trackID;
    learnFromPlayer(query);
    return query;
}

static void learnFrom(SGLyricsQuery *query, SGLyricsResult *result) {
    if (!query.title.length && result.title.length) query.title = result.title;
    if (!query.artist.length && result.artist.length) query.artist = result.artist;
    if (!query.album.length && result.album.length) query.album = result.album;
    if (query.seconds <= 0 && result.seconds > 0) query.seconds = result.seconds;
}

#pragma mark - the walk

// Main queue only, except sg_missing and sg_credits.
static NSMutableDictionary<NSString *, id> *sg_kept;
static NSMutableDictionary<NSString *, NSMutableArray *> *sg_waiting;
static NSMutableSet<NSString *> *sg_missing;
static NSMutableDictionary<NSString *, SGLyricsCredit *> *sg_credits;
// Spotify's own has_lyrics per track, as its metadata said. The player's metadata is read many
// times a second while a list scrolls, so a value already noted costs one lookup and no write.
static NSMutableDictionary<NSString *, NSNumber *> *sg_spotifyHas;
static const NSUInteger kNotedTracks = 200;

static void setUp(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_kept = [NSMutableDictionary dictionary];
        sg_waiting = [NSMutableDictionary dictionary];
        sg_missing = [NSMutableSet set];
        sg_credits = [NSMutableDictionary dictionary];
        sg_spotifyHas = [NSMutableDictionary dictionary];
    });
}

// Whether the source's lines are better than what the walk already has: any lines beat none, and
// finer timing beats coarser — words timed beat a line's start, which beats plain text. Read off the
// lines themselves, which say how they were really timed, rather than off what the source claimed.
static BOOL betterLines(SGLyricsResult *merged, SGLyricsResult *fresh) {
    if (!fresh.karaokeLines.count) return NO;
    return !merged.karaokeLines.count || SGKaraokeLinesTiming(fresh.karaokeLines) < SGKaraokeLinesTiming(merged.karaokeLines);
}

static NSString *timingName(NSArray<SGKaraokeLine *> *lines) {
    switch (SGKaraokeLinesTiming(lines)) {
        case SGKaraokeTimingWords: return @"word timed";
        case SGKaraokeTimingLine: return @"line timed";
        default: return @"untimed";
    }
}

// The same for the text Spotify's own page shows: any text beats none, timed beats untimed.
static BOOL betterTexts(SGLyricsResult *merged, SGLyricsResult *fresh) {
    if (!fresh.texts.count) return NO;
    return !merged.texts.count || (fresh.synced && !merged.synced);
}

// The player names its track a beat after the request that belongs to it arrives — the request
// routinely lands first — so the walk goes on without the name and polls for it while it runs, the
// sources that search by one going in the moment the track is known.
static const NSTimeInterval kNamePoll = 0.1;

static BOOL named(SGLyricsQuery *query) {
    return query.title.length && query.artist.length;
}

// One walk down the order for one track.
@interface SGLyricsWalk : NSObject
@property (nonatomic, copy) NSArray<NSString *> *order;
@property (nonatomic) NSUInteger index;           // the next source of the order to be asked
@property (nonatomic, strong) SGLyricsQuery *query;
@property (nonatomic, strong) SGLyricsResult *merged;
// Sources that needed a name the query did not have when their turn came. They go back in ahead of
// the ones not asked yet as soon as the track is named, in the order they were passed over.
@property (nonatomic, strong) NSMutableArray<NSString *> *passedOver;
// sg_failures when the walk started. Another walk's failure counts too, which at worst asks again.
@property (nonatomic) NSUInteger failuresAtStart;
@property (nonatomic) NSUInteger outstanding;     // asked and not yet answered
@property (nonatomic) NSTimeInterval lastStart;   // when the last source was asked, for the stagger
@property (nonatomic) NSUInteger wake;            // the number of the wake pending, to tell it from a stale one
@property (nonatomic) BOOL timedOut;              // the deadline ended the walk with sources still out
@property (nonatomic) BOOL done;                  // its waiters have their answer; late answers still merge
@end

@implementation SGLyricsWalk
@end

// A walk that ends with nothing is only an answer when every source was asked and answered. One
// that passed a source over for want of a name asked it nothing, one the deadline ended left the
// rest unasked, and one during which a request failed could not say; keeping any of those as "no
// lyrics" would stick to the track — every later request would get the kept nil, and the lyrics
// card would be taken off the track for the rest of the session. Lines are kept whatever else was
// still out, an instrumental verdict is for good, and a walk that did get through everyone keeps
// its nothing, so the next request does not ask again.
static void keep(SGLyricsWalk *walk) {
    SGLyricsResult *merged = walk.merged;
    NSString *trackID = walk.query.trackID;
    BOOL lyrics = merged.karaokeLines.count || merged.texts.count;
    BOOL askedAndAnswered = walk.index >= walk.order.count && !walk.outstanding && !walk.passedOver.count;
    BOOL failed = atomic_load(&sg_failures) != walk.failuresAtStart;
    if (!lyrics && !merged.instrumental && !(askedAndAnswered && !failed)) return;
    // A walk run beside one that already answered must not put worse lines in its place. What is
    // kept is the same object this walk answers with, so a better answer arriving late improves both.
    id have = sg_kept[trackID];
    if ([have isKindOfClass:SGLyricsResult.class] && !betterLines(have, merged) && !betterTexts(have, merged)) return;
    if (sg_kept.count >= kKeptTracks) [sg_kept removeAllObjects];
    sg_kept[trackID] = lyrics ? merged : NSNull.null;
    @synchronized (sg_missing) {
        if (lyrics) [sg_missing removeObject:trackID];
        else [sg_missing addObject:trackID];
    }
}

// Ends the walk: what it has is kept, whoever is still out, and the requests waiting on it get their
// answer. Main queue.
static void finish(SGLyricsWalk *walk) {
    if (walk.done) return;
    walk.done = YES;
    SGLyricsResult *merged = walk.merged;
    NSString *trackID = walk.query.trackID;
    SGLyricsResult *lyrics = merged.karaokeLines.count || merged.texts.count ? merged : nil;
    keep(walk);
    BOOL allAsked = walk.index >= walk.order.count && !walk.passedOver.count;
    BOOL failed = atomic_load(&sg_failures) != walk.failuresAtStart;
    SGLog(@"lyrics: %@ ends with %@", trackID, lyrics
          ? [NSString stringWithFormat:@"%lu %@ lines from %@, %lu page lines",
             (unsigned long)lyrics.karaokeLines.count, timingName(lyrics.karaokeLines),
             lyrics.provider, (unsigned long)lyrics.texts.count]
          : walk.timedOut ? @"nothing, the deadline came first; not kept, so the next request asks again"
          : merged.instrumental ? @"nothing, the sources say it is instrumental; kept as such"
          : !allAsked && walk.passedOver.count ? [NSString stringWithFormat:@"nothing, %@ never knowing its name; not kept, so the next request asks again",
             [walk.passedOver componentsJoinedByString:@", "]]
          : !allAsked || walk.outstanding ? @"nothing, not every source could answer in time; not kept, so the next request asks again"
          : failed ? @"nothing, a request failed on the way; not kept, so the next request asks again"
          : @"nothing");
    NSArray *waiting = sg_waiting[trackID];
    [sg_waiting removeObjectForKey:trackID];
    for (void (^done)(SGLyricsResult *) in waiting) done(lyrics);
}

// The player has named the track: the sources passed over for want of a name go in ahead of the
// ones whose turn has not come, in the order they were passed over.
static void namedNow(SGLyricsWalk *walk) {
    if (!walk.passedOver.count) return;
    SGLog(@"lyrics: %@ named partway as \"%@\" by \"%@\", asking %@ after all", walk.query.trackID,
          walk.query.title, walk.query.artist, [walk.passedOver componentsJoinedByString:@", "]);
    NSMutableArray<NSString *> *order = [walk.order mutableCopy];
    [order insertObjects:walk.passedOver
               atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(walk.index, walk.passedOver.count)]];
    walk.order = order;
    walk.passedOver = [NSMutableArray array];
}

static void advance(SGLyricsWalk *walk, BOOL immediate);
static void answered(SGLyricsWalk *walk, SGLyricsProvider *provider, SGLyricsResult *fresh);

// The one wake a walk keeps, for the next source's turn to come round. A newer wake numbers itself,
// so an older one finds its number stale and does nothing; one wake pending at a time, at the
// moment the stagger actually runs out.
static void scheduleWake(SGLyricsWalk *walk, NSTimeInterval delay) {
    NSUInteger wake = walk.wake + 1;
    walk.wake = wake;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (walk.done || walk.wake != wake) return;
        advance(walk, NO);
    });
}

// Asks the next source whose turn has come. A call made from an answer goes straight ahead — the
// source that answered has had its say and the next is due; one made by the wake waits out the
// stagger, so a source left out there while it is slow gets kStagger before the next starts over it.
static void advance(SGLyricsWalk *walk, BOOL immediate) {
    if (walk.done) return;
    while (walk.index < walk.order.count) {
        SGLyricsProvider *provider = SGLyricsProviderFor(walk.order[walk.index]);
        if (provider.needsName && !named(walk.query)) {
            walk.index++;
            [walk.passedOver addObject:provider.key];
            continue;
        }
        NSTimeInterval now = CFAbsoluteTimeGetCurrent();
        if (!immediate && walk.lastStart + kStagger > now) {
            scheduleWake(walk, walk.lastStart + kStagger - now);
            return;
        }
        walk.index++;
        walk.outstanding++;
        walk.lastStart = now;
        scheduleWake(walk, kStagger);
        provider.ask(walk.query, ^(SGLyricsResult *fresh) { answered(walk, provider, fresh); });
        return;
    }
    if (!walk.outstanding && !walk.passedOver.count) finish(walk);
}

// One source has answered. Its lines join the merge if they are the best so far, and the walk goes
// on: the next source at once, or the end if that was the last of them. An answer landing after the
// walk has already answered its waiters is merged and kept all the same, for the next request.
static void answered(SGLyricsWalk *walk, SGLyricsProvider *provider, SGLyricsResult *fresh) {
    walk.outstanding--;
    SGLyricsQuery *query = walk.query;
    SGLyricsResult *merged = walk.merged;
    BOOL wasNamed = named(query);
    learnFrom(query, fresh);
    if (fresh.instrumental) {
        SGLog(@"lyrics: %@ is instrumental, by %@", query.trackID, provider.key);
        merged.instrumental = YES;
        if (walk.done) keep(walk); else finish(walk);
        return;
    }
    if (betterLines(merged, fresh)) {
        merged.karaokeLines = fresh.karaokeLines;
        merged.wordTimed = fresh.wordTimed;
        merged.provider = provider.name;
        merged.credit = fresh.credit;
    }
    if (betterTexts(merged, fresh)) {
        merged.starts = fresh.starts;
        merged.texts = fresh.texts;
        merged.synced = fresh.synced;
        if (!merged.provider) {
            merged.provider = provider.name;
            merged.credit = fresh.credit;
        }
    }
    if (walk.done) {
        keep(walk);
        return;
    }
    if (!wasNamed && named(query)) namedNow(walk);
    // A source has answered with timed lines: that is the answer, whatever is still out.
    if (merged.synced && merged.texts.count && merged.karaokeLines.count) {
        finish(walk);
        return;
    }
    advance(walk, YES);
}

// Keeps asking the player for the name until it gives one or the walk ends. The name is read into
// the query in place: the sources asked meanwhile hold that same query and see it named.
static void watchForName(SGLyricsWalk *walk) {
    if (walk.done) return;
    learnFromPlayer(walk.query);
    if (named(walk.query)) {
        namedNow(walk);
        advance(walk, NO);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kNamePoll * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        watchForName(walk);
    });
}

static void startWalk(NSString *trackID, SGLyricsQuery *query) {
    SGLog(@"lyrics: asking %@ for %@ as \"%@\" by \"%@\", album \"%@\", %lds",
          [SGLyricsOrder() componentsJoinedByString:@", "], trackID, query.title, query.artist, query.album, (long)query.seconds);
    SGLyricsWalk *walk = [SGLyricsWalk new];
    walk.order = SGLyricsOrder();
    walk.query = query;
    walk.merged = [SGLyricsResult new];
    walk.passedOver = [NSMutableArray array];
    walk.failuresAtStart = atomic_load(&sg_failures);
    advance(walk, NO);
    if (!named(query)) watchForName(walk);
    // Whatever happens, the walk answers by then. What is still out is merged when it lands, for
    // the next request; the waiters have their answer now, which is the point of the deadline.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWalkDeadline * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (walk.done) return;
        walk.timedOut = YES;
        finish(walk);
    });
}

void SGLyricsFetch(NSString *trackID, void (^done)(SGLyricsResult *result)) {
    setUp();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!trackID.length) {
            done(nil);
            return;
        }
        id kept = sg_kept[trackID];
        if (kept) {
            done(kept == NSNull.null ? nil : kept);
            return;
        }
        NSMutableArray *waiting = sg_waiting[trackID];
        if (waiting) {
            [waiting addObject:[done copy]];
            return;
        }
        sg_waiting[trackID] = [NSMutableArray arrayWithObject:[done copy]];
        startWalk(trackID, queryFor(trackID));
    });
}

BOOL SGLyricsMayHave(NSString *trackID) {
    setUp();
    @synchronized (sg_missing) { return ![sg_missing containsObject:trackID]; }
}

void SGLyricsPrefetch(NSString *trackID) {
    if (!trackID.length) return;
    SGLyricsFetch(trackID, ^(SGLyricsResult *result) {});
}

NSInteger SGLyricsSpotifyHas(NSString *trackID) {
    setUp();
    if (!trackID) return -1;
    @synchronized (sg_spotifyHas) {
        NSNumber *has = sg_spotifyHas[trackID];
        return has ? has.integerValue : -1;
    }
}

void SGLyricsNoteSpotifyHas(NSString *trackID, BOOL has) {
    setUp();
    if (!trackID.length) return;
    @synchronized (sg_spotifyHas) {
        NSNumber *noted = sg_spotifyHas[trackID];
        if (noted && noted.boolValue == has) return;
        if (sg_spotifyHas.count >= kNotedTracks) [sg_spotifyHas removeAllObjects];
        sg_spotifyHas[trackID] = @(has);
    }
}

NSString *const SGLyricsOwnRequestKey = @"spotifyglass.ownRequest";

// The cards under the player load together, and the list is shown without any card still loading
// once this many milliseconds have passed (NowPlaying_ScrollImpl's scrollCardsAsyncLoadingTimeoutMs,
// 2 s unless the server says otherwise, 1 s at the least). The lyrics card is one of them and waits
// for the color-lyrics reply, which with a source of the mod's on waits for the walk — answered
// within a couple of seconds however slow the sources are; the rest of the wait the reply takes is
// Spotify's own. So the wait is set to the most the flag allows.
id SGLyricsForcedFlag(NSString *key) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGLyricsEnabled(); });
    if (!on) return nil;
    if ([key isEqualToString:@"ios-nowplaying-scroll-impl.scroll_cards_async_loading_timeout_ms"]) return @5000;
    return nil;
}

// After an override; no row shows the timeout, so nothing is locked.
__attribute__((constructor)) static void registerForcer(void) {
    SGRegisterFlagForcer(NO, ^id(NSString *key) { return SGLyricsForcedFlag(key); }, nil);
}

#pragma mark - the language of translations

NSArray<NSString *> *SGLyricsTranslationLanguages(void) {
    return @[@"", @"ar", @"zh-Hans", @"zh-Hant", @"cs", @"da", @"nl", @"en", @"fi", @"fr", @"de", @"el", @"he",
             @"hi", @"hu", @"id", @"it", @"ja", @"ko", @"nb", @"pl", @"pt", @"ro", @"ru", @"sk", @"es", @"sv",
             @"th", @"tr", @"uk", @"vi"];
}

NSArray<NSString *> *SGLyricsTranslationLanguageNames(void) {
    NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en"];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *tag in SGLyricsTranslationLanguages()) {
        [names addObject:tag.length ? [english localizedStringForLocaleIdentifier:tag] ?: tag : @"Any"];
    }
    return names;
}

NSString *SGLyricsTranslationLanguage(void) {
    NSArray<NSString *> *tags = SGLyricsTranslationLanguages();
    NSInteger index = SGInt(SGKeyLyricsTranslationLanguage, 0);
    return index > 0 && index < (NSInteger)tags.count ? tags[(NSUInteger)index] : nil;
}

SGLyricsCredit *SGLyricsCreditFor(NSString *trackID) {
    setUp();
    @synchronized (sg_credits) { return trackID ? sg_credits[trackID] : nil; }
}

void SGLyricsSetCredit(NSString *trackID, SGLyricsCredit *credit) {
    setUp();
    if (!trackID.length) return;
    @synchronized (sg_credits) {
        if (sg_credits.count >= kKeptTracks) [sg_credits removeAllObjects];
        if (!credit) {
            credit = [SGLyricsCredit new];
            credit.provider = @"Spotify";
        }
        sg_credits[trackID] = credit;
    }
}

// Once, at launch: the keys Musixmatch owned alone become an order, so the Lyrics page opens on what
// the install was already doing rather than on nothing.
void SGLyricsMigrateLegacyKeys(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:SGKeyLyricsProviders]) return;
    NSArray<NSString *> *order = fromLegacyKeys();
    if (!order.count) return;
    SGLyricsSetOrder(order);
    SGSetEnabled(SGKeyLyricsAllTracks, SGFlag(kLegacyAllTracks, NO));
    SGLog(@"lyrics: carried the Musixmatch switches over as %@", [order componentsJoinedByString:@", "]);
}
