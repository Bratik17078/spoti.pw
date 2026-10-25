// Compiles the real feature implementations; Spotify's data and audio are fixtures here only.
#import <UIKit/UIKit.h>
#import <math.h>
#import "Core/SGPrefs.h"
#import "Settings/SGModPage.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/PlayerEvents.h"
#import "Shared/PlaybackRules/PlaybackRules.h"
#import "Shared/LyricCards/LyricCards.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/AudioVisualization/Visualization.h"
#import "Redesigned/Player/SGRVisualizer.h"

@implementation SPTPlayerTrack
@end
@implementation SPTPlayerState
@end
@implementation SPTPlayerOptions
@end
static SPTPlayerState *sg_state;
static NSHashTable *sg_observers;
static NSArray *sg_lines;
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : [uri isKindOfClass:NSString.class] ? uri : nil; }
SPTPlayerState *SGPlayerState(void) { return sg_state; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!sg_observers) sg_observers = [NSHashTable weakObjectsHashTable];
    [sg_observers addObject:observer];
}
NSString *const SGPlayerTransitionNotification = @"spotifyglass.playerTransition";
NSString *const SGPlayerTransitionEndedNotification = @"spotifyglass.playerTransitionEnded";
CFTimeInterval SGPlayerTransitionEnds(void) { return 0; }
UIColor *SGRAccent(void) { return UIColor.systemTealColor; }
NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *identifier) { return sg_lines; }
NSInteger SGKaraokePositionMs(void) { return 1500; }
void SGKaraokeRequestLyrics(NSString *identifier) {}

static SPTPlayerTrack *track(NSString *identifier, NSString *title, NSString *artist) {
    SPTPlayerTrack *value = [SPTPlayerTrack new];
    [value setValue:[@"spotify:track:" stringByAppendingString:identifier] forKey:@"URI"];
    [value setValue:title forKey:@"trackTitle"];
    [value setValue:artist forKey:@"artistURI"];
    [value setValue:@"Fixture Artist" forKey:@"artistName"];
    [value setValue:@{} forKey:@"metadata"];
    return value;
}

static void testRules(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    [store removeObjectForKey:SGKeyPlaybackRuleList];
    SPTPlayerTrack *original = track(@"one", @"A Song (Live)", @"spotify:artist:one");
    SPTPlayerTrack *reissue = track(@"two", @"a  song (live)", @"spotify:artist:one");
    SPTPlayerTrack *studio = track(@"three", @"A Song", @"spotify:artist:one");
    SPTPlayerTrack *namesake = track(@"four", @"A Song (Live)", @"spotify:artist:two");
    SGAddPlaybackRule(original, SGPlaybackRuleTrack);
    NSCAssert(SGPlaybackRuleForTrack(original, NSDate.date), @"exact recording must match");
    NSCAssert(!SGPlaybackRuleForTrack(reissue, NSDate.date), @"track rule must not match a different URI");
    SGAddPlaybackRule(original, SGPlaybackRuleTrack);
    NSCAssert(SGPlaybackRules().count == 1, @"duplicate track rules must replace");
    SGRemovePlaybackRule(SGPlaybackRules().firstObject[@"id"]);
    NSCAssert(!SGPlaybackRuleForTrack(original, NSDate.date), @"removed rule must not match");
    SGAddPlaybackRule(original, SGPlaybackRuleVersion);
    NSCAssert(SGPlaybackRuleForTrack(reissue, NSDate.date), @"version rule must span releases");
    NSCAssert(!SGPlaybackRuleForTrack(studio, NSDate.date), @"live rule must not match studio version");
    NSCAssert(!SGPlaybackRuleForTrack(namesake, NSDate.date), @"title alone must never block another artist");
    SGSetEnabled(SGKeyPlaybackRules, NO);
    NSCAssert(!SGPlaybackRuleForTrack(original, NSDate.date), @"master switch must disable all rules");
    [store removeObjectForKey:SGKeyPlaybackRuleList];
    SGAddPlaybackRule(original, SGPlaybackRuleBreak);
    double expiry = [SGPlaybackRules().firstObject[@"until"] doubleValue];
    NSCAssert(SGPlaybackRuleForTrack(original, [NSDate dateWithTimeIntervalSince1970:expiry - 1]), @"break must apply before expiry");
    NSCAssert(!SGPlaybackRuleForTrack(original, [NSDate dateWithTimeIntervalSince1970:expiry]), @"break must stop exactly at expiry");
    NSCAssert(!SGPlaybackRuleForTrack(original, [NSDate dateWithTimeIntervalSince1970:expiry + 1]), @"expired break must remain inactive");
    [store setObject:@[@42, @{}, @{@"id": @"bad", @"uri": @"spotify:track:one", @"title": @"Bad", @"kind": @2, @"until": @"oops"}] forKey:SGKeyPlaybackRuleList];
    NSCAssert(SGPlaybackRules().count == 0, @"malformed backup entries must be ignored");
    [store removeObjectForKey:SGKeyPlaybackRuleList];
    NSLog(@"PASS: exact URI, version/reissue, artist identity, deduplication, removal, switch, expiry and malformed data");
}

static void testCards(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(400, 400)];
    UIImage *art = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.systemIndigoColor setFill]; [context fillRect:CGRectMake(0, 0, 400, 400)];
        [UIColor.systemPinkColor setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(60, 60, 280, 280)] fill];
    }];
    NSArray *scripts = @[@[@"A quiet street beneath the morning sky", @"We watch the city wake and drift on by"],
        @[@"في ضوء الصباح نبدأ من جديد", @"والمدينة تستيقظ بهدوء"],
        @[@"朝の光が街を包んでいる", @"新しい一日が始まる"]];
    NSString *directory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    for (NSInteger style = 0; style < 3; style++) for (NSUInteger script = 0; script < scripts.count; script++) {
        UIImage *image = SGLyricCardImage(@"A very long song title to inspect truncation", @"Fixture Artist", scripts[script], art, style);
        NSCAssert(image && CGImageGetWidth(image.CGImage) == 1080 && CGImageGetHeight(image.CGImage) == 1350, @"card must export at fixed pixel dimensions");
        [UIImagePNGRepresentation(image) writeToFile:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"card-%ld-%lu.png", (long)style, (unsigned long)script]] atomically:YES];
    }
    NSCAssert(SGLyricCardImage(@"No art", @"Artist", scripts[0], nil, 2), @"missing artwork must have a usable fallback");
    NSCAssert(!SGLyricCardImage(@"Empty", @"Artist", @[], art, 0), @"empty selection must not export");
    NSString *huge = [@"word " stringByPaddingToLength:6000 withString:@"word " startingAtIndex:0];
    NSCAssert(!SGLyricCardImage(@"Overflow", @"Artist", @[huge], art, 0), @"oversized selection must not clip");
    NSLog(@"PASS: card dimensions, 3 styles, Latin/Arabic/CJK, missing artwork and overflow; PNGs in %@", directory);
}

@interface FeaturePage : UIViewController
@end
@implementation FeaturePage {
    SGRVisualizer *_visualizer;
    CADisplayLink *_audio;
    double _phase;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Player features"; self.view.backgroundColor = UIColor.blackColor;
    _visualizer = [[SGRVisualizer alloc] initWithFrame:self.view.bounds];
    _visualizer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_visualizer];
    NSArray *titles = @[@"Create lyric card", @"Playback rules", @"Visualizer settings"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[i] forState:UIControlStateNormal]; button.tag = i;
        button.frame = CGRectMake(24, 130 + 60 * i, 300, 50);
        [button addTarget:self action:@selector(open:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:button];
    }
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; _visualizer.playerVisible = YES;
    _audio = [CADisplayLink displayLinkWithTarget:self selector:@selector(feed:)];
    [_audio addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated]; _visualizer.playerVisible = NO; [_audio invalidate]; _audio = nil;
}
- (void)feed:(CADisplayLink *)link {
    float samples[1024];
    for (unsigned i = 0; i < 1024; i++) { samples[i] = 0.6 * sin(_phase); _phase += 6.283185307179586 * 440 / 48000; }
    SGVisualizationPush(samples, 1024, 48000, CACurrentMediaTime());
}
- (void)open:(UIButton *)button {
    if (button.tag == 0) { SGPresentLyricCard(self, sg_state.track); return; }
    UIViewController *page = button.tag == 1 ? SGPlaybackRulesSettingsPage() : [[SGModPage alloc] initWithTitle:@"Visualizer" intro:nil sections:@[SGRVisualizerSection()] footer:nil];
    [self.navigationController pushViewController:page animated:YES];
}
@end
@interface FeatureApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation FeatureApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    testRules(); testCards();
    sg_state = [SPTPlayerState new];
    [sg_state setValue:track(@"one", @"Morning Sky", @"spotify:artist:one") forKey:@"track"];
    [sg_state setValue:@YES forKey:@"isPlaying"];
    sg_lines = SGKaraokeEstimatedLines(@[@0, @2000, @4000], @[@"A quiet street beneath the morning sky", @"We watch the city wake and drift on by", @"And every turn becomes another start"]);
    SGSetEnabled(SGRKeyVisualizer, YES);
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[FeaturePage new]];
    [self.window makeKeyAndVisible]; return YES;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(FeatureApp.class)); } }
