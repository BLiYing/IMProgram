//  IMContactsViewController.m

#import "IMContactsViewController.h"
#import "IMUserSearchViewController.h"
#import "IMGroupListViewController.h"
#import "IMContactCells.h"
#import "IMContactSectionIndex.h"
#import "IMChatDetailViewController.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMReconnectReloader.h"
#import "IMUserCard.h"
#import "IMDatabase.h"
#import "IMMenuAction.h"
#import "IMAnimator.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMLog.h"

#pragma mark - 顶部入口 Cell（彩色图标 + 标题 + chevron）

@interface IMContactEntryCell : UITableViewCell
- (void)configureWithAction:(IMMenuAction *)action iconBg:(UIColor *)iconBg;
@end

@implementation IMContactEntryCell {
    UIImageView *_iconView;
    UIView *_iconBg;
    UILabel *_title;
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
            [_title.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        ]];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}
- (void)configureWithAction:(IMMenuAction *)action iconBg:(UIColor *)iconBg {
    _title.text = action.title;
    _iconView.image = action.systemImageName.length > 0 ? [UIImage systemImageNamed:action.systemImageName] : nil;
    _iconBg.backgroundColor = iconBg;
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
@property (nonatomic, strong, nullable) IMDatabaseAccountContext *databaseContext; // 任务5：本地缓存账号隔离
@property (nonatomic, strong) IMReconnectReloader *reconnectReloader;              // 重连即取权威（可见时）
@end

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
        _pending = @[];              // 待处理申请不落库（易变，以服务端为准），联网后由 applyFriends 补上
        _accepted = cachedFriends;   // 好友种子（离线首屏）
        _friendIndex = [[IMContactSectionIndex alloc] initWithCards:cachedFriends]; // 种子也分组，离线首屏即带索引
        [self buildEntries];
        // 实时好友事件：即使没在通讯录页，也据此刷新（Tab 角标随之亮/灭，无需切页）。
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onFriendEvent)
                                                   name:IMSocketDidReceiveFriendEventNotification object:nil];
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
        [IMMenuAction actionWithId:@"officialAccount" title:@"公众号" image:@"megaphone.fill" handler:^{ [ws im_showComingSoon:@"公众号"]; }],
        [IMMenuAction actionWithId:@"serviceAccount" title:@"服务号" image:@"headphones" handler:^{ [ws im_showComingSoon:@"服务号"]; }],
    ];
    self.entryColors = @[UIColor.systemGreenColor, UIColor.systemOrangeColor, UIColor.systemBlueColor];
}

/// 收到好友事件 → 节流刷新（合并连发，避免每帧一次登录+拉取）。
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
    [self.tableView registerClass:IMContactRequestCell.class forCellReuseIdentifier:@"request"];
    [self.tableView registerClass:IMContactEntryCell.class forCellReuseIdentifier:@"entry"];
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
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            IMLog(@"通讯录刷新登录失败（保留当前内容）：%@", error.localizedDescription ?: @"未知错误");
            return;
        }
        self.token = token;
        [IMHTTPService.sharedService friendsWithToken:token status:nil completion:^(NSArray<IMUserCard *> *friends, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (err) {
                IMLog(@"通讯录刷新失败（保留当前内容）：%@", err.localizedDescription ?: @"未知错误");
                return;
            }
            [self applyFriends:friends ?: @[]];
        }];
    }];
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
    self.friendIndex = [[IMContactSectionIndex alloc] initWithCards:accepted]; // 排序/分桶交给索引
    self.emptyLabel.hidden = (pending.count + accepted.count) > 0;
    [self.tableView reloadData];
    // 任务5：权威好友列表落库（仅 accepted），供下次断网离线首屏。空数组也写，代表当前账号无好友。
    [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:^(IMDatabase *database) {
        [database replaceCachedFriends:accepted];
    }];
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
                                                  peerNickname:card.displayName
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

// 分区布局：section 0 = 顶部入口（始终存在）；有待处理申请时 section 1 = 新的朋友；
// 其后接 N 个「好友 A–Z 字母分组」（由 friendIndex 提供）。下面以语义谓词判断，避免散落魔法下标。

/// 顶部入口区永远是 section 0。
- (BOOL)isEntriesSection:(NSInteger)section { return section == 0; }
/// 是否有"新的朋友"分区。
- (BOOL)hasRequestsSection { return self.pending.count > 0; }
/// "新的朋友"分区（存在时固定为 section 1）。
- (BOOL)isRequestsSection:(NSInteger)section {
    return [self hasRequestsSection] && section == 1;
}
/// 好友字母分组的起始 section（入口 + 可选新的朋友之后）。
- (NSInteger)friendsBaseSection { return 1 + ([self hasRequestsSection] ? 1 : 0); }
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
    if ([self isRequestsSection:section]) { return (NSInteger)self.pending.count; }
    return [self.friendIndex numberOfRowsInSection:[self friendLocalSection:section]];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self isEntriesSection:section]) { return nil; }
    if ([self isRequestsSection:section]) {
        return [NSString stringWithFormat:@"新的朋友（%lu）", (unsigned long)self.pending.count];
    }
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
        [cell configureWithAction:self.entries[indexPath.row] iconBg:self.entryColors[indexPath.row]];
        return cell;
    }
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
    IMUserCard *c = [self.friendIndex cardAtSection:[self friendLocalSection:indexPath.section] row:indexPath.row];
    // 拉黑≠解绑：被拉黑的好友仍在列表，副标题标注"已拉黑"以区分。
    NSString *subtitle = c.blocked ? [NSString stringWithFormat:@"%@ · 已拉黑", c.userID] : c.userID;
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
    if ([self isRequestsSection:indexPath.section]) { return; } // 申请行靠按钮操作，不整行点击
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
