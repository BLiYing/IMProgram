//  IMFriendRequestListViewController.m
//  接口与独立成页的理由见头文件。

#import "IMFriendRequestListViewController.h"
#import "IMLocalization.h"
#import "IMContactCells.h"
#import "IMUserCard.h"
#import "IMFriendRequestSections.h"
#import "IMHTTPService.h"
#import "IMReconnectReloader.h"
#import "IMChatDetailViewController.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMLog.h"

NSString * const IMFriendRelationDidChangeLocallyNotification = @"IMFriendRelationDidChangeLocallyNotification";

void IMPostFriendRelationDidChangeLocally(void) {
    dispatch_block_t post = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:IMFriendRelationDidChangeLocallyNotification object:nil];
    };
    if (NSThread.isMainThread) { post(); } else { dispatch_async(dispatch_get_main_queue(), post); }
}

@interface IMFriendRequestListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) NSArray<IMUserCard *> *incoming;  // 别人申请我（pending）
@property (nonatomic, strong) NSArray<IMUserCard *> *outgoing;  // 我申请别人（requested）
@property (nonatomic, strong) NSArray<IMUserCard *> *added;     // 最近 30 天内已添加（accepted，最多 50）
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
        _added = @[];
        self.hidesBottomBarWhenPushed = YES;
        __weak typeof(self) ws = self;
        _reconnectReloader = [[IMReconnectReloader alloc] initWithReloadBlock:^{ [ws reload]; }];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"friend.requests.title");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    // **不用 UITableViewController**：push 页里注入的液态标题栏会整体下移（已踩过三次）。
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 68;
    [self.tableView registerClass:IMContactRequestCell.class forCellReuseIdentifier:@"request"];
    [self.tableView registerClass:IMContactCell.class forCellReuseIdentifier:@"sent"];
    [self.tableView registerClass:IMContactCell.class forCellReuseIdentifier:@"added"];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = IMLocalized(@"friend.requests.empty");
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
            int64_t nowMs = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
            IMFriendRequestSections *sections = [IMFriendRequestSections sectionsWithCards:friends nowMs:nowMs];
            self.incoming = sections.incoming;
            self.outgoing = sections.outgoing;
            self.added = sections.added;
            self.emptyLabel.hidden = !sections.isEmpty;
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
        if (error) { [self im_showToast:error.localizedDescription ?: IMLocalized(@"common.action_failed")]; return; }
        // 服务端 Accept 只推申请方：本机通讯录页收不到事件，靠本地通知立即刷新（绕过 30s 切入节流）。
        IMPostFriendRelationDidChangeLocally();
        [self reload];
    }];
}

#pragma mark - 分区

/// 段顺序固定：待我确认 → 已发出 → 已添加；空段整段不出现（不摆空标题）。
typedef NS_ENUM(NSInteger, IMRequestSectionKind) { IMRequestSectionIncoming, IMRequestSectionOutgoing, IMRequestSectionAdded };

- (NSArray<NSNumber *> *)visibleSectionKinds {
    NSMutableArray<NSNumber *> *kinds = [NSMutableArray arrayWithCapacity:3];
    if (self.incoming.count > 0) { [kinds addObject:@(IMRequestSectionIncoming)]; }
    if (self.outgoing.count > 0) { [kinds addObject:@(IMRequestSectionOutgoing)]; }
    if (self.added.count > 0) { [kinds addObject:@(IMRequestSectionAdded)]; }
    return kinds;
}

- (IMRequestSectionKind)kindForSection:(NSInteger)section {
    NSArray<NSNumber *> *kinds = [self visibleSectionKinds];
    return (IMRequestSectionKind)(section < (NSInteger)kinds.count ? kinds[section].integerValue : IMRequestSectionAdded);
}

- (NSArray<IMUserCard *> *)cardsForKind:(IMRequestSectionKind)kind {
    switch (kind) {
        case IMRequestSectionIncoming: return self.incoming;
        case IMRequestSectionOutgoing: return self.outgoing;
        case IMRequestSectionAdded: return self.added;
    }
    return @[];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)[self visibleSectionKinds].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self cardsForKind:[self kindForSection:section]].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ([self kindForSection:section]) {
        case IMRequestSectionIncoming: return IMLocalizedFormat(@"friend.requests.incoming", (long)self.incoming.count);
        case IMRequestSectionOutgoing: return IMLocalizedFormat(@"friend.requests.outgoing", (long)self.outgoing.count);
        case IMRequestSectionAdded: return IMLocalizedFormat(@"friend.requests.added", (long)self.added.count);
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMRequestSectionKind kind = [self kindForSection:indexPath.section];
    if (kind == IMRequestSectionIncoming) {
        IMContactRequestCell *cell = [tableView dequeueReusableCellWithIdentifier:@"request" forIndexPath:indexPath];
        IMUserCard *c = self.incoming[indexPath.row];
        NSString *peer = c.userID;
        __weak typeof(self) ws = self;
        [cell configureWithCard:c
                       onAccept:^{ [ws performAction:@"accept" onPeer:peer]; }
                       onReject:^{ [ws performAction:@"reject" onPeer:peer]; }];
        return cell;
    }
    if (kind == IMRequestSectionAdded) {
        // 已添加：副标题 = @句柄（无句柄的系统账号等 → 隐藏副标题行）；右侧禁用「已添加」标记；
        // 刻意不提供删除/左滑（服务端只有「删好友关系」，没有「删记录」，见设计稿 §2）。
        IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:@"added" forIndexPath:indexPath];
        IMUserCard *c = self.added[indexPath.row];
        [cell configureWithCard:c subtitle:(c.username.length > 0 ? [@"@" stringByAppendingString:c.username] : nil)];
        [cell setActionTitle:IMLocalized(@"friend.requests.added_tag") enabled:NO action:nil];
        return cell;
    }
    // 已发出：不给动作按钮，只显「等待验证」+ 自己当时写的验证消息（让人知道这件事的下文）。
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sent" forIndexPath:indexPath];
    IMUserCard *c = self.outgoing[indexPath.row];
    NSString *hello = [c.hello stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [cell configureWithCard:c subtitle:(hello.length > 0 ? hello : IMLocalized(@"friend.requests.waiting_hint"))];
    [cell setActionTitle:IMLocalized(@"friend.requests.waiting") enabled:NO action:nil];
    return cell;
}

/// 点行 → 进对方资料页（全端统一：点人先进资料页，不直接进聊天，见 [[improgram-tap-member-opens-detail]]）。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IMUserCard *c = [self cardsForKind:[self kindForSection:indexPath.section]][indexPath.row];
    if (c.userID.length == 0 || [c.userID isEqualToString:self.userID]) { return; }
    IMChatDetailViewController *detail =
        [[IMChatDetailViewController alloc] initSingleWithHost:self.host userID:self.userID
                                                        peerID:c.userID
                                                  peerNickname:c.nickname
                                                 peerAvatarURL:c.avatarURL];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
