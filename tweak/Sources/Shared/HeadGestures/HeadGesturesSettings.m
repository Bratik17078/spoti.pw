// Settings and a deliberately action-free practice surface for AirPods head gestures.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import <math.h>
#import "HeadGestures.h"

@interface SGHeadGesturePracticePage : SGPage
- (void)positionDot;
@end

@implementation SGHeadGesturePracticePage {
    UIView *_arena;
    UIView *_dot;
    UILabel *_status;
    UILabel *_hint;
    BOOL _practising;
    CGFloat _horizontal, _vertical;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Practice head gestures";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _arena = [[UIView alloc] initWithFrame:CGRectMake(0, 20, 0, 270)];
    _arena.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    _arena.layer.cornerRadius = 135;
    _arena.layer.cornerCurve = kCACornerCurveContinuous;
    _arena.layer.borderWidth = 1;
    _arena.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    _arena.accessibilityLabel = @"Head position";
    _dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 34, 34)];
    _dot.backgroundColor = SGGreen();
    _dot.layer.cornerRadius = 17;
    _dot.layer.shadowColor = SGGreen().CGColor;
    _dot.layer.shadowOpacity = 0.8;
    _dot.layer.shadowRadius = 12;
    [_arena addSubview:_dot];
    _status = [UILabel new];
    _status.font = SGTitleFont();
    _status.textAlignment = NSTextAlignmentCenter;
    _status.textColor = UIColor.whiteColor;
    _status.frame = CGRectMake(0, 310, 0, 24);
    _hint = [UILabel new];
    _hint.font = SGSubtitleFont();
    _hint.textColor = SGGrey();
    _hint.textAlignment = NSTextAlignmentCenter;
    _hint.numberOfLines = 2;
    _hint.text = @"Move your head to guide the circle.\nPractice never controls playback.";
    _hint.frame = CGRectMake(20, 340, 0, 44);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 404)];
    [header addSubview:_arena];
    [header addSubview:_status];
    [header addSubview:_hint];
    _arena.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView = header;
    self.tableView.tableFooterView = SGNote(@"Practice follows your head without controlling playback. Face forward and tap Recenter whenever the dot drifts.");
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    CGFloat side = MAX(0, MIN(270, header.bounds.size.width - 48));
    _arena.bounds = CGRectMake(0, 0, side, side);
    _arena.layer.cornerRadius = side / 2;
    _arena.center = CGPointMake(header.bounds.size.width / 2, 20 + side / 2);
    _status.frame = CGRectMake(0, 40 + side, header.bounds.size.width, 24);
    _hint.frame = CGRectMake(20, 70 + side, header.bounds.size.width - 40, 44);
    if (fabs(header.bounds.size.height - (side + 134)) > 1) {
        header.frame = CGRectMake(0, 0, header.bounds.size.width, side + 134);
        self.tableView.tableHeaderView = header;
    }
    [self positionDot];
    SGFitNote(self.tableView, self.tableView.tableFooterView, 16, 24);
    SGInsetForBars(self.tableView);
}

- (void)positionDot {
    CGFloat radius = MAX(0, (_arena.bounds.size.width - _dot.bounds.size.width) / 2 - 16);
    _dot.center = CGPointMake(CGRectGetMidX(_arena.bounds) + _horizontal * radius,
                              CGRectGetMidY(_arena.bounds) + _vertical * radius);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 1; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return 1; }

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"recenter");
    SGFillCell(cell, @"Recenter", @"Face forward, then tap", nil, @"scope");
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    SGHeadGesturesRecenter();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_practising) return;
    _practising = YES;
    __weak typeof(self) weakSelf = self;
    SGHeadGesturesBeginPractice(^(CGFloat horizontal, CGFloat vertical, BOOL connected) {
        SGHeadGesturePracticePage *self = weakSelf;
        if (!self) return;
        self->_status.text = connected ? @"Connected" : SGHeadGestureStatus();
        self->_horizontal = horizontal;
        self->_vertical = vertical;
        [self positionDot];
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (_practising) SGHeadGesturesEndPractice();
    _practising = NO;
}

@end

UIViewController *SGHeadGesturesSettingsPage(void) {
    NSArray<NSString *> *actions = SGGestureActionNames();
    SGModRow *enabled = SGOptionRow(@"AirPods head gestures", @"Use compatible AirPods or Beats head motion", SGKeyHeadGestures);
    enabled.info = @"The feature listens only to the public head-motion stream from compatible headphones. It never uses the iPhone’s motion sensors. A compatible pair begins reporting only when it is ready to track your head.";
    enabled.changed = ^(BOOL on) { SGHeadGesturesRefresh(); };
    BOOL (^enabledNow)(void) = ^BOOL { return SGFlag(SGKeyHeadGestures, NO); };
    SGModRow *nodOnce = SGChoiceRow(@"Nod once", @"One down-and-up nod", SGKeyHeadGestureNodOnceAction, actions, SGGestureNothing);
    nodOnce.visible = enabledNow;
    SGModRow *nod = SGChoiceRow(@"Nod twice", @"Two down-and-up nods", SGKeyHeadGestureNodAction, actions, SGGestureNothing);
    nod.visible = enabledNow;
    SGModRow *shake = SGChoiceRow(@"Shake head", @"One left-and-right shake", SGKeyHeadGestureShakeAction, actions, SGGestureNothing);
    shake.visible = enabledNow;
    SGModRow *tiltLeft = SGChoiceRow(@"Tilt left", @"Ear toward left shoulder", SGKeyHeadGestureTiltLeftAction, actions, SGGestureNothing);
    tiltLeft.visible = enabledNow;
    SGModRow *tiltRight = SGChoiceRow(@"Tilt right", @"Ear toward right shoulder", SGKeyHeadGestureTiltRightAction, actions, SGGestureNothing);
    tiltRight.visible = enabledNow;
    SGModRow *sensitivity = SGSliderRow(@"Sensitivity", @"Higher needs less movement", 1, 5, 1,
        ^double { return SGHeadGestureSensitivity(); },
        ^(double value) { SGSetInt(SGKeyHeadGestureSensitivity, lround(value)); },
        ^NSString *(double value) {
            NSInteger index = MAX(0, MIN(4, (NSInteger)lround(value) - 1));
            return @[@"Very low", @"Low", @"Medium", @"High", @"Very high"][(NSUInteger)index];
        });
    sensitivity.visible = enabledNow;
    SGModRow *practice = SGPageRow(@"Practice", ^UIViewController *{ return [SGHeadGesturePracticePage new]; });
    practice.value = ^NSString *{ return SGHeadGestureStatus(); };
    return [[SGModPage alloc] initWithTitle:@"Head gestures" intro:nil sections:@[
        SGNotedSection(@"AirPods", @[enabled], @"Compatible headphones only. Head motion needs iOS permission the first time it is used."),
        SGNotedSection(@"Actions", @[nodOnce, nod, shake, tiltLeft, tiltRight],
                       @"If both nods have actions, a single nod waits briefly for a possible second nod."),
        SGSection(@"Recognition", @[sensitivity]),
        SGSection(nil, @[practice]),
    ] footer:nil];
}
