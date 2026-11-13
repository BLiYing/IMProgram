//  IMContactsViewController.m

#import "IMContactsViewController.h"
#import "IMLocalization.h"
#import "IMUserSearchViewController.h"
#import "IMGlobalSearchViewController.h"
#import "IMSearchEntryHeader.h"
#import "IMGroupListViewController.h"
#import "IMFriendRequestListViewController.h"
#import "IMFriendListViewController.h"
#import "IMFriendCacheWriter.h"
#import "IMFriendRoster.h"
#import "IMRecentContacts.h"
#import "IMContactCells.h"
#import "IMChatViewController.h"
#import "IMConversationListViewController.h" // IMCachedConversationListSeed（「最近联系」兜底种子）
#import "IMConversation.h"
#import "IMSocketManager.h"
#import "IMReconnectReloader.h"
#import "IMUserCard.h"
#import "IMRemarkStore.h"
#import "IMDatabase.h"
#import "IMMediaUtil.h"
#import "IMMenuAction.h"
#import "IMAnimator.h"
#import "IMTheme.h"

/// 入口行右值（如「我的好友」的好友数）：最宽 150、尾部截断，与标题至少隔 8。
static const CGFloat kIMContactEntryValueMaxWidth = 150;
static const CGFloat kIMContactEntryValueFontSize = 15;

#pragma mark - 顶部入口 Cell（彩色图标 + 标题 + 右值 / 角标 + chevron）

@interface IMContactEntryCell : UITableViewCell
/// badge：右侧蓝色计数胶囊（如「新的朋友」的待确认数）；value：右侧灰色文字值（如「我的好友」的好友数）。
/// 两者都是 nil/空串 = 不显示；同一行只用其一。
- (void)configureWithAction:(IMMenuAction *)action iconBg:(UIColor *)iconBg
                      badge:(nullable NSString *)badge value:(nullable NSString *)value;
@end

@implementation IMContactEntryCell {
    UIImageView *_iconView;
    UIView *_iconBg;
    UILabel *_title;
    UILabel *_badge;   // 右侧计数胶囊（贴在 disclosure 箭头左侧）
    UILabel *_value;   // 右侧文字值（同样贴在 disclosure 箭头左侧）
    NSLayoutConstraint *_badgeWidth;
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
        // 角标三端统一蓝色（2026-09-15 用户要求），与会话列表未读胶囊同一个色值。
        _badge.backgroundColor = IMTheme.unreadBadge;
        _badge.layer.cornerRadius = 9;
        _badge.layer.masksToBounds = YES;
        _badge.hidden = YES;
        [self.contentView addSubview:_badge];
        _value = [UILabel new];
        _value.translatesAutoresizingMaskIntoConstraints = NO;
        _value.font = [UIFont systemFontOfSize:kIMContactEntryValueFontSize];
        _value.textColor = IMTheme.textSecondary;
        _value.textAlignment = NSTextAlignmentRight;
        _value.lineBreakMode = NSLineBreakByTruncatingTail;
        _value.hidden = YES;
        [self.contentView addSubview:_value];
        // 标题与右值抢宽度时先保右值（它最宽也就 150），标题自己截断。
        [_value setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        // 宽度显式给（与会话列表 _badgeWidth 同一做法），**不靠文本首尾空格撑宽**：
        // UILabel 居中对齐时不计行尾空白，「  3  」只算了前面两个空格，数字整体偏右（2026-09-15 用户报）。
        _badgeWidth = [_badge.widthAnchor constraintEqualToConstant:18];

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
            _badgeWidth,
            [_value.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [_value.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_value.widthAnchor constraintLessThanOrEqualToConstant:kIMContactEntryValueMaxWidth],
            [_title.trailingAnchor constraintLessThanOrEqualToAnchor:_value.leadingAnchor constant:-IMTheme.space2],
        ]];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}
- (void)configureWithAction:(IMMenuAction *)action iconBg:(UIColor *)iconBg badge:(NSString *)badge value:(NSString *)value {
    _title.text = action.title;
    _iconView.image = action.systemImageName.length > 0 ? [UIImage systemImageNamed:action.systemImageName] : nil;
    _iconBg.backgroundColor = iconBg;
    _badge.text = badge.length > 0 ? badge : nil;
    _badge.hidden = (badge.length == 0);
    // 两侧各留 5pt、最小 18：一位数是正圆，两位数自然拉成胶囊。
    _badgeWidth.constant = badge.length > 0
        ? MAX(18, ceil([_badge sizeThatFits:CGSizeMake(CGFLOAT_MAX, 18)].width) + 10) : 0;
    _value.text = value.length > 0 ? value : nil;
    _value.hidden = (value.length == 0);
}
@end

@interface IMContactsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) NSArray<IMUserCard *> *pending;   // 对方申请我，待我同意/拒绝（入口行徽标 + Tab 角标）
@property (nonatomic, strong) NSArray<IMUserCard *> *accepted;  // 已是好友（「我的好友」入口行右值 = 条数；列表在 IMFriendListViewController）
@property (nonatomic, strong) NSArray<IMMenuAction *> *entries; // 顶部入口（群聊 / 新的朋友 / 我的好友）
@property (nonatomic, strong) NSArray<UIColor *> *entryColors;  // 与 entries 同序的图标底色
/// 会话列表页最近一次广播的内存会话数组；nil = 还没收到过（首次计算时用本地会话快照打底，见 refreshRecentContacts）。
@property (nonatomic, copy, nullable) NSArray<IMConversation *> *conversations;
/// 「最近联系」的输入（会话数组 / 备注 / 注销登记）变了、还没重算。不可见时只置脏，可见时才算（见 markRecentContactsDirty）。
@property (nonatomic, assign) BOOL recentDirty;
/// 本页在屏（viewWillAppear → viewDidDisappear 之间）。
@property (nonatomic, assign) BOOL pageVisible;
@property (nonatomic, copy) NSArray<IMConversation *> *recentContacts;   // 「最近联系」（IMRecentContacts 的结果，至多 5 个）
@property (nonatomic, copy) NSArray<NSString *> *recentRenderSignature; // 上屏内容签名：没变就不 reloadData
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong, nullable) IMDatabaseAccountContext *databaseContext; // 任务5：本地缓存账号隔离
@property (nonatomic, strong) IMReconnectReloader *reconnectReloader;              // 重连即取权威（可见时）
@property (nonatomic, assign) CFTimeInterval lastRefreshAt; // 最近一次拉到权威好友列表的时刻（CACurrentMediaTime，0=从未）
@property (nonatomic, assign) BOOL refreshInFlight;         // 好友列表请求在途（切入节流用）
@property (nonatomic, assign) BOOL eventReloadScheduled;    // 好友事件的合并刷新已排队
@end

/// 切入通讯录的刷新节流间隔：来回切 Tab 不必每次都拉 2000 人的名单，变化靠好友事件与重连兜住。
static const CFTimeInterval kIMContactsAppearRefreshInterval = 30;
/// 好友事件连发的合并窗口。
static const NSTimeInterval kIMContactsEventCoalesceDelay = 0.3;

static NSString * const kIMContactsEntryCellID = @"entry";
static NSString * const kIMContactsRecentCellID = @"recent";
static NSString * const kIMContactsEntryFriendRequests = @"friendRequests";
static NSString * const kIMContactsEntryMyFriends = @"myFriends";

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
        // 任务5：本地缓存优先——先用上次落库的好友种子算好友数，断网也有数，联网成功再权威覆盖。
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        _pending = @[];              // 待处理申请不落库（易变，以服务端为准），联网后由 applyRoster: 补上
        _accepted = [IMFriendCacheWriter cachedFriendsWithContext:_databaseContext]; // 好友种子（离线首屏）
        _recentContacts = @[];
        _recentRenderSignature = @[];
        _recentDirty = YES; // 首次显示时算一次
        [self buildEntries];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        // 实时好友事件：即使没在通讯录页，也据此刷新（Tab 角标随之亮/灭，无需切页）。
        [center addObserver:self selector:@selector(onFriendEvent)
                       name:IMSocketDidReceiveFriendEventNotification object:nil];
        // 本机主动改好友关系（同意/拒绝/拉黑/删好友）：服务端不回推本机，立即重拉（绕过切入节流）。
        [center addObserver:self selector:@selector(onLocalFriendRelationChanged)
                       name:IMFriendRelationDidChangeLocallyNotification object:nil];
        // 备注名 / 已注销标记变更：「最近联系」的显示名与去留都可能变，重算（纯本地，零请求；不可见时只置脏）。
        [center addObserver:self selector:@selector(markRecentContactsDirty)
                       name:IMRemarkStoreDidChangeNotification object:nil];
        // 会话列表变了（收发消息、删会话）→ 「最近联系」跟着变。本页随 TabBar 在启动时就创建，
        // 所以即使用户还没切到通讯录，这里也一直握着最新的那份数组（只存不算，见 onConversationListChanged:）。
        [center addObserver:self selector:@selector(onConversationListChanged:)
                       name:IMConversationListDidChangeNotification object:nil];
        // 重连即取权威资料（断网期间看的是缓存种子）。仅可见时刷新，避免离屏空跑登录+HTTP。
        __weak typeof(self) ws = self;
        _reconnectReloader = [[IMReconnectReloader alloc] initWithReloadBlock:^{ [ws reload]; }];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

/// 顶部入口（数据驱动）：新增入口 = 往 entries/entryColors 各加一条。
- (void)buildEntries {
    __weak typeof(self) ws = self;
    self.entries = @[
        [IMMenuAction actionWithId:@"groupChat" title:IMLocalized(@"common.group_chat") image:@"person.3.fill" handler:^{ [ws openGroupList]; }],
        // 「新的朋友」独立入口（2026-09-05）：原先它是好友列表上方的一段，好友一多就被挤到看不见，
        // 而"有人加我"恰恰是需要主动去处理的事。副标题显待确认数（0 时留空，别摆一个恒亮的 0）。
        [IMMenuAction actionWithId:kIMContactsEntryFriendRequests title:IMLocalized(@"friend.requests.title") image:@"person.crop.circle.badge.plus"
                           handler:^{ [ws openFriendRequests]; }],
        // 「我的好友」（2026-11-13）：好友 A–Z 列表整体搬进 IMFriendListViewController，这里只留入口，右值 = 好友数。
        [IMMenuAction actionWithId:kIMContactsEntryMyFriends title:IMLocalized(@"contacts.entry.my_friends") image:@"person.2.fill"
                           handler:^{ [ws openFriendList]; }],
        // 公众号 / 服务号入口暂时隐藏（2026-11-03，功能未做，三端同步）。恢复时连同 entryColors 一起加回；
        // 文案 key contacts.entry.official_account / service_account 仍保留。
    ];
    self.entryColors = @[UIColor.systemGreenColor, UIColor.systemTealColor, UIColor.systemBlueColor];
}

- (void)onLocalFriendRelationChanged {
    [self reload];
}

/// 收到好友事件 → 合并连发后刷新一次（在途标记 + dispatch_after + weak self，见 CODING_STYLE §8），
/// 避免每帧一次登录+拉取。
- (void)onFriendEvent {
    if (self.eventReloadScheduled) { return; }
    self.eventReloadScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kIMContactsEventCoalesceDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        self.eventReloadScheduled = NO;
        [self reload];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"contacts.title");
    self.view.backgroundColor = IMTheme.groupedBackground;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"person.badge.plus"]
                                         style:UIBarButtonItemStylePlain target:self action:@selector(addFriendTapped)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 68;
    [self.tableView registerClass:IMContactCell.class forCellReuseIdentifier:kIMContactsRecentCellID];
    [self.tableView registerClass:IMContactEntryCell.class forCellReuseIdentifier:kIMContactsEntryCellID];
    // 页顶点按式搜索框（SEARCH_DESIGN §3.1）：只是入口，点击 push 全局搜索页、范围=联系人+群聊。
    self.tableView.tableHeaderView = IMMakeSearchEntryHeader(self.view.bounds.size.width, IMLocalized(@"search.contacts.placeholder"),
                                                             self, @selector(searchEntryTapped));
    [self.view addSubview:self.tableView];
    // 「最近联系」在 viewWillAppear 才算（refreshRecentContactsIfNeeded）：没显示过就不必算。
}

- (void)searchEntryTapped {
    IMGlobalSearchViewController *vc = [[IMGlobalSearchViewController alloc] initWithHost:self.host userID:self.userID];
    vc.scope = IMSearchScopeContacts;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.reconnectReloader.visible = YES;
    self.pageVisible = YES;
    [self refreshRecentContactsIfNeeded];
    // 切入即取权威好友列表（带节流）。**不能只靠重连 / 好友事件**：socket 多半在停留「会话」页时就连上了，
    // 那一刻本页不可见、重连刷新不触发；好友缓存靠本页（与「我的好友」页）写，2026-09-06 删掉这句后通讯录整页空白。
    if (IMContactsShouldRefreshOnAppear(self.refreshInFlight, self.lastRefreshAt,
                                        CACurrentMediaTime(), kIMContactsAppearRefreshInterval)) {
        [self reload];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.reconnectReloader.visible = NO;
    self.pageVisible = NO;
}

#pragma mark - 数据：好友数 / 角标

- (void)reload {
    self.refreshInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [IMFriendRoster fetchWithHost:self.host userID:self.userID context:self.databaseContext source:@"通讯录"
                       completion:^(IMFriendRoster *roster, NSString *token) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        self.refreshInFlight = NO;
        if (roster) { [self applyRoster:roster]; } // 失败保留当前内容（helper 已打日志）
    }];
}

/// pending 给入口行徽标 + Tab 角标，accepted 给「我的好友」右值（落库已由 IMFriendRoster 做完）。
- (void)applyRoster:(IMFriendRoster *)roster {
    self.pending = roster.pending;
    self.accepted = roster.accepted;
    self.lastRefreshAt = CACurrentMediaTime();
    // 只刷入口区（徽标 + 好友数）；「最近联系」不随好友名单变。
    if (self.isViewLoaded) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:[self entriesSection]]
                      withRowAnimation:UITableViewRowAnimationNone];
    }
    // Tab 角标：把待处理申请数显示在"通讯录"Tab 上（清零靠重新进入时再算）。
    NSString *badge = roster.pending.count > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)roster.pending.count] : nil;
    if (@available(iOS 18.0, *)) { self.navigationController.tab.badgeValue = badge; }
    else { self.navigationController.tabBarItem.badgeValue = badge; }
}

#pragma mark - 数据：最近联系

- (void)onConversationListChanged:(NSNotification *)note {
    NSString *owner = note.userInfo[kIMConversationListOwnerKey];
    NSArray<IMConversation *> *conversations = note.userInfo[kIMConversationListKey];
    // 换号过渡期旧 TabBar 的会话页还可能广播一次：不是本账号的不收。
    if (![owner isEqualToString:self.userID] || ![conversations isKindOfClass:NSArray.class]) { return; }
    self.conversations = conversations;
    [self markRecentContactsDirty];
}

/// 「最近联系」的输入变了：只置脏；本页在屏才当场重算。会话列表在消息风暴下每 0.12s 就换一次数组，
/// 用户多半停在「消息」Tab，那时每次都排序 + 算签名纯属空转——等切回本页（viewWillAppear）再算一次。
- (void)markRecentContactsDirty {
    self.recentDirty = YES;
    if (self.pageVisible) { [self refreshRecentContactsIfNeeded]; }
}

- (void)refreshRecentContactsIfNeeded {
    if (!self.recentDirty) { return; }
    self.recentDirty = NO;
    [self refreshRecentContacts];
}

/// 按当前会话数组重算「最近联系」；上屏内容（成员 / 顺序 / 显示名 / 头像）没变就不动表格——
/// 在屏时消息一条条进来，无条件 reloadData 会让这一段跟着闪。
- (void)refreshRecentContacts {
    // 会话列表页还没广播过（它的种子在 init 里直接赋 ivar，不走广播）：读同一份本地会话快照打底。
    if (!self.conversations) { self.conversations = IMCachedConversationListSeed(self.databaseContext); }
    NSArray<IMConversation *> *recents = IMRecentContacts(self.conversations, self.userID, ^BOOL(NSString *peerUID) {
        return [IMRemarkStore.sharedStore isDeletedUser:peerUID];
    });
    NSMutableArray<NSString *> *signature = [NSMutableArray arrayWithCapacity:recents.count];
    for (IMConversation *c in recents) {
        [signature addObject:[NSString stringWithFormat:@"%@\n%@\n%@", c.convID, c.displayName, c.peerAvatarURL ?: @""]];
    }
    BOOL changed = ![signature isEqualToArray:self.recentRenderSignature];
    self.recentContacts = recents; // 对象总是换成最新的（点行进聊天要带最新的已读位点 / 未读数 / 标未读）
    self.recentRenderSignature = signature;
    if (changed && self.isViewLoaded) { [self.tableView reloadData]; }
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

- (void)openFriendList {
    // 把手上的好友名单交给好友页当首屏：push 时不必在主线程再读一遍整张好友表。手上没有才让它自己读库。
    IMFriendListViewController *vc = [[IMFriendListViewController alloc] initWithHost:self.host userID:self.userID
                                                                         seedFriends:self.accepted.count > 0 ? self.accepted : nil];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)addFriendTapped {
    IMUserSearchViewController *search = [[IMUserSearchViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:search animated:YES];
}

/// 点「最近联系」行 → **直接进聊天**（设计 §7.1）。这里列的是已经在聊的会话，不是「好友 / 成员」名单，
/// 所以不走「先进资料页」那条规矩；走与会话列表点行同一个共用入口（含清「标为未读」）。
- (void)openRecentChat:(IMConversation *)conversation {
    [IMChatViewController openConversation:conversation inNavigationController:self.navigationController
                                      host:self.host userID:self.userID token:nil];
}

#pragma mark - 分区映射

// 分区布局：section 0 = 顶部入口（始终存在）；section 1 = 「最近联系」（一个都没有时整段不出现）。
// 好友 A–Z 分组已于 2026-11-13 搬到 IMFriendListViewController（入口行「我的好友」）；
// 「新的朋友」分区更早（2026-09-05）就改成了入口行 → IMFriendRequestListViewController。
// self.pending / self.accepted 仍然要算——入口行的徽标、好友数与 Tab 角标都靠它们。

- (NSInteger)entriesSection { return 0; }
- (BOOL)isEntriesSection:(NSInteger)section { return section == [self entriesSection]; }

/// 入口行右侧显示什么：「新的朋友」= 待确认数徽标（0 不显示）；「我的好友」= 好友数（只写数字）。
- (void)configureEntryCell:(IMContactEntryCell *)cell atRow:(NSInteger)row {
    IMMenuAction *entry = self.entries[row];
    NSString *badge = nil;
    NSString *value = nil;
    if ([entry.actionId isEqualToString:kIMContactsEntryFriendRequests] && self.pending.count > 0) {
        badge = [NSString stringWithFormat:@"%lu", (unsigned long)self.pending.count];
    } else if ([entry.actionId isEqualToString:kIMContactsEntryMyFriends]) {
        value = [NSString stringWithFormat:@"%lu", (unsigned long)self.accepted.count];
    }
    [cell configureWithAction:entry iconBg:self.entryColors[row] badge:badge value:value];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.recentContacts.count > 0 ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self isEntriesSection:section] ? (NSInteger)self.entries.count : (NSInteger)self.recentContacts.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self isEntriesSection:section] ? nil : IMLocalized(@"contacts.recent.title");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isEntriesSection:indexPath.section]) {
        IMContactEntryCell *cell = [tableView dequeueReusableCellWithIdentifier:kIMContactsEntryCellID forIndexPath:indexPath];
        [self configureEntryCell:cell atRow:indexPath.row];
        return cell;
    }
    // 最近联系：头像 + 显示名（备注 > 昵称，与会话列表同一口径），不带消息预览和时间。
    IMContactCell *cell = [tableView dequeueReusableCellWithIdentifier:kIMContactsRecentCellID forIndexPath:indexPath];
    IMConversation *conversation = self.recentContacts[indexPath.row];
    [cell configureWithDisplayName:conversation.displayName
                         avatarURL:IMMediaFullURL(conversation.peerAvatarURL, self.host)
                        avatarSeed:conversation.peer subtitle:nil];
    [cell setActionTitle:nil enabled:NO action:nil];
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
    if (indexPath.row < (NSInteger)self.recentContacts.count) { [self openRecentChat:self.recentContacts[indexPath.row]]; }
}

@end
