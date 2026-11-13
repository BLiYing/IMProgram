//  IMFriendListViewController.m

#import "IMFriendListViewController.h"
#import "IMContactsViewController.h"          // IMContactsShouldRefreshOnAppear（切入刷新节流判据）
#import "IMFriendRequestListViewController.h" // IMFriendRelationDidChangeLocallyNotification
#import "IMFriendCacheWriter.h"
#import "IMFriendRoster.h"
#import "IMLocalization.h"
#import "IMContactCells.h"
#import "IMContactSectionIndex.h"
#import "IMChatDetailViewController.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMReconnectReloader.h"
#import "IMUserCard.h"
#import "IMRemarkStore.h"
#import "IMDatabase.h"
#import "IMTheme.h"
#import "IMLog.h"

/// 回到本页（从资料页返回等）的刷新节流间隔；变化靠好友事件与重连兜住。与通讯录首页同值。
static const CFTimeInterval kIMFriendListAppearRefreshInterval = 30;
/// 好友事件连发的合并窗口。
static const NSTimeInterval kIMFriendListEventCoalesceDelay = 0.3;
static NSString * const kIMFriendListCellID = @"friend";

@interface IMFriendListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) NSArray<IMUserCard *> *accepted;    // 已是好友（原始集合；分组展示走 friendIndex）
@property (nonatomic, strong) IMContactSectionIndex *friendIndex; // 好友 A–Z 分组索引（右侧纵向索引尺 + 字母表头）
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIView *emptyFooter;  // 承载 emptyLabel 的表尾容器（见 layoutEmptyFooter）
@property (nonatomic, strong, nullable) IMDatabaseAccountContext *databaseContext; // 本地缓存账号隔离
@property (nonatomic, strong) IMReconnectReloader *reconnectReloader;              // 重连即取权威（可见时）
@property (nonatomic, assign) NSUInteger indexGeneration;   // 最近一次发起的索引构建代号；回来的不是这一代就丢弃
@property (nonatomic, assign) CFTimeInterval lastRefreshAt; // 最近一次拉到权威好友列表的时刻（CACurrentMediaTime，0=从未）
@property (nonatomic, assign) BOOL refreshInFlight;         // 好友列表请求在途（切入节流用）
@property (nonatomic, assign) BOOL eventReloadScheduled;    // 好友事件的合并刷新已排队
@end

@implementation IMFriendListViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                 seedFriends:(NSArray<IMUserCard *> *)seedFriends {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        self.hidesBottomBarWhenPushed = YES;
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        // 首屏种子：首页手上的名单优先（零 IO）；没有才读上次落库的快照（断网也能看到列表），联网成功再权威覆盖。
        _accepted = seedFriends ? [seedFriends copy] : [IMFriendCacheWriter cachedFriendsWithContext:_databaseContext];
        // 种子也分组，离线首屏即带索引。后台算：2000 人同步分组会把 push 转场卡住。
        _friendIndex = [[IMContactSectionIndex alloc] initWithCards:@[]];
        [self rebuildFriendIndexWithReason:@"seed"];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(onFriendEvent)
                       name:IMSocketDidReceiveFriendEventNotification object:nil];
        // 本机主动改好友关系（同意/拒绝/拉黑/删好友）：服务端不回推本机，立即重拉（绕过切入节流）。
        [center addObserver:self selector:@selector(reload)
                       name:IMFriendRelationDidChangeLocallyNotification object:nil];
        // 备注名变更（本机详情页改 / 其它设备改）：显示名与首字母分组都会变，就地重排即可，
        // 不必回服务端——displayName 读的是 IMRemarkStore，本地数据已是最新。
        [center addObserver:self selector:@selector(onRemarkChanged)
                       name:IMRemarkStoreDidChangeNotification object:nil];
        __weak typeof(self) weakSelf = self;
        _reconnectReloader = [[IMReconnectReloader alloc] initWithReloadBlock:^{ [weakSelf reload]; }];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"contacts.entry.my_friends");
    self.view.backgroundColor = IMTheme.groupedBackground;

    // **不用 UITableViewController**：push 页里注入的液态标题栏会整体下移（已踩过三次）。
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 68;
    [self.tableView registerClass:IMContactCell.class forCellReuseIdentifier:kIMFriendListCellID];
    [self.view addSubview:self.tableView];

    // 空态文案挂 tableView 的表尾（随内容流排布，沿用原通讯录页的做法）。
    self.emptyLabel = [UILabel new];
    self.emptyLabel.text = IMLocalized(@"contacts.friends.empty");
    self.emptyLabel.textColor = IMTheme.textSecondary;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyFooter = [UIView new];
    [self.emptyFooter addSubview:self.emptyLabel];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutEmptyFooter]; // 宽度变了（旋转/分屏）要重排文案
}

/// 表尾空态排版：表尾视图**不参与 Auto Layout**，必须自己按当前宽度算出具体 frame。
/// 高度变了才回写 tableFooterView（赋值会触发一次布局，无条件回写就是死循环）。
- (void)layoutEmptyFooter {
    if (self.tableView.tableFooterView != self.emptyFooter) { return; }
    CGFloat inset = IMTheme.space4 * 2;
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= inset * 2) { return; }
    CGSize fit = [self.emptyLabel sizeThatFits:CGSizeMake(width - inset * 2, CGFLOAT_MAX)];
    self.emptyLabel.frame = CGRectMake(inset, inset, width - inset * 2, fit.height);
    CGRect target = CGRectMake(0, 0, width, fit.height + inset * 2);
    if (CGRectEqualToRect(self.emptyFooter.frame, target)) { return; }
    self.emptyFooter.frame = target;
    self.tableView.tableFooterView = self.emptyFooter;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.reconnectReloader.visible = YES;
    // 首次进入必拉（lastRefreshAt=0）；从资料页返回按节流，变化由上面三条通知兜住。
    if (IMContactsShouldRefreshOnAppear(self.refreshInFlight, self.lastRefreshAt,
                                        CACurrentMediaTime(), kIMFriendListAppearRefreshInterval)) {
        [self reload];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.reconnectReloader.visible = NO;
}

#pragma mark - 通知

/// 备注名变更 → 按新显示名重排分桶并刷新（纯本地，零请求）。
- (void)onRemarkChanged {
    [self rebuildFriendIndexWithReason:@"remark"];
}

/// 收到好友事件 → 合并连发后刷新一次（在途标记 + dispatch_after + weak self，见 CODING_STYLE §8）。
- (void)onFriendEvent {
    if (self.eventReloadScheduled) { return; }
    self.eventReloadScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kIMFriendListEventCoalesceDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        self.eventReloadScheduled = NO;
        [self reload];
    });
}

#pragma mark - 数据

- (void)reload {
    self.refreshInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [IMFriendRoster fetchWithHost:self.host userID:self.userID context:self.databaseContext source:@"我的好友"
                       completion:^(IMFriendRoster *roster, NSString *token) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        self.refreshInFlight = NO;
        if (token.length > 0) { self.token = token; } // 左滑删除 / 拉黑要用
        if (roster) { [self applyRoster:roster]; } // 失败保留当前内容（helper 已打日志）
    }];
}

/// 按 self.accepted 重建 A–Z 索引：拼音分组在后台队列算，回主线程只做赋值 + reloadData。
/// 连发时以最后一次发起为准（代号不匹配的结果直接丢弃），慢结果不会盖掉新数据。
- (void)rebuildFriendIndexWithReason:(NSString *)reason {
    NSUInteger generation = ++self.indexGeneration;
    NSUInteger count = self.accepted.count;
    CFTimeInterval startedAt = CACurrentMediaTime();
    __weak typeof(self) weakSelf = self;
    [IMContactSectionIndex buildWithCards:self.accepted completion:^(IMContactSectionIndex *index) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.indexGeneration) { return; }
        self.friendIndex = index;
        [self.tableView reloadData];
        IMLogUI(@"contacts_index_applied reason=%@ friends=%lu latency_ms=%.0f",
                reason, (unsigned long)count, (CACurrentMediaTime() - startedAt) * 1000);
    }];
}

/// 好友（accepted）按拼音首字母分组（A–Z + 右侧索引尺，见 friendIndex）；落库已由 IMFriendRoster 做完。
- (void)applyRoster:(IMFriendRoster *)roster {
    NSArray<IMUserCard *> *accepted = roster.accepted;
    self.accepted = accepted;
    self.lastRefreshAt = CACurrentMediaTime();
    // 表尾空态只看条数，当场就能定（种子阶段不设：种子为空不代表没有好友，可能只是没缓存过）。
    self.tableView.tableFooterView = accepted.count > 0 ? nil : self.emptyFooter;
    [self layoutEmptyFooter];
    [self rebuildFriendIndexWithReason:@"server"];
}

#pragma mark - 交互

/// 点好友行 → 进对方资料页（IMChatDetailViewController），再由资料页「消息」发起聊天。
/// 全端统一：点成员/好友一律先进资料页，不直接进聊天页（微信式）。见 [[improgram-tap-member-opens-detail]]。
- (void)openPeerDetail:(IMUserCard *)card {
    if (card.userID.length == 0 || [card.userID isEqualToString:self.userID]) { return; }
    IMChatDetailViewController *detail =
        [[IMChatDetailViewController alloc] initSingleWithHost:self.host userID:self.userID
                                                        peerID:card.userID
                                                  peerNickname:card.nickname // 真实昵称；备注由 IMRemarkStore 供给
                                                 peerAvatarURL:card.avatarURL];
    detail.showsMessagePill = YES; // 通讯录进资料页：提供「消息」入口发起单聊
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)showError:(NSString *)message {
    IMLog(@"%@", message);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:IMLocalized(@"common.notice") message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.ok") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 好友关系写操作的统一收尾：失败弹原因；成功广播「本机改了好友关系」（监听方立即重拉，本页也是其一）。
- (void)finishRelationChangeWithError:(nullable NSError *)error failureKey:(NSString *)failureKey {
    if (error) {
        [self showError:IMLocalizedFormat(failureKey, error.localizedDescription ?: @"")];
        return;
    }
    IMPostFriendRelationDidChangeLocally();
}

/// 对某好友执行拉黑 / 解除拉黑。
- (void)performAction:(NSString *)action onPeer:(NSString *)peerID {
    if (self.token.length == 0 || peerID.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService friendActionWithToken:self.token action:action peerID:peerID completion:^(NSError *error) {
        [weakSelf finishRelationChangeWithError:error failureKey:@"common.action_failed_detail"];
    }];
}

/// 删除好友（DELETE）。
- (void)removeFriend:(NSString *)peerID {
    if (self.token.length == 0 || peerID.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService removeFriendWithToken:self.token peerID:peerID completion:^(NSError *error) {
        [weakSelf finishRelationChangeWithError:error failureKey:@"common.delete_failed_detail"];
    }];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self.friendIndex numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.friendIndex numberOfRowsInSection:section];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self.friendIndex titleForSection:section]; // 字母表头（索引 head）
}

/// 右侧纵向索引尺：列出好友字母（A–Z / #），点击跳到对应分组；无好友则不显示。
- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return self.friendIndex.titles.count > 0 ? self.friendIndex.titles : nil;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return index; // titles 与分组一一对应
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:kIMFriendListCellID forIndexPath:indexPath];
    IMUserCard *card = [self.friendIndex cardAtSection:indexPath.section row:indexPath.row];
    // 拉黑≠解绑：被拉黑的好友仍在列表，副标题标注"已拉黑"以区分。
    // 副标题 = @句柄（没有则留空），绝不显示 userID——那是 10 位随机数字内部 ID。
    NSString *handle = card.username.length > 0 ? [@"@" stringByAppendingString:card.username] : @"";
    NSString *subtitle = handle;
    if (card.blocked) {
        subtitle = handle.length > 0 ? IMLocalizedFormat(@"contacts.row.handle_blocked", handle) : IMLocalized(@"common.blocked");
    }
    [cell configureWithCard:card subtitle:subtitle];
    [cell setActionTitle:nil enabled:NO action:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IMUserCard *card = [self.friendIndex cardAtSection:indexPath.section row:indexPath.row];
    if (card) { [self openPeerDetail:card]; }
}

/// 好友行左滑：删除好友 / 拉黑或解除拉黑。
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMUserCard *card = [self.friendIndex cardAtSection:indexPath.section row:indexPath.row];
    if (!card) { return nil; }
    NSString *peer = card.userID;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:IMLocalized(@"common.delete")
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [weakSelf removeFriend:peer]; done(YES);
    }];
    // 拉黑≠解绑：已拉黑的好友这里给"解除拉黑"，否则给"拉黑"。
    NSString *blockTitle = card.blocked ? IMLocalized(@"contacts.action.unblock") : IMLocalized(@"contacts.action.block");
    NSString *blockAction = card.blocked ? @"unblock" : @"block";
    UIContextualAction *block = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                        title:blockTitle
                                                                      handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [weakSelf performAction:blockAction onPeer:peer]; done(YES);
    }];
    block.backgroundColor = card.blocked ? UIColor.systemGreenColor : UIColor.systemGrayColor;
    return [UISwipeActionsConfiguration configurationWithActions:@[del, block]];
}

@end
