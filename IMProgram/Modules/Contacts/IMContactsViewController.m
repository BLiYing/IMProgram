//  IMContactsViewController.m

#import "IMContactsViewController.h"
#import "IMUserSearchViewController.h"
#import "IMContactCells.h"
#import "IMChatViewController.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "IMTheme.h"
#import "IMLog.h"

@interface IMContactsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) NSArray<IMUserCard *> *pending;   // 对方申请我，待我同意/拒绝
@property (nonatomic, strong) NSArray<IMUserCard *> *accepted;  // 已是好友
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation IMContactsViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _pending = @[];
        _accepted = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"通讯录";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"person.badge.plus"]
                                         style:UIBarButtonItemStylePlain target:self action:@selector(addFriendTapped)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 68;
    [self.tableView registerClass:IMContactCell.class forCellReuseIdentifier:@"friend"];
    [self.tableView registerClass:IMContactRequestCell.class forCellReuseIdentifier:@"request"];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"还没有好友，点右上角 + 搜索用户添加";
    self.emptyLabel.textColor = IMTheme.textSecondary;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:IMTheme.space4 * 2],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-IMTheme.space4 * 2],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

#pragma mark - 数据

- (void)reload {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            [self showError:[NSString stringWithFormat:@"登录失败：%@", error.localizedDescription]];
            return;
        }
        self.token = token;
        [IMHTTPService.sharedService friendsWithToken:token status:nil completion:^(NSArray<IMUserCard *> *friends, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (err) {
                [self showError:[NSString stringWithFormat:@"拉取好友失败：%@", err.localizedDescription]];
                return;
            }
            [self applyFriends:friends ?: @[]];
        }];
    }];
}

/// 拆分为"新的朋友"(pending) 与 好友(accepted)；好友按更新时间倒序。
- (void)applyFriends:(NSArray<IMUserCard *> *)friends {
    NSMutableArray<IMUserCard *> *pending = [NSMutableArray array];
    NSMutableArray<IMUserCard *> *accepted = [NSMutableArray array];
    for (IMUserCard *c in friends) {
        if (c.status == IMFriendStatusPending) { [pending addObject:c]; }
        else if (c.status == IMFriendStatusAccepted) { [accepted addObject:c]; }
    }
    [accepted sortUsingComparator:^NSComparisonResult(IMUserCard *a, IMUserCard *b) {
        if (a.updatedAt == b.updatedAt) { return NSOrderedSame; }
        return a.updatedAt > b.updatedAt ? NSOrderedAscending : NSOrderedDescending;
    }];
    self.pending = pending;
    self.accepted = accepted;
    self.emptyLabel.hidden = (pending.count + accepted.count) > 0;
    [self.tableView reloadData];
    // Tab 角标：把待处理申请数显示在"通讯录"Tab 上（清零靠重新进入时再算）。
    self.navigationController.tabBarItem.badgeValue = pending.count > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)pending.count] : nil;
}

#pragma mark - 交互

- (void)addFriendTapped {
    IMUserSearchViewController *search = [[IMUserSearchViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:search animated:YES];
}

/// 对某对端执行好友动作（同意/拒绝），完成后刷新列表。
- (void)performAction:(NSString *)action onPeer:(NSString *)peerID {
    if (self.token.length == 0 || peerID.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService friendActionWithToken:self.token action:action peerID:peerID completion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) {
            [self showError:[NSString stringWithFormat:@"操作失败：%@", error.localizedDescription]];
            return;
        }
        [self reload];
    }];
}

- (void)openChatWithPeer:(NSString *)peerID {
    if (peerID.length == 0 || [peerID isEqualToString:self.userID]) { return; }
    // 从通讯录进入等同"发起会话"：无已读位点/未读/对端已读位点，聊天页自行向服务端同步。
    IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:self.host userID:self.userID
                                                                    peerID:peerID readSeq:0 unread:0 peerReadSeq:0];
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)showError:(NSString *)message {
    IMLog(@"%@", message);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 分区映射

/// 有待处理申请时：section 0 = 新的朋友，section 1 = 好友；否则只有 好友。
- (BOOL)hasRequestsSection {
    return self.pending.count > 0;
}
- (BOOL)isRequestsSection:(NSInteger)section {
    return [self hasRequestsSection] && section == 0;
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self hasRequestsSection] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self isRequestsSection:section] ? self.pending.count : self.accepted.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self isRequestsSection:section]) {
        return [NSString stringWithFormat:@"新的朋友（%lu）", (unsigned long)self.pending.count];
    }
    return [NSString stringWithFormat:@"好友（%lu）", (unsigned long)self.accepted.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isRequestsSection:indexPath.section]) {
        IMContactRequestCell *cell = [tableView dequeueReusableCellWithIdentifier:@"request" forIndexPath:indexPath];
        IMUserCard *c = self.pending[indexPath.row];
        NSString *peer = c.userID;
        __weak typeof(self) weakSelf = self;
        [cell configureWithCard:c
                       onAccept:^{ [weakSelf performAction:@"accept" onPeer:peer]; }
                       onReject:^{ [weakSelf performAction:@"reject" onPeer:peer]; }];
        return cell;
    }
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:@"friend" forIndexPath:indexPath];
    IMUserCard *c = self.accepted[indexPath.row];
    [cell configureWithCard:c subtitle:c.userID];
    [cell setActionTitle:nil enabled:NO action:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isRequestsSection:indexPath.section]) { return; } // 申请行靠按钮操作，不整行点击
    [self openChatWithPeer:self.accepted[indexPath.row].userID];
}

@end
