// Settings and a deliberately action-free practice surface for AirPods head gestures.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "HeadGestures.h"

@interface SGHeadGesturePracticePage : SGPage
@end

@implementation SGHeadGesturePracticePage {
    UIView *_arena;
    UIView *_dot;
    UILabel *_status;
    UILabel *_hint;
    BOOL _practising;
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
    self.tableView.tableFooterView = SGNote(@"Nod twice to run the Nod action, or shake left and right to run the Shake action after you leave practice.");
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    CGFloat side = MIN(270, header.bounds.size.width - 48);
    _arena.bounds = CGRectMake(0, 0, side, side);
    _arena.center = CGPointMake(header.bounds.size.width / 2, 20 + side / 2);
    _status.frame = CGRectMake(0, 40 + side, header.bounds.size.width, 24);
    _hint.frame = CGRectMake(20, 70 + side, header.bounds.size.width - 40, 44);
    header.frame = CGRectMake(0, 0, header.bounds.size.width, side + 134);
    SGFitNote(self.tableView, self.tableView.tableFooterView, 16, 24);
    SGInsetForBars(self.tableView);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 0; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_practising) return;
    _practising = YES;
    __weak typeof(self) weakSelf = self;
    SGHeadGesturesBeginPractice(^(CGFloat horizontal, CGFloat vertical, BOOL connected) {
        SGHeadGesturePracticePage *self = weakSelf;
        if (!self) return;
        self->_status.text = connected ? @"Connected" : SGHeadGestureStatus();
        CGFloat radiusX = MAX(0, (self->_arena.bounds.size.width - self->_dot.bounds.size.width) / 2 - 12);
        CGFloat radiusY = MAX(0, (self->_arena.bounds.size.height - self->_dot.bounds.size.height) / 2 - 12);
        CGPoint destination = CGPointMake(CGRectGetMidX(self->_arena.bounds) + horizontal * radiusX,
                                          CGRectGetMidY(self->_arena.bounds) + vertical * radiusY);
        [UIView animateWithDuration:0.08 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
            self->_dot.center = destination;
        } completion:nil];
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (!self.navigationController || ![self.navigationController.viewControllers containsObject:self]) {
        if (_practising) SGHeadGesturesEndPractice();
        _practising = NO;
    }
}

@end

UIViewController *SGHeadGesturesSettingsPage(void) {
    NSArray<NSString *> *actions = SGGestureActionNames();
    SGModRow *enabled = SGOptionRow(@"AirPods head gestures", @"Use compatible AirPods or Beats head motion", SGKeyHeadGestures);
    enabled.info = @"The feature listens only to the public head-motion stream from compatible headphones. It never uses the iPhone’s motion sensors. A compatible pair begins reporting only when it is ready to track your head.";
    enabled.changed = ^(BOOL on) { SGHeadGesturesRefresh(); };
    SGModRow *nod = SGChoiceRow(@"Nod twice", @"Two down-and-up nods", SGKeyHeadGestureNodAction, actions, SGGestureNothing);
    nod.visible = ^BOOL { return SGFlag(SGKeyHeadGestures, NO); };
    SGModRow *shake = SGChoiceRow(@"Shake head", @"One left-and-right shake", SGKeyHeadGestureShakeAction, actions, SGGestureNothing);
    shake.visible = ^BOOL { return SGFlag(SGKeyHeadGestures, NO); };
    SGModRow *practice = SGPageRow(@"Practice", ^UIViewController *{ return [SGHeadGesturePracticePage new]; });
    practice.value = ^NSString *{ return SGHeadGestureStatus(); };
    return [[SGModPage alloc] initWithTitle:@"Head gestures" intro:nil sections:@[
        SGNotedSection(@"AirPods", @[enabled], @"Compatible headphones only. Head motion needs iOS permission the first time it is used."),
        SGSection(@"Actions", @[nod, shake]),
        SGSection(nil, @[practice]),
    ] footer:nil];
}
