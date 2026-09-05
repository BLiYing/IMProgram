//  IMFriendRequestListViewController.m
//  接口与独立成页的理由见头文件。

#import "IMFriendRequestListViewController.h"
#import "IMContactCells.h"
#import "IMUserCard.h"
#import "IMHTTPService.h"
#import "IMReconnectReloader.h"
#import "IMChatDetailViewController.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMLog.h"

@interface IMFriendRequestListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) NSArray<IMUserCard *> *incoming;  // 别人申请我（pending）
@property (nonatomic, strong) NSArray<IMUserCard *> *outgoing;  // 我申请别人（requested）
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) IMReconnectReloader *reconnectReloader;
@end

@implementation IMFriendRequestListViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _incoming = @[];
        _outgoing = @[];
        self.hidesBottomBarWhenPushed = YES;
        __weak typeof(self) ws = self;
        _reconnectReloader = [[IMReconnectReloader alloc] initWithReloadBlock:^{ [ws reload]; }];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"新的朋友";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    // **不用 UITableViewController**：push 页里注入的液态标题栏会整体下移（已踩过三次）。
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 68;
    [self.tableView registerClass:IMContactRequestCell.class forCellReuseIdentifier:@"request"];
    [self.tableView registerClass:IMContactCell.class forCellReuseIdentifier:@"sent"];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"没有待处理的好友申请";
    self.emptyLabel.textColor = IMTheme.textSecondary;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.reconnectReloader.visible = YES;
    [self reload];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.reconnectReloader.visible = NO;
}

#pragma mark - 数据

- (void)reload {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (token.length == 0) {
            IMLog(@"新的朋友刷新登录失败（保留当前内容）：%@", error.localizedDescription ?: @"未知错误");
            return;
        }
        self.token = token;
        // 一次拉全量关系再本地分流：pending / requested 各拉一次是两个来回，
        // 而通讯录本来就要全量（这里独立页也不例外），没必要多一次请求。
        [IMHTTPService.sharedService friendsWithToken:token status:nil completion:^(NSArray<IMUserCard *> *friends, NSError *err) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (err) {
                IMLog(@"新的朋友刷新失败（保留当前内容）：%@", err.localizedDescription ?: @"未知错误");
                return;
            }
            NSMutableArray<IMUserCard *> *incoming = [NSMutableArray array];
            NSMutableArray<IMUserCard *> *outgoing = [NSMutableArray array];
            for (IMUserCard *c in friends ?: @[]) {
                if (c.status == IMFriendStatusPending) { [incoming addObject:c]; }
                else if (c.status == IMFriendStatusRequested) { [outgoing addObject:c]; }
            }
            self.incoming = incoming;
            self.outgoing = outgoing;
            self.emptyLabel.hidden = (incoming.count + outgoing.count) > 0;
            [self.tableView reloadData];
        }];
    }];
}

/// 同意 / 拒绝，完成后重拉。
- (void)performAction:(NSString *)action onPeer:(NSString *)peerID {
    if (self.token.length == 0 || peerID.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService friendActionWithToken:self.token action:action peerID:peerID completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: @"操作失败"]; return; }
        [self reload];
    }];
}

#pragma mark - 分区

/// section 0 = 待我确认；section 1 = 已发出。空的那一节整节不出现（不摆一个空标题）。
- (BOOL)isIncomingSection:(NSInteger)section { return self.incoming.count > 0 && section == 0; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (self.incoming.count > 0 ? 1 : 0) + (self.outgoing.count > 0 ? 1 : 0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)([self isIncomingSection:section] ? self.incoming.count : self.outgoing.count);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self isIncomingSection:section]
        ? [NSString stringWithFormat:@"待我确认（%lu）", (unsigned long)self.incoming.count]
        : [NSString stringWithFormat:@"已发出（%lu）", (unsigned long)self.outgoing.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isIncomingSection:indexPath.section]) {
        IMContactRequestCell *cell = [tableView dequeueReusableCellWithIdentifier:@"request" forIndexPath:indexPath];
        IMUserCard *c = self.incoming[indexPath.row];
        NSString *peer = c.userID;
        __weak typeof(self) ws = self;
        [cell configureWithCard:c
                       onAccept:^{ [ws performAction:@"accept" onPeer:peer]; }
                       onReject:^{ [ws performAction:@"reject" onPeer:peer]; }];
        return cell;
    }
    // 已发出：不给动作按钮，只显「等待验证」+ 自己当时写的验证消息（让人知道这件事的下文）。
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sent" forIndexPath:indexPath];
    IMUserCard *c = self.outgoing[indexPath.row];
    NSString *hello = [c.hello stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [cell configureWithCard:c subtitle:(hello.length > 0 ? hello : @"等待对方验证")];
    [cell setActionTitle:@"等待验证" enabled:NO action:nil];
    return cell;
}

/// 点行 → 进对方资料页（全端统一：点人先进资料页，不直接进聊天，见 [[improgram-tap-member-opens-detail]]）。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IMUserCard *c = [self isIncomingSection:indexPath.section] ? self.incoming[indexPath.row] : self.outgoing[indexPath.row];
    if (c.userID.length == 0 || [c.userID isEqualToString:self.userID]) { return; }
    IMChatDetailViewController *detail =
        [[IMChatDetailViewController alloc] initSingleWithHost:self.host userID:self.userID
                                                        peerID:c.userID
                                                  peerNickname:c.nickname
                                                 peerAvatarURL:c.avatarURL];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
