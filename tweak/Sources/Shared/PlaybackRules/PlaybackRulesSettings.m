#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "PlaybackRules.h"

@interface SGPlaybackRulesPage : SGPage
@end
@implementation SGPlaybackRulesPage {
    NSArray<NSDictionary *> *_rules;
}
- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Playback rules";
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:SGPlaybackRulesDidChangeNotification object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; SGInsetForBars(self.tableView); }
- (void)reload { _rules = SGPlaybackRules(); [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 3; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 2 ? MAX((NSInteger)_rules.count, 1) : 1; }
- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section { return section == 2 ? SGSectionHeader(table, @"Saved rules · swipe to remove") : nil; }
- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section { return section == 2 ? SGSectionHeaderHeight : SGSectionGap; }
- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section { return CGFLOAT_MIN; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"rule");
    if (path.section == 0) {
        SGFillCell(cell, @"Apply playback rules", @"Changes apply immediately", nil, nil);
        UISwitch *toggle = [UISwitch new];
        toggle.onTintColor = SGGreen(); toggle.on = SGFlag(SGKeyPlaybackRules, NO);
        [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (path.section == 1) {
        SGFillCell(cell, @"Add rule for what's playing…", nil, nil, @"minus.circle");
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (!_rules.count) SGFillCell(cell, @"No rules yet", @"Add one here or from the player's ⋯ menu", SGGrey(), nil);
    else {
        NSDictionary *rule = _rules[(NSUInteger)path.row];
        NSInteger kind = [rule[@"kind"] integerValue];
        NSString *detail = kind == SGPlaybackRuleVersion ? @"This version · all releases" : @"This track";
        if (kind == SGPlaybackRuleBreak) {
            NSDate *until = [NSDate dateWithTimeIntervalSince1970:[rule[@"until"] doubleValue]];
            detail = until.timeIntervalSinceNow <= 0 ? @"Break ended · plays again" : [@"On break until " stringByAppendingString:[NSDateFormatter localizedStringFromDate:until dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterNoStyle]];
        }
        SGFillCell(cell, rule[@"title"], [NSString stringWithFormat:@"%@ · %@", rule[@"artist"] ?: @"", detail], nil, nil);
    }
    return cell;
}
- (void)toggled:(UISwitch *)toggle {
    SGSetEnabled(SGKeyPlaybackRules, toggle.on);
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlaybackRulesDidChangeNotification object:nil];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 1) SGPresentPlaybackRuleActions(self, SGPlayerState().track, [table cellForRowAtIndexPath:path]);
}
- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path { return path.section == 2 && _rules.count; }
- (NSString *)tableView:(UITableView *)table titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)path { return @"Remove rule"; }
- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style == UITableViewCellEditingStyleDelete) SGRemovePlaybackRule(_rules[(NSUInteger)path.row][@"id"]);
}
@end
UIViewController *SGPlaybackRulesSettingsPage(void) { return [SGPlaybackRulesPage new]; }
