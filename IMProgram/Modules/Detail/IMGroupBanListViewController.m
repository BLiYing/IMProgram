//  IMGroupBanListViewController.m

#import "IMGroupBanListViewController.h"
#import "IMHTTPService.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMAccountIdentity.h"

@interface IMGroupBanListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *bans; ///< [{user_id,banned_by,banned_at,expires_at}]
@end

@implementation IMGroupBanListViewController

- (instancetype)initWithConvID:(NSString *)convID {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _convID = [convID copy];
        _bans = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"黑名单";
    self.view.backgroundColor = IMTheme.groupedBackground;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [self reload];
}

- (void)reload {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService groupBansWithToken:token convID:self.convID
                                        completion:^(NSArray<NSDictionary *> *bans, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: @"加载失败"]; return; }
        self.bans = bans ?: @[];
        [self.tableView reloadData];
    }];
}

#pragma mark - 数据源

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(1, (NSInteger)self.bans.count); // 空态占一行提示
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.bans.count ? @"左滑可解除拉黑。冷却期到期后会自动移出黑名单。" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"c" forIndexPath:indexPath];
    cell.textLabel.textColor = IMTheme.textPrimary;
    cell.detailTextLabel.textColor = IMTheme.textSecondary;
    if (self.bans.count == 0) {
        cell.textLabel.text = @"暂无被拉黑成员";
        cell.textLabel.textColor = IMTheme.textSecondary;
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *b = self.bans[indexPath.row];
    NSString *nick = [b[@"nickname"] isKindOfClass:[NSString class]] ? b[@"nickname"] : @"";
    NSString *uname = [b[@"username"] isKindOfClass:[NSString class]] ? b[@"username"] : @"";
    int64_t expires = [b[@"expires_at"] respondsToSelector:@selector(longLongValue)] ? [b[@"expires_at"] longLongValue] : 0;
    // 主标题=显示名（末级不落 uid），副标题=@句柄 + 封禁档位。管理员要认得出拉黑的是谁，
    // 而 uid 是 10 位随机数字（docs/UI.md「用户标识」）。
    cell.textLabel.text = IMDisplayName(nick, uname);
    NSString *state = expires == 0 ? @"永久" : @"冷却中";
    cell.detailTextLabel.text = uname.length > 0
        ? [NSString stringWithFormat:@"@%@ · %@", uname, state]
        : state;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

// 左滑解除拉黑。
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.bans.count == 0) { return nil; }
    NSDictionary *b = self.bans[indexPath.row];
    NSString *uid = [b[@"user_id"] isKindOfClass:[NSString class]] ? b[@"user_id"] : @"";
    __weak typeof(self) ws = self;
    UIContextualAction *unban = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"解除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        NSString *token = IMHTTPService.sharedService.currentToken;
        if (token.length == 0) { done(NO); return; }
        [IMHTTPService.sharedService unbanGroupMemberWithToken:token convID:ws.convID userID:uid
                                                   completion:^(NSError *error) {
            __strong typeof(ws) self = ws;
            if (!self) { done(NO); return; }
            if (error) { [self im_showToast:error.localizedDescription ?: @"解除失败"]; done(NO); return; }
            [self im_showToast:@"已解除"];
            [self reload];
            done(YES);
        }];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[unban]];
}

@end
