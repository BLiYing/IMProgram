//  IMChatDetailViewController.m

#import "IMChatDetailViewController.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar / kIMLiquidBarHeight
#import "IMChatDetailTabs.h"
#import "IMLiquidSegmentedControl.h" // 页签用的 Liquid Glass 分段控件
#import "IMGroupManageViewController.h"
#import "IMQRCardViewController.h"
#import "IMQRResultRouter.h" // 层3：本站邀请链接（/q/u、/q/g）App 内拦截走原生流程
#import "IMGroupTextViewController.h"

#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMProtocol.h"
#import "IMDatabase.h"
#import "IMTimeUtil.h" // IMNowMillis()：成员禁言状态判定与时长换算
#import "IMMessageModel.h"
#import "IMConversation.h"
#import "IMGroupInfo.h"
#import "IMUserCard.h"
#import "IMRemarkStore.h"

#import "IMChatViewController.h"
#import "IMFriendPickerViewController.h"
#import "IMConversationMediaViewController.h"
#import "IMMediaViewerViewController.h"
#import "IMMediaPagerViewController.h"
#import "IMMediaTileCell.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaPlaceholder.h" // 磨砂占位统一渲染器（三处共用）
#import "IMMediaUtil.h"
#import "IMMediaDownloadCoordinator.h" // 媒体/文件下载编排（与聊天页共用）
#import "IMDownloadProgress.h"
#import "IMFilePreviewPresenter.h"
#import <SafariServices/SafariServices.h>
#import "IMPopoverCard.h"
#import "IMGlass.h"
#import "UILabel+IMAvatar.h"
#import "UIViewController+IMToast.h"
#import "UIViewController+IMDeleteSheet.h" // 两档删除 sheet（与聊天页共用）
#import "IMTheme.h"
#import "IMLog.h"
#import <objc/runtime.h>
#import "IMDropletHeaderMorph.h"
#import "IMProgram-Swift.h"

#import "IMDetailHeaderViews.h"          // IMDetailAvatarView / IMDetailHeaderContainer
#import "IMDetailMemberCell.h"
#import "IMDetailMediaContainerCell.h"
#import "IMDetailFileCell.h"
#import "IMDetailLinkCell.h"
#import "IMDetailContactCell.h"
#import "IMChatDetailViewController+Private.h" // 私有类扩展（属性/协议/常量/enum）——与分文件 category 共享

#pragma mark - 详情页

// enum IMDetailSection / 私有类扩展已移至 IMChatDetailViewController+Private.h；此处定义那批共享布局常量。
CGFloat const kIMDetailPillsRowH = 78;
CGFloat const kIMDetailTabBarH   = 52;   ///< 页签栏高度（含分段控件上下留白）；分段控件本体 = kIMDetailTabBarH-12
CGFloat const kIMDetailTabSegH   = 40;   ///< 分段控件本体高度（点击面积）
/// 标题栏「变实」上限：头部收拢完成（名字/成员已进标题栏）时的不透明程度。
CGFloat const kIMDetailNavOpaqueOnCollapse = 0.8;

@implementation IMChatDetailViewController

#pragma mark - 生命周期

- (instancetype)initSingleWithHost:(NSString *)host userID:(NSString *)userID peerID:(NSString *)peerID
                      peerNickname:(NSString *)peerNickname peerAvatarURL:(NSString *)peerAvatarURL {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy]; _userID = [userID copy]; _peerID = [peerID copy];
        _peerNickname = [peerNickname copy];
        // 备注名（仅自己可见，替代对端昵称显示）：先用全局缓存的值秒显，loadPeerBlockState 再取权威值校正。
        _peerRemark = [IMRemarkStore.sharedStore remarkForUser:peerID];
        _peerAvatarURL = [peerAvatarURL copy];
        _convID = IMConversationID(userID, peerID);
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        if (![context.ownerUserID isEqualToString:userID]) {
            IMLogDatabase(@"单聊详情页账号与当前数据库上下文不一致 page_uid=%@ db_uid=%@",
                          userID, context.ownerUserID ?: @"(none)");
        }
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        _isGroup = NO;
        // 好友态**先按本地已知关系起步**（IMFriendStateStore：上次 /friends 或本地快照）。
        // 无从判断时才乐观 YES。原来无条件 YES，于是点非好友的名片进来会先闪一遍
        // 「消息/呼叫/视频 + 备注·设置·页签」再变成「加好友」（用户 2026-08-30 报的 bug）。
        _peerIsFriend = [self initialPeerIsFriendGuess:peerID];
        // URL 只决定圆形头像内容，不再触发全幅大图头部。
        _hasPhoto = NO;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (instancetype)initGroupWithHost:(NSString *)host userID:(NSString *)userID convID:(NSString *)convID
                       groupName:(NSString *)groupName groupAvatarURL:(NSString *)groupAvatarURL {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy]; _userID = [userID copy]; _convID = [convID copy];
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        if (![context.ownerUserID isEqualToString:userID]) {
            IMLogDatabase(@"群详情页账号与当前数据库上下文不一致 page_uid=%@ db_uid=%@",
                          userID, context.ownerUserID ?: @"(none)");
        }
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        _groupName = [groupName copy]; _isGroup = YES;
        _peerAvatarURL = [groupAvatarURL copy];   // 复用字段承载群头像，供 headerAvatarURL 立即取用
        _hasPhoto = NO;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation {
    return [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:operation];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.selectedTab = 0;
    [self buildTableView];
    [self buildHeaderOverlay];
    [self rebuildTabs];

    // 初始数据：会话设置（置顶/免打扰）；群→群资料；单聊→拉黑态。
    [self loadConversationSettings];
    if (self.isGroup) {
        [self loadGroupInfo];
        [self loadFriendUIDs]; // 群成员长按菜单据此显「发送消息」(好友) / 「添加好友」(非好友)
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onGroupEvent:)
                                                   name:IMSocketDidReceiveGroupEventNotification object:nil];
    } else {
        [self loadPeerBlockState];
        [self loadPeerProfile]; // 拉权威资料覆盖 init 快照 / 404 → 空态（见 +Peer.m）
        // 备注名多端同步：其它设备改了对这位好友的备注 → 就地刷新标题与「备注名」行。
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onPeerRemarkChanged:)
                                                   name:IMRemarkStoreDidChangeNotification object:nil];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onConvUpdate:)
                                               name:IMSocketDidUpdateConversationNotification object:nil];
    // 任务2：消息被物理移除（为所有人删除 / 仅为我删除）→ 重建页签内容（文件列表随之更新）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMessageRemoved:)
                                               name:IMSocketDidRemoveMessageNotification object:nil];
}

/// 备注名变更：只认本页对端（批量刷新无 peerID 键，一律接受）。值以 IMRemarkStore 为准。
- (void)onPeerRemarkChanged:(NSNotification *)note {
    NSString *peerID = note.userInfo[kIMRemarkPeerIDKey];
    if (peerID.length > 0 && ![peerID isEqualToString:self.peerID]) { return; }
    self.peerRemark = [IMRemarkStore.sharedStore remarkForUser:self.peerID];
    [self refreshHeaderTexts];
    [self.tableView reloadData];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Telegram 风格详情页：保留 UINavigationController 堆栈和侧滑返回，但隐藏系统导航栏。
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    // 回前台抢回下载回调（同聊天页）：文件列表 + 媒体宫格里仍在跑的任务，防返回后进度条冻结。
    if (_downloads) {
        NSMutableArray<IMMessageModel *> *ms = [NSMutableArray array];
        if (self.tabRows.count) { [ms addObjectsFromArray:self.tabRows]; }
        if (self.tabMediaMessages.count) { [ms addObjectsFromArray:self.tabMediaMessages]; }
        [_downloads reattachActiveTasksForMessages:ms];
    }
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // 主导航容器始终隐藏系统 UINavigationBar。返回时若临时恢复系统栏，会与统一 Glass 导航栏叠加产生双标题/双阴影。
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.topInset = self.view.safeAreaInsets.top;
    CGFloat W = self.view.bounds.size.width;
    // 头部占位高度（含顶部安全区）。
    CGFloat headerH = [self headerHeight];
    UIView *spacer = self.tableView.tableHeaderView;
    if (ABS(spacer.frame.size.height - headerH) > 0.5) {
        spacer.frame = CGRectMake(0, 0, W, headerH);
        self.tableView.tableHeaderView = spacer; // 触发重新测量
    }
    self.pillsView.frame = CGRectMake(0, self.topInset + 208, W, kIMDetailPillsRowH);
    self.stickyBar.frame = CGRectMake(0, [self tabPinTop], W, kIMDetailTabBarH);
    [self layoutSegmented:self.stickySeg inWidth:W];
    [self syncScrollInset];
    [self applyHeaderMorph]; // 尺寸变化后重算
    [self updatePillsVisibility];
}

/// 所有详情页统一使用圆形头像头部；URL 仅替换头像内容。
- (CGFloat)headerHeight {
    return self.topInset + 200 + 8 + kIMDetailPillsRowH;
}

/// 底部 inset + 橡皮筋策略：
/// - **始终**补足到「能滚到头部收拢(H) + 页签贴顶(pin)」→ 任何内容长度都能上滑贴顶、点 tab 也能贴顶。
/// - 内容够长（贴顶后列表仍填满屏幕）→ 允许橡皮筋、可继续自然滚动（走 Zone② detent）。
/// - 内容不足（贴顶后下方是空白）→ `bounces=NO`：能滚到 pin 但**贴顶后禁止再越界上滑**（2(2)a，硬停不回弹）。
- (void)syncScrollInset {
    CGFloat viewH = self.tableView.bounds.size.height;
    if (viewH <= 0) { return; }
    CGFloat pin = [self pinOffset];
    CGFloat wantMax = MAX([self headerCollapseOffset], pin);        // 至少能滚到收拢 + 贴顶
    CGFloat naturalMax = self.tableView.contentSize.height - viewH; // 不含 inset 的最大 offset
    CGFloat bottom = MAX(0, wantMax - naturalMax);
    if (ABS(self.tableView.contentInset.bottom - bottom) > 0.5) {
        self.tableView.contentInset = UIEdgeInsetsMake(0, 0, bottom, 0);
    }
    // 贴顶后是否还有内容可滚：有→允许橡皮筋自然滚动；没有→硬停（贴顶即到顶，禁止越界上滑）。
    BOOL longEnough = naturalMax >= pin - 0.5;
    self.tableView.bounces = longEnough;
    self.tableView.alwaysBounceVertical = longEnough;
}

#pragma mark - 数据加载

- (void)loadConversationSettings {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    // 单会话设置端点（GET …/{id}/settings）：只要几个布尔，不再拉整张会话列表遍历查找。
    [IMHTTPService.sharedService conversationSettingsWithToken:token convID:self.convID
                                                    completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            // 兜底走老路（全量会话列表）：新 GET 端点是 2026-08-18 才加的，连到未重启的旧后端会 404。
            // **不能**静默保留 0/NO 默认——开关会渲染错，且随后的提交是整体替换 PUT，会拿错误基线
            // 悄悄清掉服务端的置顶/标未读（PUT 路由旧后端就有，写得进去）。
            [self loadConversationSettingsViaListFallback:token];
            return;
        }
        self.pinnedAt = [data[@"pinned_at"] longLongValue];
        self.muted = [data[@"muted"] boolValue];
        self.markedUnread = [data[@"marked_unread"] boolValue]; // PUT 整体替换，提交时须回传
        NSString *rmk = [data[@"remark"] isKindOfClass:[NSString class]] ? data[@"remark"] : nil;
        self.convRemark = rmk.length > 0 ? rmk : nil; // 群备注（G1）：替代群名显示
        [self reloadSettingsAndPills];
        [self refreshHeaderTexts]; // 备注变化 → 头部标题即时跟随
    }];
}

/// 旧后端兼容：按老方式拉全量会话列表找本会话的设置（仅在单会话端点失败时走）。
- (void)loadConversationSettingsViaListFallback:(NSString *)token {
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService conversationsWithToken:token completion:^(NSArray<IMConversation *> *convs, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error) { return; }
        for (IMConversation *c in convs) {
            if ([c.convID isEqualToString:self.convID]) {
                self.pinnedAt = c.pinnedAt;
                self.muted = c.muted;
                self.markedUnread = c.markedUnread;
                self.convRemark = c.remark.length > 0 ? c.remark : nil;
                [self reloadSettingsAndPills];
                [self refreshHeaderTexts];
                break;
            }
        }
    }];
}

- (void)loadGroupInfo {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService groupInfoWithToken:token convID:self.convID completion:^(IMGroupInfo *group, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || !group) { return; }
        self.group = group;
        self.groupName = group.name;
        [self resetSuperMemberPaging]; // 超级群：资料只回我自己，成员签另走分页（非超级群 no-op）
        BOOL manage = group.myRole == IMGroupRoleOwner || group.myRole == IMGroupRoleAdmin;
        [self.avatarView setAvatarURL:[self headerAvatarURL] seed:self.convID name:group.name];
        // 头像编辑统一由右上角“编辑”进入。
        self.liquidNavigationBar.actionTitle = manage ? @"编辑" : nil;
        [self refreshHeaderTexts];
        [self rebuildTabs];
        [self.tableView reloadData];
        [self.view setNeedsLayout];
    }];
}

- (void)avatarTapped {
    NSString *url = [self headerAvatarURL];
    NSURL *URL = [NSURL URLWithString:url];
    NSString *scheme = URL.scheme.lowercaseString;
    if (url.length == 0 || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        return;
    }
    IMMediaViewerViewController *viewer =
        [IMMediaViewerViewController viewerWithURL:url isVideo:NO
                                   preloadedImage:self.avatarView.photo.image
                                    onOpenGallery:nil];
    viewer.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)loadPeerBlockState {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService friendsWithToken:token status:nil completion:^(NSArray<IMUserCard *> *friends, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error) { return; }
        BOOL wasFriend = self.peerIsFriend;
        BOOL isFriend = NO;
        for (IMUserCard *c in friends) {
            if ([c.userID isEqualToString:self.peerID]) {
                self.peerBlocked = c.blocked;
                self.peerRemark = c.remark;
                isFriend = (c.status == IMFriendStatusAccepted); // 拉黑的好友 status 仍 accepted，故仍算好友
                break;
            }
        }
        self.peerIsFriend = isFriend;
        [self refreshHeaderTexts]; // 备注可能变了 → 标题/头像首字母跟着刷
        [self.tableView reloadData]; // 刷新「更多」菜单的 拉黑/取消拉黑 文案 + actions cell 操作排
        if (wasFriend != isFriend) { [self rebuildPillsView]; } // 好友态变化 → 重建 header 悬浮操作排
    }];
}

/// 群模式：拉取我的 accepted 好友 uid 集合，供成员长按菜单区分「发送消息」/「添加好友」。
- (void)loadFriendUIDs {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService friendsWithToken:token status:nil completion:^(NSArray<IMUserCard *> *friends, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error) { return; }
        NSMutableSet<NSString *> *uids = [NSMutableSet set];
        for (IMUserCard *c in friends) {
            if (c.status == IMFriendStatusAccepted && c.userID.length) { [uids addObject:c.userID]; }
        }
        self.friendUIDs = uids;
        // 无需 reloadData：菜单在长按时惰性构建，届时读取最新 friendUIDs 即可。
    }];
}

/// 我是否已是该 uid 的好友（friendUIDs 尚未加载完成时返回 NO，长按菜单默认给「添加好友」入口）。
- (BOOL)isFriendUID:(NSString *)uid {
    return uid.length > 0 && [self.friendUIDs containsObject:uid];
}

- (void)refreshHeaderTexts {
    NSString *name = self.displayTitle, *sub = self.displaySubtitle;
    self.nameOnImage.text = name; self.nameBelow.text = name;
    self.subOnImage.text = sub; self.subBelow.text = sub;
    self.liquidNavigationBar.titleText = name;
    self.liquidNavigationBar.subtitleText = sub;
}

- (void)reloadSettingsAndPills {
    [self.tableView reloadData];
}

#pragma mark - 事件

- (void)onGroupEvent:(NSNotification *)note {
    if (![note.userInfo[kIMConvIDKey] isEqualToString:self.convID]) { return; }
    NSString *event = note.userInfo[kIMGroupEventKey];
    NSString *target = note.userInfo[kIMGroupTargetKey];
    if (([event isEqualToString:@"remove"] && [target isEqualToString:self.userID]) ||
        [event isEqualToString:@"dissolve"]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self loadGroupInfo];
}

- (void)onConvUpdate:(NSNotification *)note {
    if (![note.userInfo[kIMConvIDKey] isEqualToString:self.convID]) { return; }
    [self loadConversationSettings];
}

/// 任务2：某条消息被物理移除（为所有人删除 / 仅为我删除）→ 本会话则重建页签（文件列表去掉该行）。
- (void)onMessageRemoved:(NSNotification *)note {
    if (![note.userInfo[kIMConvIDKey] isEqualToString:self.convID]) { return; }
    [self rebuildTabs];
    [self.tableView reloadData];
}

#pragma mark - 页签

- (void)rebuildTabs {
    __block NSArray<IMMessageModel *> *msgs = @[];
    [self performDatabaseOperation:^(IMDatabase *database) {
        msgs = [database messagesForConv:self.convID];
    }];
    self.tabs = [IMChatDetailTabs tabsForMessages:msgs isGroup:self.isGroup];
    if (self.selectedTab >= (NSInteger)self.tabs.count) { self.selectedTab = 0; }
    // 分段控件
    if (!self.segmented) {
        self.segmented = [[IMLiquidSegmentedControl alloc] initWithFrame:CGRectZero];
        [self.segmented addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        [self addTabPinTapTo:self.segmented]; // 单 tab / 重复点当前 tab 也能贴顶
    }
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:self.tabs.count];
    for (IMChatDetailTab *t in self.tabs) { [titles addObject:t.title ?: @""]; }
    self.segmented.titles = titles;
    self.stickySeg.titles = titles;
    if (self.tabs.count > 0) {
        self.segmented.selectedIndex = self.selectedTab;
        self.stickySeg.selectedIndex = self.selectedTab;
    }
    [self recomputeTabContentWithMessages:msgs]; // 复用上面已加载的消息，避免再读一次全表
}

- (void)segmentChanged:(IMLiquidSegmentedControl *)seg { [self switchToTab:seg.selectedIndex scrollToPin:YES]; }
- (void)stickySegChanged:(IMLiquidSegmentedControl *)seg { [self switchToTab:seg.selectedIndex scrollToPin:YES]; }

/// 相邻页签横滑切换（左滑=下一签、右滑=上一签），带水平滑入动画（Fix-B/横滑）。
- (void)swipeToNextTab:(UISwipeGestureRecognizer *)g {
    if (self.selectedTab + 1 < (NSInteger)self.tabs.count) { [self switchToTab:self.selectedTab + 1 scrollToPin:NO]; }
}
- (void)swipeToPrevTab:(UISwipeGestureRecognizer *)g {
    if (self.selectedTab - 1 >= 0) { [self switchToTab:self.selectedTab - 1 scrollToPin:NO]; }
}

/// 分段控件被点击（含单 tab / 重复点当前 tab）→ 仅贴顶（切换由 valueChanged 走 switchToTab）。
/// 已贴顶时直接返回：切换不同 tab 时本 tap 与 valueChanged→switchToTab 同触发，若此刻（尤其媒体深滚后）
/// 再发一次 animated 的 scrollTabsToPin，会与 switchToTab 的 reloadData 相撞（animated setContentOffset + reloadData
/// → 弹到页顶，Bug b）。贴顶态无需再贴，交给 switchToTab 无动画保持即可。
- (void)tabBarTapped {
    if ([self tabsArePinned]) { return; }
    [self scrollTabsToPinAnimated:YES];
}

/// 页签贴顶的目标 offset（页签分区顶对齐折叠顶栏下沿）。页签分区之上的内容固定，故此值恒定。
- (CGFloat)pinOffset {
    NSInteger sec = [self indexOfSection:IMDetailSectionTabs];
    if (sec == NSNotFound) { return 0; }
    CGRect hr = [self.tableView rectForHeaderInSection:sec];
    return MAX(0, hr.origin.y - [self tabPinTop]);
}
- (BOOL)tabsArePinned { return self.tableView.contentOffset.y >= [self pinOffset] - 1; }

/// 切换页签：**内容瞬时替换、零动画**。已贴顶→保持贴顶（**绝不回露头部再滑回**，这是之前"先滑到顶再滑回"的根因）；
/// 未贴顶且需要贴顶→平滑滚过去。
- (void)switchToTab:(NSInteger)index scrollToPin:(BOOL)scrollToPin {
    if (index < 0 || index >= (NSInteger)self.tabs.count) { return; }
    if (index == self.selectedTab) { if (scrollToPin && ![self tabsArePinned]) { [self scrollTabsToPinAnimated:YES]; } return; }
    BOOL wasPinned = [self tabsArePinned];
    self.selectedTab = index;
    [self.segmented setSelectedIndex:index animated:YES];
    [self.stickySeg setSelectedIndex:index animated:YES];
    [self recomputeTabContent];
    if ([self indexOfSection:IMDetailSectionTabs] == NSNotFound) { return; }
    [UIView performWithoutAnimation:^{
        [self.tableView reloadData];       // 整表零动画重建：内容瞬时替换，无逐行高度动画
        [self.tableView layoutIfNeeded];
        [self syncScrollInset];            // 始终补足 inset → pin 可达（估算已关，pinOffset 立即准确）
        if (wasPinned) {                   // #4 已贴顶：直接钉在贴顶位（不露头部、不回进入态）
            self.tableView.contentOffset = CGPointMake(0, [self pinOffset]);
        }
    }];
    if (wasPinned) {
        // 安全网：reloadData 后布局在下一帧可能再次结算，届时强制断言一次贴顶位，抵消偶发落偏。
        __weak typeof(self) ws = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self || [self indexOfSection:IMDetailSectionTabs] == NSNotFound) { return; }
            [self syncScrollInset];
            self.tableView.contentOffset = CGPointMake(0, [self pinOffset]);
        });
    } else if (scrollToPin) {              // 之前在头部区、点了 tab：平滑滚到贴顶（#2(2) 点 tab 即贴顶）
        __weak typeof(self) ws = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [ws scrollTabsToPinAnimated:YES]; });
    }
}

/// 把页签分区滚到折叠顶栏正下方（贴顶）。
- (void)scrollTabsToPinAnimated:(BOOL)animated {
    if ([self indexOfSection:IMDetailSectionTabs] == NSNotFound) { return; }
    CGFloat maxOff = self.tableView.contentSize.height + self.tableView.contentInset.bottom - self.tableView.bounds.size.height;
    CGFloat target = IMClamp([self pinOffset], 0, MAX(0, maxOff));
    [self.tableView setContentOffset:CGPointMake(0, target) animated:animated];
}

/// 页签分区滚到折叠顶栏下方即显示吸顶条（其下列表继续滚动，无缝衔接）。
- (void)updateStickyTabs {
    NSInteger sec = [self indexOfSection:IMDetailSectionTabs];
    if (sec == NSNotFound || self.tabs.count == 0) { self.stickyBar.hidden = YES; self.segmented.hidden = NO; return; }
    CGRect hr = [self.tableView rectForHeaderInSection:sec];
    CGFloat headerTopInView = hr.origin.y - self.tableView.contentOffset.y;
    BOOL pinned = headerTopInView <= [self tabPinTop] + 0.5;
    self.stickyBar.hidden = !pinned;
    // 贴顶后隐藏表内真分段——吸顶条透明，真 header 上移时会从其后透出，与镜像分段并存（两个 tab 栏）。
    self.segmented.hidden = pinned;
    if (pinned && self.stickySeg.selectedIndex != self.selectedTab) {
        self.stickySeg.selectedIndex = self.selectedTab;
    }
}

/// 新→旧（timestamp 降序）比较器；媒体页与文件/语音/链接页共用。
- (NSComparator)tabNewestFirstComparator {
    return ^NSComparisonResult(IMMessageModel *a, IMMessageModel *b) {
        return a.timestamp > b.timestamp ? NSOrderedAscending : (a.timestamp < b.timestamp ? NSOrderedDescending : NSOrderedSame);
    };
}

/// 依当前选中页签，预备内容数组（媒体项 / 文件·语音·链接消息）。
/// 传入已加载的会话消息可省一次全表读（rebuildTabs 复用其结果）；传 nil 时自行从库加载。
- (void)recomputeTabContentWithMessages:(NSArray<IMMessageModel *> *)msgs {
    self.tabMedia = @[]; self.tabMediaMessages = @[]; self.tabRows = @[];
    if (self.tabs.count == 0) { return; }
    IMChatDetailTab *t = self.tabs[self.selectedTab];
    if (t.kind == IMDetailTabKindMembers) { return; }
    if (!msgs) {
        __block NSArray<IMMessageModel *> *loaded = @[];
        [self performDatabaseOperation:^(IMDatabase *database) {
            loaded = [database messagesForConv:self.convID];
        }];
        msgs = loaded;
    }
    if (t.kind == IMDetailTabKindMedia) {
        NSMutableArray<IMMessageModel *> *media = [NSMutableArray array];
        for (IMMessageModel *m in msgs) {
            if ([IMChatDetailTabs message:m matchesKind:IMDetailTabKindMedia]) { [media addObject:m]; }
        }
        // 新→旧。**先排消息再派生 item**，保证 tabMedia 与 tabMediaMessages 逐位对齐
        //（宫格要按 index 反查消息取下载态/thumb）。
        NSArray<IMMessageModel *> *sorted = [media sortedArrayUsingComparator:[self tabNewestFirstComparator]];
        NSMutableArray<IMMediaItem *> *items = [NSMutableArray arrayWithCapacity:sorted.count];
        for (IMMessageModel *m in sorted) {
            [items addObject:[IMMediaItem itemWithURL:IMMediaFullURL(m.content, self.host)
                                              isVideo:[m.contentType isEqualToString:@"video"]
                                            timestamp:m.timestamp
                                                thumb:m.thumb durationMillis:m.duration]];
        }
        self.tabMediaMessages = sorted;
        self.tabMedia = items;
        return;
    }
    // 文件/语音/链接：过滤 + 新→旧
    NSMutableArray<IMMessageModel *> *rows = [NSMutableArray array];
    for (IMMessageModel *m in msgs) { if ([IMChatDetailTabs message:m matchesKind:t.kind]) { [rows addObject:m]; } }
    self.tabRows = [rows sortedArrayUsingComparator:[self tabNewestFirstComparator]];
}

- (void)recomputeTabContent { [self recomputeTabContentWithMessages:nil]; }

#pragma mark - Section 组装

/// 当前页面的 section 顺序。
- (NSArray<NSNumber *> *)sectionLayout {
    NSMutableArray<NSNumber *> *s = [NSMutableArray array];
    // 非好友（单聊）：只保留头像 + 操作排（加好友/更多），隐藏备注名·设置·页签三张卡——
    // 尚未建立关系时这些设置无意义。仅隐藏，数据加载逻辑不动（加为好友后 reloadData 即恢复）。
    if (!self.isGroup && !self.peerIsFriend) { return s; }
    if (!self.isGroup) { [s addObject:@(IMDetailSectionInfo)]; } // 单聊：备注名/用户名
    if (self.isGroup && [self aboutRowKinds].count > 0) { [s addObject:@(IMDetailSectionAbout)]; } // 公告/简介卡（Pills 下）
    [s addObject:@(IMDetailSectionSettings)];
    if (self.tabs.count > 0) { [s addObject:@(IMDetailSectionTabs)]; }
    return s;
}
- (IMDetailSection)sectionKindAt:(NSInteger)index { return (IMDetailSection)[[self sectionLayout][index] integerValue]; }
- (NSInteger)indexOfSection:(IMDetailSection)kind {
    NSArray *layout = [self sectionLayout];
    for (NSInteger i = 0; i < (NSInteger)layout.count; i++) { if ([layout[i] integerValue] == kind) { return i; } }
    return NSNotFound;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return [self sectionLayout].count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self sectionKindAt:section]) {
        case IMDetailSectionInfo:     return 2; // 备注名 + 用户名
        case IMDetailSectionAbout:    return (NSInteger)[self aboutRowKinds].count;
        case IMDetailSectionSettings: return (NSInteger)[self settingsRowKinds].count;
        case IMDetailSectionTabs:     return [self tabRowCount];
    }
    return 0;
}

- (NSInteger)tabRowCount {
    if (self.tabs.count == 0) { return 0; }
    IMChatDetailTab *t = self.tabs[self.selectedTab];
    switch (t.kind) {
        case IMDetailTabKindMembers: // [添加成员] + 成员（超级群分页累积）+ 可选「加载更多」行
            return [self memberRowOffset] + (NSInteger)self.displayMembers.count
                 + ((self.group.isSuper && self.superHasMore) ? 1 : 0);
        case IMDetailTabKindMedia:   return 1;                                        // 1 个宫格 cell（空态也占位）
        default:                     return MAX(1, (NSInteger)self.tabRows.count);    // 至少 1（空态提示）
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if ([self sectionKindAt:section] != IMDetailSectionTabs) { return nil; }
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, kIMDetailTabBarH)];
    [self layoutSegmented:self.segmented inWidth:tableView.bounds.size.width];
    [wrap addSubview:self.segmented];
    return wrap;
}

/// 分段控件按内容宽居中（贴顶条与表内一致，单/多 tab 段宽固定）。段高 kIMDetailTabSegH、下限加宽 → 点击面积更大。
- (void)layoutSegmented:(IMLiquidSegmentedControl *)seg inWidth:(CGFloat)width {
    CGFloat w = [seg sizeThatFits:CGSizeMake(width - 32, kIMDetailTabSegH)].width;
    // 多 tab 下限 200（大点击面积）；**单 tab 收窄到 1/3（~67）**——单个页签无需铺那么宽，居中更紧凑。
    CGFloat minW = self.tabs.count <= 1 ? 200.0 / 3.0 : 200;
    w = IMClamp(w, minW, width - 32);
    seg.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    seg.frame = CGRectMake((width - w) / 2, (kIMDetailTabBarH - kIMDetailTabSegH) / 2, w, kIMDetailTabSegH);
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    IMDetailSection kind = [self sectionKindAt:section];
    if (kind == IMDetailSectionTabs) { return kIMDetailTabBarH; }
    return 12;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMDetailSection kind = [self sectionKindAt:indexPath.section];
    if (kind == IMDetailSectionAbout) { return 64; } // 标题 + 一行预览（subtitle 样式）
    if (kind == IMDetailSectionTabs && self.tabs.count > 0) {
        IMChatDetailTab *t = self.tabs[self.selectedTab];
        if (t.kind == IMDetailTabKindMembers) { return 60; }
        if (t.kind == IMDetailTabKindMedia) {
            // 宽度必须与宫格排布用的**真实** cell 内容宽一致，否则行高多出几 pt → 卡片底部白边。
            // 真实宽由 cell 首次布局回调上报（见 mediaGridWidth）；未知时先用估算值兜底。
            CGFloat w = self.mediaGridWidth > 0 ? self.mediaGridWidth : tableView.bounds.size.width - 32;
            CGFloat h = [IMDetailMediaContainerCell heightForCount:self.tabMedia.count width:w];
            return h > 0 ? h : 60;
        }
        if (t.kind == IMDetailTabKindFiles) { return 74; } // 文件行 3 行：文件名 + 状态 + 时间（#2b；详情页无来源行）
        // 语音行 3 行（sketch §10 + 新布局）：sender 18 + mini(44=波形+meta) + time 13 + spacing 6×2 + padding 20 ≈ 100pt；106 留冗余。
        if (t.kind == IMDetailTabKindVoice) { return 106; }
        // 链接行 3 行：og:title/host + host+path + 时间（草图 §C，IMDetailLinkCell 内嵌 IMLinkRowView）——
        // 内部 t1(16)+2+t2(14)+2+t3(14)=48pt + cell 上下 padding 9+9=66pt；旧的 60pt 会截掉时间行（用户反馈）。
        if (t.kind == IMDetailTabKindLinks) { return 74; }
        // 名片行：群聊恒带「由 X 分享」第三行 → 用带来源的高度；单聊无来源，仍是 64（§7.1）。
        if (t.kind == IMDetailTabKindContacts) { return self.isGroup ? IMDetailContactCellHeightWithSource : IMDetailContactCellHeight; }
        return 60;
    }
    return 52;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ([self sectionKindAt:indexPath.section]) {
        case IMDetailSectionInfo:     return [self infoCell:tableView row:indexPath.row];
        case IMDetailSectionAbout:    return [self aboutCell:tableView row:indexPath.row];
        case IMDetailSectionSettings: return [self settingsCell:tableView row:indexPath.row];
        case IMDetailSectionTabs:     return [self tabCell:tableView row:indexPath.row];
    }
    return [tableView dequeueReusableCellWithIdentifier:@"plain" forIndexPath:indexPath];
}

#pragma mark - Cells

/// 系统样式 cell 统一出池：详情页各分区行原先每次 reloadData 全新 alloc（怕分支间字段残留），
/// 改为复用池 + **出池即全字段重置**，各 builder 只设自己的差异字段——既复用又不怕残留。
- (UITableViewCell *)dequeueStyledCell:(UITableViewCellStyle)style reuseID:(NSString *)reuseID inTable:(UITableView *)tv {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) { cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:reuseID]; }
    cell.textLabel.text = nil;
    cell.textLabel.textColor = IMTheme.textPrimary;
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.textLabel.textAlignment = NSTextAlignmentNatural;
    cell.detailTextLabel.text = nil;
    cell.detailTextLabel.textColor = IMTheme.textSecondary;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail; // aboutCell 会改，出池拉回默认
    cell.imageView.image = nil;
    cell.imageView.tintColor = IMTheme.accent;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

#pragma mark - 公告 / 简介卡（全员只读，G1 修）

/// 群公告/简介卡的行类型（顺序即展示顺序）。
typedef NS_ENUM(NSInteger, IMDetailAboutRow) {
    IMDetailAboutRowAnnouncement = 0, ///< 群公告（非空才显）
    IMDetailAboutRowIntro,            ///< 群简介（非空才显）
};

/// 组装公告/简介卡当前应显示的行——公告/简介**非空才显**，都空则整卡不显（sectionLayout 里据 count 决定）。
- (NSArray<NSNumber *> *)aboutRowKinds {
    NSMutableArray<NSNumber *> *rows = [NSMutableArray array];
    if (!self.isGroup) { return rows; }
    if (self.group.announcement.length > 0) { [rows addObject:@(IMDetailAboutRowAnnouncement)]; }
    if (self.group.intro.length > 0) { [rows addObject:@(IMDetailAboutRowIntro)]; }
    return rows;
}

/// 折行/连续空白压成单行预览（详情页卡与横幅一致）。
- (NSString *)aboutSingleLinePreview:(NSString *)text {
    NSArray<NSString *> *parts = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *part in parts) { if (part.length > 0) { [kept addObject:part]; } }
    return [kept componentsJoinedByString:@" "];
}

- (UITableViewCell *)aboutCell:(UITableView *)tv row:(NSInteger)row {
    NSArray<NSNumber *> *kinds = [self aboutRowKinds];
    IMDetailAboutRow kind = (row < (NSInteger)kinds.count) ? (IMDetailAboutRow)kinds[row].integerValue : IMDetailAboutRowAnnouncement;
    UITableViewCell *cell = [self dequeueStyledCell:UITableViewCellStyleSubtitle reuseID:@"dSub" inTable:tv];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (kind == IMDetailAboutRowAnnouncement) {
        cell.imageView.image = [UIImage systemImageNamed:@"megaphone"];
        cell.textLabel.text = @"群公告";
        cell.detailTextLabel.text = [self aboutSingleLinePreview:self.group.announcement];
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"info.circle"];
        cell.textLabel.text = @"群简介";
        cell.detailTextLabel.text = [self aboutSingleLinePreview:self.group.intro];
    }
    return cell;
}

/// 设置区行类型（顺序即展示顺序）。群聊比单聊多「我在本群的昵称/群备注」，管理员再多「群管理」。
typedef NS_ENUM(NSInteger, IMDetailSettingsRow) {
    IMDetailSettingsRowPin = 0,     ///< 置顶聊天
    IMDetailSettingsRowMute,        ///< 消息免打扰
    IMDetailSettingsRowMyNickname,  ///< 我在本群的昵称（群聊，任意成员，G1）
    IMDetailSettingsRowRemark,      ///< 群备注（群聊，仅本人可见，G1）
    IMDetailSettingsRowGroupQR,     ///< 群二维码（群聊，QRCODE P0；perm_invite=1 时对非管理员隐藏）
    IMDetailSettingsRowGroupInviteLink, ///< 群邀请链接（群聊；与二维码同源同权限，展示在二维码下方）
    IMDetailSettingsRowManage,      ///< 群管理（群主/管理员）
};

/// 组装设置区当前应显示的行（避免硬编码 0/1/2 造成群/单聊分叉 bug）。
- (NSArray<NSNumber *> *)settingsRowKinds {
    NSMutableArray<NSNumber *> *rows = [NSMutableArray arrayWithObjects:@(IMDetailSettingsRowPin), @(IMDetailSettingsRowMute), nil];
    if (self.isGroup) {
        [rows addObject:@(IMDetailSettingsRowMyNickname)]; // 任意成员可改自己的群昵称
        [rows addObject:@(IMDetailSettingsRowRemark)];     // 群备注（仅本人可见）
        // 群二维码 + 群邀请链接：perm_invite=1 时对非管理员隐藏（无邀请权者不给死胡同入口，对齐微信）。
        if ([self inviteEntriesVisible]) {
            [rows addObject:@(IMDetailSettingsRowGroupQR)];
            [rows addObject:@(IMDetailSettingsRowGroupInviteLink)];
        }
        if ([self canManageGroup]) { [rows addObject:@(IMDetailSettingsRowManage)]; }
    }
    return rows;
}

- (UITableViewCell *)settingsCell:(UITableView *)tv row:(NSInteger)row {
    NSArray<NSNumber *> *kinds = [self settingsRowKinds];
    IMDetailSettingsRow kind = (row < (NSInteger)kinds.count) ? (IMDetailSettingsRow)kinds[row].integerValue : IMDetailSettingsRowPin;
    UITableViewCell *cell = [self dequeueStyledCell:UITableViewCellStyleValue1 reuseID:@"dVal" inTable:tv];
    switch (kind) {
        case IMDetailSettingsRowPin: {
            cell.textLabel.text = @"置顶聊天";
            UISwitch *sw = [UISwitch new]; sw.on = self.pinnedAt > 0; sw.tag = 1;
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            break;
        }
        case IMDetailSettingsRowMute: {
            cell.textLabel.text = @"消息免打扰";
            UISwitch *sw = [UISwitch new]; sw.on = self.muted; sw.tag = 2;
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            break;
        }
        case IMDetailSettingsRowMyNickname:
            cell.textLabel.text = @"我在本群的昵称";
            cell.detailTextLabel.text = self.group.myNickname.length ? self.group.myNickname : @"未设置";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case IMDetailSettingsRowRemark:
            cell.textLabel.text = @"群备注";
            cell.detailTextLabel.text = [self currentConvRemark].length ? [self currentConvRemark] : @"未设置";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case IMDetailSettingsRowGroupQR:
            cell.textLabel.text = @"群二维码";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case IMDetailSettingsRowGroupInviteLink:
            cell.textLabel.text = @"群邀请链接";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case IMDetailSettingsRowManage:
            cell.textLabel.text = @"群管理";
            // 有待审入群申请时把红点带到「群管理」行（不必进管理页才发现，G3 修）。
            if (self.group.pendingCount > 0) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 待审", (long)self.group.pendingCount];
                cell.detailTextLabel.textColor = IMTheme.danger;
            } else {
                cell.detailTextLabel.text = @"仅群主/管理员";
            }
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
    }
    return cell;
}

- (UITableViewCell *)tabCell:(UITableView *)tv row:(NSInteger)row {
    IMChatDetailTab *t = self.tabs[self.selectedTab];
    if (t.kind == IMDetailTabKindMembers) { return [self memberTabCell:tv row:row]; }
    if (t.kind == IMDetailTabKindMedia) {
        if (self.tabMedia.count == 0) { return [self emptyCell:tv text:@"暂无媒体"]; }
        IMDetailMediaContainerCell *cell = [tv dequeueReusableCellWithIdentifier:@"mediagrid"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        __weak typeof(self) ws = self;
        cell.onPick = ^(IMMediaItem *item) { [ws openMediaItem:item]; };
        // 逐格门控（M4-7）：必须在 setItems: 前挂好——reloadData 会立刻回调查询每格状态。
        cell.stateForItemIndex = ^IMDownloadProgress *(NSInteger i) {
            IMMessageModel *mm = [ws mediaMessageAtIndex:i];
            return mm ? [ws.downloads stateForMessage:mm] : nil;
        };
        cell.thumbForItemIndex = ^NSString *(NSInteger i) { return [ws mediaMessageAtIndex:i].thumb; };
        cell.onDownloadItemIndex = ^(NSInteger i) {
            IMMessageModel *mm = [ws mediaMessageAtIndex:i];
            if (mm) { [ws.downloads handleTapForMessage:mm]; }
        };
        // 任务2：媒体宫格逐格长按菜单（转发/定位/取消下载/删除两档）——与文件行同一套。
        cell.contextMenuForItemIndex = ^UIContextMenuConfiguration *(NSInteger i) {
            IMMessageModel *mm = [ws mediaMessageAtIndex:i];
            return mm ? [ws contentMenuConfigForMessage:mm] : nil;
        };
        // 真实内容宽上报：与估算值不符时记下并只重算行高（beginUpdates/endUpdates 不重建 cell，无闪烁）。
        // 宽度只在首次布局/旋转时变一次，收敛后不再触发，无循环。
        cell.onContentWidthChanged = ^(CGFloat width) {
            __strong typeof(ws) self = ws;
            if (!self || ABS(self.mediaGridWidth - width) < 0.5) { return; }
            self.mediaGridWidth = width;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView beginUpdates];
                [self.tableView endUpdates];
            });
        };
        self.mediaContainerCell = cell;
        [cell setItems:self.tabMedia];
        return cell;
    }
    // 文件/语音/链接
    if (self.tabRows.count == 0) {
        NSString *empty = t.kind == IMDetailTabKindFiles ? @"暂无文件" : (t.kind == IMDetailTabKindVoice ? @"暂无语音" : (t.kind == IMDetailTabKindContacts ? @"暂无名片" : @"暂无链接"));
        return [self emptyCell:tv text:empty];
    }
    IMMessageModel *m = self.tabRows[row];
    // 文件行：三态专用 cell（未下载 ↓ / 下载中 环形+⏸ / 已下载 类型图标）。无右侧配件——
    // 点行=下载/暂停/继续/打开；取消下载走长按菜单（仅进行中文件才有该项）。草图 §04。
    if (t.kind == IMDetailTabKindFiles) {
        IMDetailFileCell *fc = [tv dequeueReusableCellWithIdentifier:@"detailfile"];
        [fc configureWithMessage:m download:[self.downloads stateForMessage:m]];
        return fc;
    }
    if (t.kind == IMDetailTabKindContacts) { return [self contactRowCellIn:tv message:m]; } // 见 +Contacts.m
    if (t.kind == IMDetailTabKindLinks) {
        // 草图 §C：36×36 favicon + t1 og:title(host 兜底) + t2 host+path(mono) + t3 时间；点行=打开链接、无来源、无原文预览。
        IMDetailLinkCell *lc = [tv dequeueReusableCellWithIdentifier:@"detaillink"];
        [lc configureWithMessage:m];
        return lc;
    }
    // 语音三行 cell（2026-08-27 sketch §10）：发送者 / IMVoiceMiniPlayerView / 年月日时:分。
    // 用固定 reuseID 让 +Actions.m 的装配只在首次挂 stack，复用只更新内容。
    UITableViewCell *cell = [self dequeueStyledCell:UITableViewCellStyleDefault reuseID:@"dVoice3mini" inTable:tv];
    cell.selectionStyle = UITableViewCellSelectionStyleNone; // 三行 cell 有内部播放键，行整体选中反而误导
    [self decorateVoiceRow3Cell:cell message:m];
    return cell;
}

- (UITableViewCell *)emptyCell:(UITableView *)tv text:(NSString *)text {
    UITableViewCell *cell = [self dequeueStyledCell:UITableViewCellStyleDefault reuseID:@"dDef" inTable:tv];
    cell.textLabel.text = text; cell.textLabel.textColor = IMTheme.textSecondary;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

#pragma mark - UITableViewDelegate（点选）

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IMDetailSection kind = [self sectionKindAt:indexPath.section];
    if (kind == IMDetailSectionInfo && indexPath.row == 0) { [self editRemark]; return; }
    if (kind == IMDetailSectionAbout) {
        NSArray<NSNumber *> *kinds = [self aboutRowKinds];
        if (indexPath.row >= (NSInteger)kinds.count) { return; }
        if ((IMDetailAboutRow)kinds[indexPath.row].integerValue == IMDetailAboutRowAnnouncement) {
            [IMGroupTextViewController presentFrom:self title:@"群公告"
                                          subtitle:[IMGroupTextViewController announceSubtitleForMillis:self.group.announcementAt]
                                              body:self.group.announcement];
        } else {
            [IMGroupTextViewController presentFrom:self title:@"群简介" subtitle:nil body:self.group.intro];
        }
        return;
    }
    if (kind == IMDetailSectionSettings) {
        NSArray<NSNumber *> *kinds = [self settingsRowKinds];
        if (indexPath.row >= (NSInteger)kinds.count) { return; }
        switch ((IMDetailSettingsRow)kinds[indexPath.row].integerValue) {
            case IMDetailSettingsRowMyNickname: [self editMyGroupNickname]; break;
            case IMDetailSettingsRowRemark:     [self editGroupRemark]; break;
            case IMDetailSettingsRowGroupQR:    [self openGroupQR]; break;
            case IMDetailSettingsRowGroupInviteLink: [self openGroupInviteLink]; break;
            case IMDetailSettingsRowManage:     [self openGroupManage]; break;
            default: break; // 置顶/免打扰走开关，不响应行点击
        }
        return;
    }
    if (kind == IMDetailSectionTabs && self.tabs.count > 0) {
        IMChatDetailTab *t = self.tabs[self.selectedTab];
        if (t.kind == IMDetailTabKindMembers) {
            [self handleMemberTabTapAtRow:indexPath.row];
        } else if (t.kind == IMDetailTabKindFiles) {
            if (indexPath.row >= (NSInteger)self.tabRows.count) { return; }
            IMMessageModel *m = self.tabRows[indexPath.row];
            // 与聊天页气泡口径完全一致（发送方 = 收到方）：本机有原件 → QuickLook；否则点整条 = 触发下载。
            // 自己发的文件发送时已收编进下载缓存（IMMediaSendService+adoptFileAtPath），故一般点开即 QuickLook；
            // 清缓存后 localFileForMessage 返回 nil，自然回落到 handleTapForMessage 触发下载。
            if ([self.downloads localFileForMessage:m]) { [self openCachedFileForMessage:m]; }
            else { [self.downloads handleTapForMessage:m]; }
        } else if (t.kind == IMDetailTabKindVoice) {
            // 三行 cell 的 ▶/波形自己处理播放（IMVoiceMiniPlayerView.onPlayTap）；行整体点击不动作，避免与内部键冲突。
        } else if (t.kind == IMDetailTabKindLinks) {
            if (self.tabRows.count > 0) { [self openLink:IMMediaFullURL(self.tabRows[indexPath.row].content, self.host)]; }
        } else if (t.kind == IMDetailTabKindContacts) { [self openContactRowAtIndex:indexPath.row]; } // → 资料页（+Contacts.m）
    }
}

/// 成员行取对应成员（row>0；否则 nil）。
- (nullable IMGroupMember *)memberAtIndexPath:(NSIndexPath *)ip {
    if ([self sectionKindAt:ip.section] != IMDetailSectionTabs || self.tabs.count == 0) { return nil; }
    if (self.tabs[self.selectedTab].kind != IMDetailTabKindMembers) { return nil; }
    NSInteger offset = [self memberRowOffset];
    if (offset > 0 && ip.row == 0) { return nil; } // 「添加成员」行不是成员
    NSInteger i = ip.row - offset;
    NSArray<IMGroupMember *> *list = self.displayMembers;
    return (i >= 0 && i < (NSInteger)list.count) ? list[i] : nil; // 「加载更多」行越界 → nil，长按菜单等自然跳过
}

/// 我能否移除该成员（owner 可移任何非自己；admin 可移 member）。
- (BOOL)canRemoveMember:(IMGroupMember *)m {
    if (!m || [m.userID isEqualToString:self.userID]) { return NO; }
    IMGroupRole mine = self.group.myRole;
    return mine == IMGroupRoleOwner || (mine == IMGroupRoleAdmin && m.role == IMGroupRoleMember);
}

#pragma mark - 成员行：左滑移除

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMGroupMember *m = [self memberAtIndexPath:indexPath];
    if (![self canRemoveMember:m]) { return nil; }
    __weak typeof(self) ws = self;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"移除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [ws removeMember:m ban:@"cooldown"]; done(YES);
    }];
    remove.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[ remove ]];
}

#pragma mark - 成员行：长按上下文菜单（发送消息 / 管理 / 移除）

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    // 内容行长按（任务2）：文件/语音/链接三类逐行页签统一走同一套菜单（转发/定位/[取消下载]/删除）。
    // 媒体宫格逐格菜单在容器 cell 的 collectionView contextMenu 委托里；成员行走下方成员菜单。
    IMMessageModel *rowMsg = [self contentRowMessageAtIndexPath:indexPath];
    if (rowMsg) { return [self contentMenuConfigForMessage:rowMsg]; }
    IMGroupMember *m = [self memberAtIndexPath:indexPath];
    if (!m || [m.userID isEqualToString:self.userID]) { return nil; }
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *sug) {
        NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
        // 好友准入（微信式，任务一 P0）：好友 → 「发送消息」；非好友 → 「添加好友」（非好友发消息会被 200103 拒收）。
        if ([ws isFriendUID:m.userID]) {
            [items addObject:[UIAction actionWithTitle:@"发送消息" image:[UIImage systemImageNamed:@"bubble.right"]
                                            identifier:nil handler:^(UIAction *a) { [ws openChatWithMember:m]; }]];
        } else {
            [items addObject:[UIAction actionWithTitle:@"添加好友" image:[UIImage systemImageNamed:@"person.badge.plus"]
                                            identifier:nil handler:^(UIAction *a) { [ws requestAddFriendUID:m.userID]; }]];
        }
        if (ws.group.myRole == IMGroupRoleOwner && m.role == IMGroupRoleMember) {
            [items addObject:[UIAction actionWithTitle:@"设为管理员" image:[UIImage systemImageNamed:@"person.badge.shield.checkmark"]
                                            identifier:nil handler:^(UIAction *a) { [ws runGroupRole:ws.convID user:m.userID role:@"admin"]; }]];
        }
        if (ws.group.myRole == IMGroupRoleOwner && m.role == IMGroupRoleAdmin) {
            [items addObject:[UIAction actionWithTitle:@"撤销管理员" image:[UIImage systemImageNamed:@"person.badge.minus"]
                                            identifier:nil handler:^(UIAction *a) { [ws runGroupRole:ws.convID user:m.userID role:@"member"]; }]];
        }
        if (ws.group.myRole == IMGroupRoleOwner) {
            [items addObject:[UIAction actionWithTitle:@"转让群主" image:[UIImage systemImageNamed:@"crown"]
                                            identifier:nil handler:^(UIAction *a) { [ws confirmTransfer:m]; }]];
        }
        // G2 禁言/解禁：权限同移除（严格高于对方）。已被禁言显「解除禁言」，否则「禁言…」（弹时长）。
        if ([ws canRemoveMember:m]) {
            BOOL muted = m.muteUntil > IMNowMillis();
            if (muted) {
                [items addObject:[UIAction actionWithTitle:@"解除禁言" image:[UIImage systemImageNamed:@"speaker.wave.2"]
                                                identifier:nil handler:^(UIAction *a) {
                    [ws muteMember:m.userID until:0];
                }]];
            } else {
                [items addObject:[UIAction actionWithTitle:@"禁言…" image:[UIImage systemImageNamed:@"speaker.slash"]
                                                identifier:nil handler:^(UIAction *a) {
                    [ws pickMuteDurationForMember:m];
                }]];
            }
        }
        if ([ws canRemoveMember:m]) {
            // 「移出群聊」= cooldown（24h 内不能再加），与旧详情页对齐；服务端 ban=cooldown 归一为 24h。
            UIAction *rm = [UIAction actionWithTitle:@"移出群聊" image:[UIImage systemImageNamed:@"trash"]
                                          identifier:nil handler:^(UIAction *a) { [ws removeMember:m ban:@"cooldown"]; }];
            rm.attributes = UIMenuElementAttributesDestructive;
            [items addObject:rm];
            // 「移出并不再允许加入」= forever，与 Web MemberMenu 对齐。
            UIAction *rmBan = [UIAction actionWithTitle:@"移出并不再允许加入"
                                                 image:[UIImage systemImageNamed:@"nosign"]
                                            identifier:nil handler:^(UIAction *a) { [ws removeMember:m ban:@"forever"]; }];
            rmBan.attributes = UIMenuElementAttributesDestructive;
            [items addObject:rmBan];
        }
        return [UIMenu menuWithTitle:m.localDisplayName children:items];
    }];
}

/// 打开成员的资料页（走单聊右上头像同一逻辑）。
- (void)openPeerDetail:(IMGroupMember *)m {
    if (!m || [m.userID isEqualToString:self.userID]) { return; }
    IMChatDetailViewController *vc = [[IMChatDetailViewController alloc] initSingleWithHost:self.host userID:self.userID
                                                                                    peerID:m.userID
                                                                              peerNickname:m.displayName
                                                                             peerAvatarURL:m.avatarURL];
    vc.showsMessagePill = YES; // 从群成员进 → 操作排显「消息」
    [self.navigationController pushViewController:vc animated:YES];
}

/// 与成员开始单聊（长按「发送消息」）。
- (void)openChatWithMember:(IMGroupMember *)m {
    if (!m || [m.userID isEqualToString:self.userID]) { return; }
    [IMChatViewController openInNavigationController:self.navigationController
                                                host:self.host userID:self.userID
                                              peerID:m.userID readSeq:0 unread:0 peerReadSeq:0
                                        peerNickname:m.displayName peerAvatarURL:m.avatarURL];
}

/// 移除成员（带二次确认）。ban=cooldown（24h 冷却）/forever（永久拉黑，不再允许加入）。
- (void)removeMember:(IMGroupMember *)m ban:(NSString *)ban {
    if (![self canRemoveMember:m]) { return; }
    BOOL forever = [ban isEqualToString:@"forever"];
    NSString *title = forever
        ? [NSString stringWithFormat:@"移出「%@」并不再允许加入？", m.localDisplayName]
        : [NSString stringWithFormat:@"移出「%@」？", m.localDisplayName];
    NSString *message = forever
        ? @"该成员将被移出群聊并永久拉黑，无法再次通过邀请或扫码加入本群。"
        : @"该成员将被移出群聊。";
    [self confirmDestructive:title message:message action:@"移除" handler:^{
        NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService removeGroupMemberWithToken:token convID:self.convID userID:m.userID
                                                            ban:ban
                                                    completion:^(NSError *error) {
            if (error) { [ws im_showToast:error.localizedDescription]; return; }
            [ws loadGroupInfo];
        }];
    }];
}

/// 成员级禁言：until=0 解禁 / -1 永久 / 其余到期毫秒。
- (void)muteMember:(NSString *)userID until:(int64_t)until {
    NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService muteGroupMemberWithToken:token convID:self.convID userID:userID until:until
                                                completion:^(NSError *error) {
        if (error) { [ws im_showToast:error.localizedDescription]; return; }
        [ws loadGroupInfo];
    }];
}

/// 禁言时长弹窗：10 分钟 / 1 小时 / 1 天 / 永久（与旧 IMGroupInfoViewController 完全对齐）。
- (void)pickMuteDurationForMember:(IMGroupMember *)m {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"禁言时长"
                                                                   message:m.localDisplayName
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) ws = self;
    NSString *target = m.userID;
    void (^add)(NSString *, int64_t) = ^(NSString *title, int64_t untilMs) {
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) { [ws muteMember:target until:untilMs]; }]];
    };
    int64_t now = IMNowMillis();
    add(@"10 分钟", now + 10 * 60 * 1000);
    add(@"1 小时",  now + 60 * 60 * 1000);
    add(@"1 天",    now + 24 * 60 * 60 * 1000);
    add(@"永久", -1); // 服务端把 <0 归一为永久
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    // iPad 兜底锚点
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                                CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 动作：群成员管理（成员页签）

- (void)inviteMembers {
    // 二次拦（入口通常已隐藏；防竞态/异常路径点到）：无邀请权直接中文吐司，不进好友选择器。
    if (self.group.permInvite && ![self canManageGroup]) {
        [self im_showToast:@"群主已开启「仅管理员可邀请」，你无法邀请成员"];
        return;
    }
    NSMutableSet<NSString *> *inGroup = [NSMutableSet set];
    // 超级群下这份排除集只有"已加载的那几页"，翻没到的成员仍可能被选中——服务端对重复邀请幂等，可接受。
    for (IMGroupMember *m in self.displayMembers) { [inGroup addObject:m.userID]; }
    __weak typeof(self) ws = self;
    IMFriendPickerViewController *picker =
        [[IMFriendPickerViewController alloc] initWithHost:self.host userID:self.userID
                                                    excludedIDs:inGroup confirmTitle:@"邀请"
                                                         onDone:^(NSArray<NSString *> *ids) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        [self.navigationController popToViewController:self animated:YES];
        NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
        [IMHTTPService.sharedService inviteToGroupWithToken:token convID:self.convID memberIDs:ids
                                                 completion:^(NSArray<NSString *> *added, NSError *error) {
            if (error) {
                // 300207 = 被邀请者已被移出/冷却期：用邀请场景第三人称文案（区别于自加群映射的第二人称）。
                if (error.code == 300207) { [self im_showToast:@"该成员已被移出本群，暂时无法再次邀请"]; }
                // 300204 = 无邀请权（竞态：进选择器后群主刚开启「仅管理员可邀请」）。后端此码下发英文默认文案，
                // 且 300204 被多场景复用不宜在 IMFriendlyMessageForCode 一刀切映射，故在此邀请场景就地给中文。
                else if (error.code == 300204) { [self im_showToast:@"群主已开启「仅管理员可邀请」，你无法邀请成员"]; }
                else { [self im_showToast:error.localizedDescription]; }
                return;
            }
            // 按**实际加入数**给反馈，不能一律报成功：服务端会跳过已在群里的人（幂等，不是错误），
            // 而端上的排除集在超级群下必然不全——那时 displayMembers 只有已翻到的那几页。
            NSInteger skipped = (NSInteger)ids.count - (NSInteger)added.count;
            if (added.count == 0) { [self im_showToast:@"所选的人都已在群里"]; }
            else if (skipped > 0) { [self im_showToast:[NSString stringWithFormat:@"已邀请 %ld 人，其余 %ld 人已在群里",
                                                        (long)added.count, (long)skipped]]; }
            [self loadGroupInfo]; // 内含 resetSuperMemberPaging：超级群成员签从第一页重拉
        }];
    }];
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)runGroupRole:(NSString *)convID user:(NSString *)user role:(NSString *)role {
    NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService setGroupRoleWithToken:token convID:convID userID:user role:role completion:^(NSError *error) {
        if (error) { [ws im_showToast:error.localizedDescription]; return; }
        [ws loadGroupInfo];
    }];
}

- (void)confirmTransfer:(IMGroupMember *)member {
    [self confirmDestructive:@"转让群主"
                     message:[NSString stringWithFormat:@"确定把群主转让给 %@？你将变为普通成员。", member.localDisplayName]
                      action:@"转让" handler:^{
        NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService transferGroupWithToken:token convID:self.convID userID:member.userID completion:^(NSError *error) {
            if (error) { [ws im_showToast:error.localizedDescription]; return; }
            [ws loadGroupInfo];
        }];
    }];
}

- (BOOL)canManageGroup {
    return self.group && (self.group.myRole == IMGroupRoleOwner || self.group.myRole == IMGroupRoleAdmin);
}

/// perm_invite 开启且我非群主/管理员时，隐藏所有「邀请」类入口（群二维码 / 群邀请链接 / 添加成员）。
/// 对齐微信：无邀请权者不给死胡同入口；服务端仍是权威闸门（点到也会被 300204/300212 拦）。
- (BOOL)inviteEntriesVisible {
    return !(self.isGroup && self.group.permInvite && ![self canManageGroup]);
}

- (void)openGroupManage {
    if (![self canManageGroup]) { return; }
    __weak typeof(self) ws = self;
    IMGroupManageViewController *vc = [[IMGroupManageViewController alloc] initWithHost:self.host userID:self.userID
                                                                                convID:self.convID group:self.group
                                                                             onChanged:^{ [ws loadGroupInfo]; }];
    [self.navigationController pushViewController:vc animated:YES];
}

/// 群二维码（QRCODE P0，任意成员可出示；perm_invite=1 时仅群主/管理员可出码——码即邀请链接）。
/// 无权限时不进入卡片页，直接中文吐司（对齐 Web：Web 亦不打开模态、只吐司）。
- (void)openGroupQR { [self pushGroupCardAsLink:NO]; }

/// 群邀请链接（点 1）：与群二维码同源（`/q/g/<token>`）同权限，复用二维码卡片页（asLink=YES 只改标题/文案）——
/// 卡片页含「复制链接 / 分享」，链接即码。perm_invite=1 时对非管理员隐藏，点到也在此二次拦（中文吐司）。
- (void)openGroupInviteLink { [self pushGroupCardAsLink:YES]; }

/// 群二维码 / 群邀请链接同源同权限，仅呈现文案不同——收口为一处（asLink 决定标题与拦截文案）。
- (void)pushGroupCardAsLink:(BOOL)asLink {
    if (self.group.permInvite && ![self canManageGroup]) {
        [self im_showToast:(asLink ? @"群主已开启「仅管理员可邀请」，你无法获取群邀请链接"
                                   : @"群主已开启「仅管理员可邀请」，你无法出示群二维码")];
        return;
    }
    IMQRCardViewController *vc = [[IMQRCardViewController alloc] initGroupCardWithHost:self.host userID:self.userID
                                                                              convID:self.convID groupName:self.group.name
                                                                           avatarURL:self.group.avatarURL
                                                                         memberCount:self.group.memberCount
                                                                            canReset:[self canManageGroup] asLink:asLink];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 打开媒体 / 链接 / 返回

#pragma mark - 媒体 / 文件 Tab 的下载（M4-7，草图 §04）

/// 与聊天页共用同一套编排：同一份文件在两处**共享一个下载态与进度**（key 都是 content）。
- (IMMediaDownloadCoordinator *)downloads {
    if (!_downloads) {
        _downloads = [[IMMediaDownloadCoordinator alloc] initWithHost:self.host
                                                             myUserID:self.userID
                                                              isGroup:self.isGroup];
        _downloads.autoPrefetchEnabled = NO; // 浏览历史媒体不该顺手把几十条视频拉下来；这里只反映状态
        __weak typeof(self) ws = self;
        // 高频进度 → 就地更新（宫格只刷那一格 cell、文件行只改 cell）；绝不 reload（否则内嵌 CollectionView 卡死）。
        _downloads.onProgress = ^(IMMessageModel *m, IMDownloadProgress *state) { [ws updateDownloadCellForMessage:m state:state]; };
        // 低频（下载完成）→ reload 让 cell 重配（媒体格重拉清晰图 / 文件行回类型图标 + ⋯）。
        _downloads.onStateChanged = ^(IMMessageModel *m) { [ws refreshDownloadRowForMessage:m]; };
    }
    return _downloads;
}

- (nullable IMMessageModel *)mediaMessageAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabMediaMessages.count) { return nil; }
    return self.tabMediaMessages[index];
}

/// 进度**就地更新**（不 reload）：媒体页刷那一格、文件页刷那一行的可见 cell。
- (void)updateDownloadCellForMessage:(IMMessageModel *)m state:(IMDownloadProgress *)state {
    if (self.tabs.count == 0) { return; }
    IMChatDetailTab *t = self.tabs[self.selectedTab];
    if (t.kind == IMDetailTabKindMedia) {
        NSUInteger i = [self.tabMediaMessages indexOfObjectIdenticalTo:m];
        if (i != NSNotFound) { [self.mediaContainerCell updateItemAtIndex:(NSInteger)i download:state]; }
        return;
    }
    if (t.kind != IMDetailTabKindFiles) { return; }
    NSInteger section = [self indexOfSection:IMDetailSectionTabs];
    if (section == NSNotFound) { return; }
    NSUInteger row = [self.tabRows indexOfObjectIdenticalTo:m];
    if (row == NSNotFound || (NSInteger)row >= [self.tableView numberOfRowsInSection:section]) { return; }
    IMDetailFileCell *cell = (IMDetailFileCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:section]];
    if ([cell isKindOfClass:IMDetailFileCell.class]) { [cell updateDownload:state]; }
}

/// 定点刷新：媒体页只刷那一格（内嵌 CollectionView 整行重建代价高），文件页刷那一行。
- (void)refreshDownloadRowForMessage:(IMMessageModel *)m {
    if (self.tabs.count == 0) { return; }
    IMChatDetailTab *t = self.tabs[self.selectedTab];
    NSInteger section = [self indexOfSection:IMDetailSectionTabs];
    if (section == NSNotFound) { return; }
    if (t.kind == IMDetailTabKindMedia) {
        NSUInteger i = [self.tabMediaMessages indexOfObjectIdenticalTo:m];
        if (i != NSNotFound) { [self.mediaContainerCell refreshItemAtIndex:(NSInteger)i]; }
        return;
    }
    if (t.kind != IMDetailTabKindFiles) { return; }
    NSUInteger row = [self.tabRows indexOfObjectIdenticalTo:m];
    if (row == NSNotFound || (NSInteger)row >= [self.tableView numberOfRowsInSection:section]) { return; }
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)row inSection:section]]
                          withRowAnimation:UITableViewRowAnimationNone];
}

/// 已下载的文件 → 本地 QuickLook 预览（走三处共用的 IMFilePreviewPresenter；由用户点触发，绝不自动打开）。
- (void)openCachedFileForMessage:(IMMessageModel *)m {
    [IMFilePreviewPresenter presentURL:[self.downloads localFileForMessage:m] fromViewController:self];
}

#pragma mark - 文件行长按菜单：转发 / 删除 / 定位到聊天

/// 逐行内容页签（文件/语音/链接，均 tabRows 逐行）某行对应的消息（越界/媒体·成员页返回 nil）。
/// 任务2：这三类页签的长按菜单与文件行一致；媒体走宫格逐格菜单、成员走成员菜单，各不在此。
- (nullable IMMessageModel *)contentRowMessageAtIndexPath:(NSIndexPath *)ip {
    if ([self sectionKindAt:ip.section] != IMDetailSectionTabs || self.tabs.count == 0) { return nil; }
    IMDetailTabKind kind = self.tabs[self.selectedTab].kind;
    if (kind != IMDetailTabKindFiles && kind != IMDetailTabKindVoice && kind != IMDetailTabKindLinks && kind != IMDetailTabKindContacts) { return nil; }
    if (ip.row < 0 || ip.row >= (NSInteger)self.tabRows.count) { return nil; }
    return self.tabRows[ip.row];
}

/// 详情内容长按菜单（任务2）：转发 / 定位到聊天 / [取消下载·仅进行中] / 删除（两档 sheet）。
/// **文件·语音·链接行 + 媒体宫格逐格共用**（成员页除外）。仅对真实消息（convSeq>0）给菜单。
- (nullable UIContextMenuConfiguration *)contentMenuConfigForMessage:(IMMessageModel *)m {
    if (!m || m.convSeq <= 0) { return nil; }
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *sug) {
        NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
        [items addObject:[UIAction actionWithTitle:@"转发" image:[UIImage systemImageNamed:@"arrowshape.turn.up.right"]
                                        identifier:nil handler:^(UIAction *a) { [ws forwardFileMessage:m]; }]];
        [items addObject:[UIAction actionWithTitle:@"定位到聊天" image:[UIImage systemImageNamed:@"bubble.left.and.text.bubble.right"]
                                        identifier:nil handler:^(UIAction *a) { [ws locateFileMessageInChat:m]; }]];
        IMDownloadProgress *dp = [ws.downloads stateForMessage:m];
        if (dp.phase == IMDownloadPhaseDownloading || dp.phase == IMDownloadPhasePaused) {
            [items addObject:[UIAction actionWithTitle:@"取消下载" image:[UIImage systemImageNamed:@"xmark.circle"]
                                            identifier:nil handler:^(UIAction *a) { [ws.downloads cancelDownloadForMessage:m]; }]];
        }
        // 删除（任务2，两档，对齐聊天页）：可为所有人删 → 原生子菜单【为所有人删除】+【仅删除自己】（点开有 push 过渡）；
        // 否则「删除」= 仅删除自己。不再用居中 actionSheet。
        if ([ws canDeleteForEveryone:m]) {
            UIAction *selfOnly = [UIAction actionWithTitle:@"仅删除自己" image:[UIImage systemImageNamed:@"trash"]
                                               identifier:nil handler:^(UIAction *a) { [ws hideMessageForSelf:m]; }];
            selfOnly.attributes = UIMenuElementAttributesDestructive;
            UIAction *everyone = [UIAction actionWithTitle:@"为所有人删除" image:[UIImage systemImageNamed:@"trash"]
                                               identifier:nil handler:^(UIAction *a) { [ws deleteMessageForEveryone:m]; }];
            everyone.attributes = UIMenuElementAttributesDestructive;
            // 破坏性重的「为所有人删除」放最后（destructive-last，与本仓菜单约定一致）。
            [items addObject:[UIMenu menuWithTitle:@"删除" image:[UIImage systemImageNamed:@"trash"]
                                        identifier:nil options:0 children:@[selfOnly, everyone]]];
        } else {
            UIAction *del = [UIAction actionWithTitle:@"删除" image:[UIImage systemImageNamed:@"trash"]
                                           identifier:nil handler:^(UIAction *a) { [ws hideMessageForSelf:m]; }];
            del.attributes = UIMenuElementAttributesDestructive;
            [items addObject:del];
        }
        return [UIMenu menuWithTitle:@"" children:items];
    }];
}

/// 导航栈里承载本会话的聊天页（详情页通常从它 push 而来）。转发/定位复用它的现成逻辑。
/// 与统一入口共用同一份查找口径（IMChatViewController +existingChatForConvID:），避免各处自行遍历方向不一致。
- (nullable IMChatViewController *)originChatInStack {
    return [IMChatViewController existingChatForConvID:self.convID
                               inNavigationController:self.navigationController];
}

/// 转发：复用聊天页 IMChatViewController 的转发选择+回声逻辑（present 由本页发起，呈现上下文正确）。
/// stripCaption=YES：资料页文件 tab 只显示文件名，看不到源消息的 caption/mentions；若透传会把当年
/// 原发件人贴在同一条文件上的「@xxx 附言」意外带到目标会话（曾出现「转发 pdf 却带 @4501 附言」）。
/// 主流长按转发/查看器转发/多选批量/收藏等看得见附言的入口不受影响，仍走 Telegram 式保留。
- (void)forwardFileMessage:(IMMessageModel *)m {
    IMChatViewController *chat = [self originChatInStack];
    if (chat) { [chat presentForwardPickerForMessage:m fromViewController:self stripCaption:YES]; }
    else { [self im_showToast:@"请回到聊天页转发"]; } // 详情页非从聊天进入（如通讯录），无聊天上下文
}

/// 定位到聊天：pop 回本会话聊天页并滚到该消息高亮一闪。
- (void)locateFileMessageInChat:(IMMessageModel *)m {
    IMChatViewController *chat = [self originChatInStack];
    if (!chat) { [self im_showToast:@"请回到聊天页查看"]; return; }
    if (m.convSeq <= 0) { [self im_showToast:@"该消息无法定位"]; return; }
    int64_t seq = m.convSeq;
    [self.navigationController popToViewController:chat animated:YES];
    // pop 动画进行中滚动会被转场吞掉/落错位（dispatch_async 只是下一轮 runloop，仍在动画中）。
    // 挂在转场协调器的完成回调上，等 pop 真正落定再跳；无协调器（罕见）回落下一轮 runloop。
    id<UIViewControllerTransitionCoordinator> tc = self.navigationController.transitionCoordinator;
    if (tc) {
        [tc animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
            [chat jumpToConvSeq:seq];
        }];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ [chat jumpToConvSeq:seq]; });
    }
}

/// 删除文件（任务2，两档，参照 Telegram/主流 IM）：
/// 我发的 / 群主·管理员 → 【为所有人删除】(WS msg_op delete，对端也消失) +【仅删除自己】；
/// 他人发的普通成员 → 仅【删除】(=仅删除自己，REST 隐藏 + 多设备同步)。
/// 交互（任务2 优化）：长按菜单里「删除」——可为所有人删时展开**原生子菜单**（为所有人删除/仅删除自己），
/// 否则「删除」=仅删除自己；不再用居中 actionSheet。菜单构造见 contentMenuConfigForMessage:。

/// 我能否为该消息「为所有人删除」：我发的，或群主/管理员。
- (BOOL)canDeleteForEveryone:(IMMessageModel *)m {
    if (m.from.length > 0 && [m.from isEqualToString:self.userID]) { return YES; }
    return self.isGroup && (self.group.myRole == IMGroupRoleOwner || self.group.myRole == IMGroupRoleAdmin);
}

/// 为所有人删除（任务2）：WS msg_op op=delete；服务端广播回经 IMSocketDidRemoveMessageNotification 移除本地。被拒走 reject 通知。
- (void)deleteMessageForEveryone:(IMMessageModel *)m {
    if (m.convSeq <= 0) { return; }
    [[IMSocketManager sharedManager] deleteMessageForEveryoneInConv:(m.convID ?: self.convID) targetConvSeq:m.convSeq];
}

/// 仅删除自己（任务2）：编排（REST hide + 本端移除）收敛在 IMSocketManager，VC 只负责失败 toast。
- (void)hideMessageForSelf:(IMMessageModel *)m {
    if (m.convSeq <= 0) { return; }
    __weak typeof(self) ws = self;
    [[IMSocketManager sharedManager] hideMessageInConv:(m.convID ?: self.convID) targetConvSeq:m.convSeq
                                            completion:^(NSError *error) {
        if (error) { [ws im_showToast:error.localizedDescription ?: @"删除失败"]; }
    }];
}

/// 点媒体格（已就绪项，门控项由 onDownloadItemIndex 拦下先下载）：进分页查看器，翻页范围=本 tab 全部媒体，
/// **不显「媒体库」按钮**（onOpenGallery=nil，避免「媒体 tab→查看器→媒体库→…」死循环）。
- (void)openMediaItem:(IMMediaItem *)item {
    NSArray<IMMediaItem *> *items = self.tabMedia;
    NSUInteger start = [items indexOfObjectIdenticalTo:item];
    if (start == NSNotFound) { // 兜底：单开
        IMMediaViewerViewController *viewer = [IMMediaViewerViewController viewerWithURL:item.url isVideo:item.isVideo
                                                                         preloadedImage:nil onOpenGallery:nil];
        viewer.thumbDataURI = item.thumb;
        [self presentViewController:viewer animated:YES completion:nil];
        return;
    }
    __weak typeof(self) ws = self;
    IMMediaPagerViewController *pager =
        [IMMediaPagerViewController pagerWithCount:items.count startIndex:start
                                      pageProvider:^IMMediaViewerViewController *(NSUInteger index) {
            __strong typeof(ws) self = ws;
            if (!self || index >= items.count) { return nil; }
            IMMediaItem *it = items[index];
            IMMediaViewerViewController *v = [IMMediaViewerViewController viewerWithURL:it.url isVideo:it.isVideo
                                                                       preloadedImage:nil onOpenGallery:nil];
            v.thumbDataURI = it.thumb;
            IMMessageModel *mm = [self mediaMessageAtIndex:(NSInteger)index];
            if (mm) { v.moreActions = [self viewerMoreActionsForMessage:mm]; }
            return v;
        }];
    pager.conversationTitle = self.displayTitle;
    [self presentViewController:pager animated:YES completion:nil];
}

/// 查看器「更多」外部动作（定位/转发）：与本页媒体格长按菜单同源，作用在正确的消息上。
- (NSArray<IMPopoverCardItem *> *)viewerMoreActionsForMessage:(IMMessageModel *)m {
    if (!m || m.convSeq <= 0) { return @[]; }
    __weak typeof(self) ws = self;
    NSMutableArray<IMPopoverCardItem *> *acts = [NSMutableArray array];
    [acts addObject:[IMPopoverCardItem itemWithTitle:@"定位到聊天" symbol:@"text.bubble" destructive:NO
                                             handler:^{ [ws locateFileMessageInChat:m]; }]];
    [acts addObject:[IMPopoverCardItem itemWithTitle:@"转发" symbol:@"arrowshape.turn.up.right" destructive:NO
                                             handler:^{ [ws forwardFileMessage:m]; }]];
    [acts addObject:[IMPopoverCardItem itemWithTitle:@"删除" symbol:@"trash" destructive:YES
                                             handler:^{ [ws confirmDeleteMediaMessage:m]; }]];
    return acts;
}

/// 查看器「更多」里的删除（IMPopoverCard 扁平列表 → action sheet 承载两档）：可为所有人删=弹两档；否则=仅删除自己。
- (void)confirmDeleteMediaMessage:(IMMessageModel *)m {
    if (!m || m.convSeq <= 0) { return; }
    if (![self canDeleteForEveryone:m]) { [self hideMessageForSelf:m]; return; }
    __weak typeof(self) ws = self;
    // 「更多」先关查看器再执行，此刻可见的是本页；与聊天页不同，本页没有全屏媒体库入口，self 必可见。
    UIViewController *presenter = [UIViewController im_topVisibleViewController] ?: self;
    [presenter im_presentDeleteChoiceSheetWithSelfOnly:^{ [ws hideMessageForSelf:m]; }
                                              everyone:^{ [ws deleteMessageForEveryone:m]; }];
}
/// 应用内浏览器打开链接（SFSafariViewController，仅接受 http/https；与聊天页 openLink: 一致）。
/// 层3：本站邀请链接（/q/u、/q/g）先走扫码同款 resolve+路由，不出 App。
- (void)openLink:(NSString *)url {
    if ([IMQRResultRouter routeInviteLinkIfOwn:url host:self.host userID:self.userID fromController:self]) { return; }
    NSURL *u = [NSURL URLWithString:url ?: @""];
    if (!u || !([u.scheme isEqualToString:@"http"] || [u.scheme isEqualToString:@"https"])) { return; }
    SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:u];
    [self presentViewController:safari animated:YES completion:nil];
}
- (void)headerActionTapped {
    if (self.isGroup) { [self openGroupManage]; }
    else { [self editRemark]; }
}
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar {
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar {
    [self headerActionTapped];
}
- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar {
    [self liquidNavigationBarDidTapBack:bar];
}
- (void)goBack { [self.navigationController popViewControllerAnimated:YES]; }

@end
