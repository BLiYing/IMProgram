//  IMUserSearchViewController.m

#import "IMUserSearchViewController.h"
#import "IMContactCells.h"
#import "IMChatViewController.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "IMTheme.h"
#import "IMLog.h"

@interface IMUserSearchViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) NSArray<IMUserCard *> *results;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *statusByUser; // uid → IMFriendStatus
@property (nonatomic, assign) BOOL searched; // 是否搜索过（区分"未搜索"与"无结果"）
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *hintLabel;
@end

@implementation IMUserSearchViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _results = @[];
        _statusByUser = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"添加朋友";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.placeholder = @"对方完整 uid 或手机号";
    self.searchBar.delegate = self;
    self.searchBar.returnKeyType = UIReturnKeySearch;
    [self.searchBar sizeToFit];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 68;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.tableHeaderView = self.searchBar;
    [self.tableView registerClass:IMContactCell.class forCellReuseIdentifier:@"user"];
    [self.view addSubview:self.tableView];

    self.hintLabel = [UILabel new];
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.hintLabel.text = @"输入关键词搜索用户";
    self.hintLabel.textColor = IMTheme.textSecondary;
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.hintLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.hintLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.hintLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:40],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadRelations];
}

#pragma mark - 数据

/// 登录拿 token，并拉好友关系建 uid→status 映射，供结果按钮判定。
- (void)loadRelations {
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
        [self refreshStatusMapThen:nil];
    }];
}

/// 拉好友列表重建 uid→status 映射；done 在主线程回调（用于动作后刷新按钮）。
- (void)refreshStatusMapThen:(nullable void (^)(void))done {
    if (self.token.length == 0) { if (done) { done(); } return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService friendsWithToken:self.token status:nil completion:^(NSArray<IMUserCard *> *friends, NSError *err) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (!err) {
            NSMutableDictionary<NSString *, NSNumber *> *map = [NSMutableDictionary dictionary];
            for (IMUserCard *c in friends) { map[c.userID] = @(c.status); }
            self.statusByUser = map;
            [self.tableView reloadData];
        }
        if (done) { done(); }
    }];
}

- (void)runSearch:(NSString *)query {
    NSString *q = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (q.length == 0 || self.token.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService searchUsersWithToken:self.token query:q completion:^(NSArray<IMUserCard *> *users, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) {
            [self showError:[NSString stringWithFormat:@"搜索失败：%@", error.localizedDescription]];
            return;
        }
        self.searched = YES;
        self.results = users ?: @[];
        self.hintLabel.text = self.results.count > 0 ? @"" : @"没有找到匹配的用户";
        self.hintLabel.hidden = self.results.count > 0;
        [self.tableView reloadData];
    }];
}

#pragma mark - 交互

- (IMFriendStatus)statusForUser:(NSString *)uid {
    NSNumber *n = self.statusByUser[uid];
    return n ? (IMFriendStatus)n.integerValue : IMFriendStatusNone;
}

/// 对某对端执行好友动作（申请/同意），完成后刷新关系映射（按钮随之更新）。
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
        [self refreshStatusMapThen:nil];
    }];
}

- (void)openChatWithPeer:(NSString *)peerID {
    if (peerID.length == 0 || [peerID isEqualToString:self.userID]) { return; }
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

#pragma mark - UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self runSearch:searchBar.text];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:@"user" forIndexPath:indexPath];
    IMUserCard *c = self.results[indexPath.row];
    NSString *subtitle = c.userID;
    if (c.tags.count > 0) {
        subtitle = [NSString stringWithFormat:@"%@ · %@", c.userID, [c.tags componentsJoinedByString:@" "]];
    }
    [cell configureWithCard:c subtitle:subtitle];

    NSString *peer = c.userID;
    __weak typeof(self) weakSelf = self;
    switch ([self statusForUser:peer]) {
        case IMFriendStatusAccepted: {
            [cell setActionTitle:@"发消息" enabled:YES action:^{ [weakSelf openChatWithPeer:peer]; }];
            break;
        }
        case IMFriendStatusRequested: {
            [cell setActionTitle:@"已申请" enabled:NO action:nil];
            break;
        }
        case IMFriendStatusPending: {
            [cell setActionTitle:@"同意" enabled:YES action:^{ [weakSelf performAction:@"accept" onPeer:peer]; }];
            break;
        }
        case IMFriendStatusBlocked: {
            [cell setActionTitle:@"已拉黑" enabled:NO action:nil];
            break;
        }
        case IMFriendStatusNone:
        default: {
            [cell setActionTitle:@"加好友" enabled:YES action:^{ [weakSelf performAction:@"request" onPeer:peer]; }];
            break;
        }
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

@end
