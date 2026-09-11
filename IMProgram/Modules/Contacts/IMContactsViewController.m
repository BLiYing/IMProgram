//  IMContactsViewController.m

#import "IMContactsViewController.h"
#import "IMUserSearchViewController.h"
#import "IMGroupListViewController.h"
#import "IMFriendRequestListViewController.h"
#import "IMContactCells.h"
#import "IMContactSectionIndex.h"
#import "IMChatDetailViewController.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMReconnectReloader.h"
#import "IMUserCard.h"
#import "IMRemarkStore.h"
#import "IMDatabase.h"
#import "IMDatabase+RosterCache.h"
#import "IMMenuAction.h"
#import "IMAnimator.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMLog.h"
#import "IMAccountIdentity.h"

#pragma mark - 顶部入口 Cell（彩色图标 + 标题 + chevron）

@interface IMContactEntryCell : UITableViewCell
/// badge：右侧计数（如「新的朋友」的待确认数）。nil/空串 = 不显示。
- (void)configureWithAction:(IMMenuAction *)action iconBg:(UIColor *)iconBg badge:(nullable NSString *)badge;
@end

@implementation IMContactEntryCell {
    UIImageView *_iconView;
    UIView *_iconBg;
    UILabel *_title;
    UILabel *_badge;   // 右侧红点计数（贴在 disclosure 箭头左侧）
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _iconBg = [UIView new];
        _iconBg.translatesAutoresizingMaskIntoConstraints = NO;
        _iconBg.layer.cornerRadius = 7;
        _iconBg.layer.masksToBounds = YES;
        [self.contentView addSubview:_iconBg];

        _iconView = [UIImageView new];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.tintColor = UIColor.whiteColor;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconBg addSubview:_iconView];

        _title = [UILabel new];
        _title.translatesAutoresizingMaskIntoConstraints = NO;
        _title.font = [UIFont systemFontOfSize:17];
        _title.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_title];

        _badge = [UILabel new];
        _badge.translatesAutoresizingMaskIntoConstraints = NO;
        _badge.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _badge.textColor = UIColor.whiteColor;
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.backgroundColor = UIColor.systemRedColor;
        _badge.layer.cornerRadius = 9;
        _badge.layer.masksToBounds = YES;
        _badge.hidden = YES;
        // 抗压缩：两位数不该被标题挤成省略号。
        [_badge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_badge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_badge];

        [NSLayoutConstraint activateConstraints:@[
            [_iconBg.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [_iconBg.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconBg.widthAnchor constraintEqualToConstant:30],
            [_iconBg.heightAnchor constraintEqualToConstant:30],
            [_iconView.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:18],
            [_iconView.heightAnchor constraintEqualToConstant:18],
            [_title.leadingAnchor constraintEqualToAnchor:_iconBg.trailingAnchor constant:IMTheme.space3],
            [_title.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_title.trailingAnchor constraintLessThanOrEqualToAnchor:_badge.leadingAnchor constant:-8],
            [_badge.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [_badge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_badge.heightAnchor constraintEqualToConstant:18],
            [_badge.widthAnchor constraintGreaterThanOrEqualToAnchor:_badge.heightAnchor],
        ]];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}
- (void)configureWithAction:(IMMenuAction *)action iconBg:(UIColor *)iconBg badge:(NSString *)badge {
    _title.text = action.title;
    _iconView.image = action.systemImageName.length > 0 ? [UIImage systemImageNamed:action.systemImageName] : nil;
    _iconBg.backgroundColor = iconBg;
    // 两侧各留 5pt：一位数是圆点，两位数自然拉成胶囊。
    _badge.text = badge.length > 0 ? [NSString stringWithFormat:@"  %@  ", badge] : nil;
    _badge.hidden = (badge.length == 0);
}
@end

@interface IMContactsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) NSArray<IMUserCard *> *pending;   // 对方申请我，待我同意/拒绝
@property (nonatomic, strong) NSArray<IMUserCard *> *accepted;  // 已是好友（原始集合；分组展示走 friendIndex）
@property (nonatomic, strong) IMContactSectionIndex *friendIndex; // 好友 A–Z 分组索引（右侧纵向索引尺 + 字母表头）
@property (nonatomic, strong) NSArray<IMMenuAction *> *entries; // 顶部入口（群聊/公众号/服务号）
@property (nonatomic, strong) NSArray<UIColor *> *entryColors;  // 与 entries 同序的图标底色
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIView *emptyFooter;  // 承载 emptyLabel 的表尾容器（见 layoutEmptyFooter）
@property (nonatomic, strong, nullable) IMDatabaseAccountContext *databaseContext; // 任务5：本地缓存账号隔离
@property (nonatomic, strong) IMReconnectReloader *reconnectReloader;              // 重连即取权威（可见时）
@property (nonatomic, assign) NSUInteger indexGeneration;   // 最近一次发起的索引构建代号；回来的不是这一代就丢弃
@property (nonatomic, assign) CFTimeInterval lastRefreshAt; // 最近一次拉到权威好友列表的时刻（CACurrentMediaTime，0=从未）
@property (nonatomic, assign) BOOL refreshInFlight;         // 好友列表请求在途（切入节流用）
@property (nonatomic, copy) NSDictionary<NSString *, NSArray *> *cachedFriendsFingerprint; // 本地好友快照的内容指纹（见 persistFriendsIfChanged:）
@end

/// 切入通讯录的刷新节流间隔：来回切 Tab 不必每次都拉 2000 人的名单，变化靠好友事件与重连兜住。
static const CFTimeInterval kIMContactsAppearRefreshInterval = 30;

/// 好友快照整表重写的串行队列：按发起顺序落库，后拉到的名单不会被先拉到的那份覆盖。
static dispatch_queue_t IMContactsCacheWriteQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("im.contacts.cache", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

BOOL IMContactsShouldRefreshOnAppear(BOOL inFlight, CFTimeInterval lastRefreshAt,
                                     CFTimeInterval now, CFTimeInterval interval) {
    if (inFlight) { return NO; }
    if (lastRefreshAt <= 0 || now < lastRefreshAt) { return YES; }
    return now - lastRefreshAt >= interval;
}

@implementation IMContactsViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        // 任务5：本地缓存优先——先用上次落库的好友种子渲染，断网也能看到列表，联网成功再权威覆盖。
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        __block NSArray<IMUserCard *> *cachedFriends = @[];
        [IMDatabase.sharedDatabase performWithAccountContext:_databaseContext block:^(IMDatabase *database) {
            cachedFriends = database.cachedFriends;
        }];
        // 快照指纹：之后拉回来的名单跟它一样就不必整表重写（冷启动后的第一次刷新通常就是这种情况）。
        _cachedFriendsFingerprint = IMCachedFriendsFingerprint(cachedFriends);
        _pending = @[];              // 待处理申请不落库（易变，以服务端为准），联网后由 applyFriends 补上
        _accepted = cachedFriends;   // 好友种子（离线首屏）
        // 种子也分组，离线首屏即带索引。后台算：本页随 TabBar 在启动时就创建，2000 人同步分组会拖慢冷启动。
        _friendIndex = [[IMContactSectionIndex alloc] initWithCards:@[]];
        [self rebuildFriendIndexWithReason:@"seed"];
        [self buildEntries];
        // 实时好友事件：即使没在通讯录页，也据此刷新（Tab 角标随之亮/灭，无需切页）。
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onFriendEvent)
                                                   name:IMSocketDidReceiveFriendEventNotification object:nil];
        // 备注名变更（本机详情页改 / 其它设备改）：显示名与首字母分组都会变，就地重排即可，
        // 不必回服务端——displayName 读的是 IMRemarkStore，本地数据已是最新。
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onRemarkChanged)
                                                   name:IMRemarkStoreDidChangeNotification object:nil];
        // 重连即取权威资料（断网期间看的是缓存种子）。仅可见时刷新，避免离屏空跑登录+HTTP。
        __weak typeof(self) ws = self;
        _reconnectReloader = [[IMReconnectReloader alloc] initWithReloadBlock:^{ [ws reload]; }];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

/// 顶部入口（数据驱动）：新增入口 = 往 entries/entryColors 各加一条。全部 → 开发中吐司。
- (void)buildEntries {
    __weak typeof(self) ws = self;
    self.entries = @[
        [IMMenuAction actionWithId:@"groupChat" title:@"群聊" image:@"person.3.fill" handler:^{ [ws openGroupList]; }],
        // 「新的朋友」独立入口（2026-09-05）：原先它是好友列表上方的一段，好友一多就被挤到看不见，
        // 而"有人加我"恰恰是需要主动去处理的事。副标题显待确认数（0 时留空，别摆一个恒亮的 0）。
        [IMMenuAction actionWithId:@"friendRequests" title:@"新的朋友" image:@"person.crop.circle.badge.plus"
                           handler:^{ [ws openFriendRequests]; }],
        [IMMenuAction actionWithId:@"officialAccount" title:@"公众号" image:@"megaphone.fill" handler:^{ [ws im_showComingSoon:@"公众号"]; }],
        [IMMenuAction actionWithId:@"serviceAccount" title:@"服务号" image:@"headphones" handler:^{ [ws im_showComingSoon:@"服务号"]; }],
    ];
    self.entryColors = @[UIColor.systemGreenColor, UIColor.systemTealColor, UIColor.systemOrangeColor, UIColor.systemBlueColor];
}

/// 收到好友事件 → 节流刷新（合并连发，避免每帧一次登录+拉取）。
/// 备注名变更 → 按新显示名重排分桶并刷新（纯本地，零请求）。
- (void)onRemarkChanged {
    [self rebuildFriendIndexWithReason:@"remark"];
}

- (void)onFriendEvent {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
    [self performSelector:@selector(reload) withObject:nil afterDelay:0.3];
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
    [self.tableView registerClass:IMContactEntryCell.class forCellReuseIdentifier:@"entry"];
    [self.view addSubview:self.tableView];

    // 空态文案挂 tableView 的**表尾**，不再居中盖在 self.view 上：顶部入口区是 4 行 68pt 的
    // 分组表，屏幕竖直中心恰好落在最后一条入口（服务号）身上，两段文字直接叠在一起（2026-09-05 实测）。
    // 表尾天然接在最后一段内容下方，以后入口再增减也撞不上。
    self.emptyLabel = [UILabel new];
    self.emptyLabel.text = @"还没有好友，点右上角 + 搜索用户添加";
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
    // 切入即取权威好友列表（带节流）。**不能只靠重连 / 好友事件**：socket 多半在停留「会话」页时就连上了，
    // 那一刻本页不可见、重连刷新不触发；好友缓存又只有本页写，2026-09-06 删掉这句后通讯录整页空白。
    // 当时的切 Tab 卡顿不是这次请求（异步、token 有缓存），而是回来后在主线程重建 2000 人拼音索引——
    // 已改为后台构建 + 拼音缓存（见 rebuildFriendIndexWithReason:）。
    if (IMContactsShouldRefreshOnAppear(self.refreshInFlight, self.lastRefreshAt,
                                        CACurrentMediaTime(), kIMContactsAppearRefreshInterval)) {
        [self reload];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.reconnectReloader.visible = NO;
}

#pragma mark - 数据

- (void)reload {
    IMHTTPService.sharedService.host = self.host;
    self.refreshInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            self.refreshInFlight = NO;
            IMLog(@"通讯录刷新登录失败（保留当前内容）：%@", error.localizedDescription ?: @"未知错误");
            return;
        }
        self.token = token;
        [IMHTTPService.sharedService friendsWithToken:token status:nil completion:^(NSArray<IMUserCard *> *friends, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            self.refreshInFlight = NO;
            if (err) {
                IMLog(@"通讯录刷新失败（保留当前内容）：%@", err.localizedDescription ?: @"未知错误");
                return;
            }
            [self applyFriends:friends ?: @[]];
        }];
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

/// 任务5：权威好友列表落库（仅 accepted），供下次断网离线首屏。空名单也写，代表当前账号无好友。
/// 与上次落库（或冷启动读出的快照）逐列一致就不写——2000 人删了重插在 Mac 上约 16ms，而切 Tab 拉回来的名单
/// 几乎总是没变。变了才写，并挪到后台串行队列：FMDatabaseQueue 线程安全；卡片解析后不再被改写；
/// performWithAccountContext 会丢弃账号已切走的写入。锁序与主线程一致（IMDatabase 锁 → FMDB 队列），不会反向等待。
/// **指纹只在真的写成后才记**：写失败整笔回滚、库里仍是上一份，保留旧指纹下次刷新就会重试
/// （原先每次无条件重写，天然带重试；「没变不写」不能把这一点弄丢）。串行队列 + 主队列 FIFO，
/// 指纹始终等于最后一次写成的那份。
- (void)persistFriendsIfChanged:(NSArray<IMUserCard *> *)accepted {
    NSDictionary<NSString *, NSArray *> *fingerprint = IMCachedFriendsFingerprint(accepted);
    BOOL changed = ![fingerprint isEqualToDictionary:self.cachedFriendsFingerprint ?: @{}];
    IMLogUI(@"contacts_cache_persist changed=%d friends=%lu", changed, (unsigned long)accepted.count);
    if (!changed) { return; }
    IMDatabaseAccountContext *context = self.databaseContext;
    NSArray<IMUserCard *> *snapshot = [accepted copy];
    __weak typeof(self) weakSelf = self;
    dispatch_async(IMContactsCacheWriteQueue(), ^{
        __block BOOL written = NO;
        [IMDatabase.sharedDatabase performWithAccountContext:context block:^(IMDatabase *database) {
            written = [database replaceCachedFriends:snapshot];
        }];
        if (!written) { return; }
        dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.cachedFriendsFingerprint = fingerprint; });
    });
}

/// 拆分为"新的朋友"(pending) 与 好友(accepted)；好友按拼音首字母分组（A–Z + 右侧索引尺，见 friendIndex）。
- (void)applyFriends:(NSArray<IMUserCard *> *)friends {
    NSMutableArray<IMUserCard *> *pending = [NSMutableArray array];
    NSMutableArray<IMUserCard *> *accepted = [NSMutableArray array];
    for (IMUserCard *c in friends) {
        if (c.status == IMFriendStatusPending) { [pending addObject:c]; }
        else if (c.status == IMFriendStatusAccepted) { [accepted addObject:c]; }
    }
    self.pending = pending;
    self.accepted = accepted;
    self.lastRefreshAt = CACurrentMediaTime();
    // 表尾空态只看条数，当场就能定（种子阶段不设：种子为空不代表没有好友，可能只是没缓存过）。
    self.tableView.tableFooterView = (pending.count + accepted.count) > 0 ? nil : self.emptyFooter;
    [self layoutEmptyFooter];
    // 好友行与「新的朋友」徽标随新索引回来的那次 reloadData 一起刷，省一次整表重载。
    [self rebuildFriendIndexWithReason:@"server"];
    [self persistFriendsIfChanged:accepted];
    // Tab 角标：把待处理申请数显示在"通讯录"Tab 上（清零靠重新进入时再算）。
    NSString *badge = pending.count > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)pending.count] : nil;
    if (@available(iOS 18.0, *)) { self.navigationController.tab.badgeValue = badge; }
    else { self.navigationController.tabBarItem.badgeValue = badge; }
}

#pragma mark - 交互

- (void)openGroupList {
    IMGroupListViewController *list = [[IMGroupListViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)openFriendRequests {
    IMFriendRequestListViewController *vc =
        [[IMFriendRequestListViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:vc animated:YES];
}

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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 分区映射

// 分区布局：section 0 = 顶部入口（始终存在）；其后接 N 个「好友 A–Z 字母分组」（由 friendIndex 提供）。
// 下面以语义谓词判断，避免散落魔法下标。
//
// **「新的朋友」分区已于 2026-09-05 移除**：改由顶部入口行「新的朋友」→ IMFriendRequestListViewController。
// 两处并存只会让人在列表里找一次、在入口里再找一次；而好友一多，原来那一段就被冲到看不见了。
// self.pending 仍然要算——入口行的红点徽标与 Tab 角标都靠它。

/// 顶部入口区永远是 section 0。
- (BOOL)isEntriesSection:(NSInteger)section { return section == 0; }
/// 好友字母分组的起始 section（顶部入口之后）。
- (NSInteger)friendsBaseSection { return 1; }
/// 该 section 是否属于好友字母分组区。
- (BOOL)isFriendSection:(NSInteger)section { return section >= [self friendsBaseSection]; }
/// section → friendIndex 内的分组下标。
- (NSInteger)friendLocalSection:(NSInteger)section { return section - [self friendsBaseSection]; }

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self friendsBaseSection] + [self.friendIndex numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isEntriesSection:section]) { return (NSInteger)self.entries.count; }
    return [self.friendIndex numberOfRowsInSection:[self friendLocalSection:section]];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self isEntriesSection:section]) { return nil; }
    return [self.friendIndex titleForSection:[self friendLocalSection:section]]; // 字母表头（索引 head）
}

/// 右侧纵向索引尺：列出好友字母（A–Z / #），点击跳到对应分组；无好友则不显示。
- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return self.friendIndex.titles.count > 0 ? self.friendIndex.titles : nil;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return [self friendsBaseSection] + index; // titles 与好友分组一一对应，加偏移即绝对 section
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isEntriesSection:indexPath.section]) {
        IMContactEntryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"entry" forIndexPath:indexPath];
        IMMenuAction *entry = self.entries[indexPath.row];
        // 「新的朋友」带待确认数徽标；其余入口无徽标。
        NSString *badge = ([entry.actionId isEqualToString:@"friendRequests"] && self.pending.count > 0)
            ? [NSString stringWithFormat:@"%lu", (unsigned long)self.pending.count] : nil;
        [cell configureWithAction:entry iconBg:self.entryColors[indexPath.row] badge:badge];
        return cell;
    }
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:@"friend" forIndexPath:indexPath];
    IMUserCard *c = [self.friendIndex cardAtSection:[self friendLocalSection:indexPath.section] row:indexPath.row];
    // 拉黑≠解绑：被拉黑的好友仍在列表，副标题标注"已拉黑"以区分。
    // 副标题 = @句柄（没有则留空），绝不显示 userID——那是 10 位随机数字内部 ID。
    NSString *handle = c.username.length > 0 ? [@"@" stringByAppendingString:c.username] : @"";
    NSString *subtitle = c.blocked ? (handle.length > 0 ? [handle stringByAppendingString:@" · 已拉黑"] : @"已拉黑") : handle;
    [cell configureWithCard:c subtitle:subtitle];
    [cell setActionTitle:nil enabled:NO action:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isEntriesSection:indexPath.section]) {
        [IMAnimator selectionChanged];
        IMMenuAction *entry = self.entries[indexPath.row];
        if (entry.handler) { entry.handler(); }
        return;
    }
    IMUserCard *c = [self.friendIndex cardAtSection:[self friendLocalSection:indexPath.section] row:indexPath.row];
    if (c) { [self openPeerDetail:c]; }
}

/// 好友行左滑：删除好友 / 拉黑或解除拉黑（入口行/申请行不提供）。
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self isFriendSection:indexPath.section]) { return nil; }
    IMUserCard *card = [self.friendIndex cardAtSection:[self friendLocalSection:indexPath.section] row:indexPath.row];
    if (!card) { return nil; }
    NSString *peer = card.userID;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:@"删除"
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [weakSelf removeFriend:peer]; done(YES);
    }];
    // 拉黑≠解绑：已拉黑的好友这里给"解除拉黑"，否则给"拉黑"。
    NSString *blockTitle = card.blocked ? @"解除拉黑" : @"拉黑";
    NSString *blockAction = card.blocked ? @"unblock" : @"block";
    UIContextualAction *block = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                        title:blockTitle
                                                                      handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [weakSelf performAction:blockAction onPeer:peer]; done(YES);
    }];
    block.backgroundColor = card.blocked ? UIColor.systemGreenColor : UIColor.systemGrayColor;
    return [UISwipeActionsConfiguration configurationWithActions:@[del, block]];
}

/// 删除好友（DELETE）；完成后刷新列表。
- (void)removeFriend:(NSString *)peerID {
    if (self.token.length == 0 || peerID.length == 0) { return; }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService removeFriendWithToken:self.token peerID:peerID completion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) {
            [self showError:[NSString stringWithFormat:@"删除失败：%@", error.localizedDescription]];
            return;
        }
        [self reload];
    }];
}

@end
