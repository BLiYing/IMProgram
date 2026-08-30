//  IMGroupAdminListViewController.m

#import "IMGroupAdminListViewController.h"
#import "IMGroupAdminLogic.h"
#import "IMGroupManageRowIcon.h"
#import "IMDetailMemberCell.h"
#import "IMGroupInfo.h"
#import "IMFriendPickerViewController.h"
#import "IMChatDetailViewController.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"

typedef NS_ENUM(NSInteger, IMAdminSection) {
    IMAdminSecOwner = 0, ///< 群主（只读一行）
    IMAdminSecAdmins,    ///< 「添加管理员」（仅群主）+ 管理员行 / 空态占位
    IMAdminSecCount,
};

@interface IMGroupAdminListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, strong) IMGroupInfo *group;
@property (nonatomic, copy, nullable) void (^onChanged)(void);
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<IMGroupMember *> *admins; ///< 派生自 group.members，随刷新重算
@end

@implementation IMGroupAdminListViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID convID:(NSString *)convID
                       group:(IMGroupInfo *)group onChanged:(void (^)(void))onChanged {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy]; _userID = [userID copy]; _convID = [convID copy];
        _group = group; _onChanged = [onChanged copy];
        _admins = [IMGroupAdminLogic adminsFromMembers:group.members];
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"管理员";
    self.view.backgroundColor = IMTheme.groupedBackground;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 60;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:IMDetailMemberCell.class forCellReuseIdentifier:@"m"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    // 角色随时可能被另一台设备/管理端改掉，本页就是"一屏角色"，必须实时跟。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onGroupEvent:)
                                               name:IMSocketDidReceiveGroupEventNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload]; // 从选人页回来 / 从后台回前台：一律以服务端为准（不做乐观更新）
}

- (BOOL)isOwner { return self.group.myRole == IMGroupRoleOwner; }

#pragma mark - 数据

/// 重拉群资料 → 重算派生 → 刷新。
/// 网络抖动等**静默保留上一份快照**（每次 viewWillAppear 都吐一次司很吵，且旧数据比空白有用）；
/// 只有"这一页对我已不成立"（群没了 / 我不在群里 / 我已不是群主或管理员）才提示并退页。
- (void)reload {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService groupInfoWithToken:token convID:self.convID
                                         completion:^(IMGroupInfo *group, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || !group) {
            if (error.code == 300201 || error.code == 300203) {
                [self popWithToast:[IMGroupAdminLogic toastForError:error]];
            }
            return;
        }
        if (!group.canManage) { // 我被撤职 / 群主身份被别处转走：整页只对群主与管理员开放
            [self popWithToast:@"你已不是群主或管理员"];
            return;
        }
        self.group = group;
        self.admins = [IMGroupAdminLogic adminsFromMembers:group.members];
        [self.tableView reloadData];
    }];
}

/// 退回**本页下面那一页**，并把吐司挂落地页。
/// 两点都不能省：① 必须 `popToViewController:` 而不是 `popViewControllerAnimated:`——本页未必在栈顶
/// （群解散时本页与管理员列表页会各自收到同一条群事件，弹栈顶就会把对方弹掉、自己留在失效页上）；
/// ② 吐司挂落地页——挂本页等于让它随退场动画一起消失。
- (void)popWithToast:(NSString *)text {
    NSArray<UIViewController *> *stack = self.navigationController.viewControllers;
    NSUInteger idx = [stack indexOfObject:self];
    UIViewController *back = (idx != NSNotFound && idx > 0) ? stack[idx - 1] : nil;
    if (back) {
        [self.navigationController popToViewController:back animated:YES];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
    [(back ?: self) im_showToast:text];
}

/// 群事件：本群才理。被移出 / 群解散 → 本页对我不再成立，退回上一页；其余（含 role/transfer）重拉。
- (void)onGroupEvent:(NSNotification *)note {
    if (![note.userInfo[kIMConvIDKey] isEqualToString:self.convID]) { return; }
    NSString *event = note.userInfo[kIMGroupEventKey];
    NSString *target = note.userInfo[kIMGroupTargetKey];
    BOOL removedMe = [event isEqualToString:@"remove"] && [target isEqualToString:self.userID];
    if (removedMe || [event isEqualToString:@"dissolve"]) {
        [self popWithToast:removedMe ? @"你已不在该群" : @"该群已被解散"];
        return;
    }
    [self reload];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return IMAdminSecCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == IMAdminSecOwner) { return [IMGroupAdminLogic ownerFromMembers:self.group.members] ? 1 : 0; }
    NSInteger rows = (NSInteger)self.admins.count;
    if (rows == 0) { rows = 1; }                 // 空态占位「还没有管理员」
    return rows + (self.isOwner ? 1 : 0);        // 首行「添加管理员」仅群主
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == IMAdminSecOwner) { return @"群主"; }
    return [NSString stringWithFormat:@"管理员 · %lu", (unsigned long)self.admins.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != IMAdminSecAdmins) { return nil; }
    if (!self.isOwner) { return @"只有群主可以增减管理员。"; }
    return self.admins.count > 0
        ? @"左滑可撤销管理员身份。管理员可审批入群、禁言与移出普通成员，但不能设置管理员或转让群组。"
        : @"管理员可审批入群、禁言与移出普通成员，但不能设置管理员或转让群组。";
}

/// 该行是不是「添加管理员」入口行。
- (BOOL)isAddRow:(NSIndexPath *)ip {
    return ip.section == IMAdminSecAdmins && self.isOwner && ip.row == 0;
}

/// 该行对应的管理员（「添加」行/空态占位返回 nil）。
- (nullable IMGroupMember *)adminAt:(NSIndexPath *)ip {
    if (ip.section != IMAdminSecAdmins || [self isAddRow:ip]) { return nil; }
    NSInteger idx = ip.row - (self.isOwner ? 1 : 0);
    if (idx < 0 || idx >= (NSInteger)self.admins.count) { return nil; } // 空态占位行
    return self.admins[idx];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == IMAdminSecOwner) {
        IMDetailMemberCell *cell = [tableView dequeueReusableCellWithIdentifier:@"m" forIndexPath:indexPath];
        IMGroupMember *owner = [IMGroupAdminLogic ownerFromMembers:self.group.members];
        [cell configureWithMember:owner isMe:[owner.userID isEqualToString:self.userID]];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    if ([self isAddRow:indexPath]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"c" forIndexPath:indexPath];
        cell.textLabel.text = @"添加管理员";
        cell.textLabel.textColor = IMTheme.accent;
        cell.imageView.image = IMGroupManageRowIcon(@"person.badge.plus");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    IMGroupMember *m = [self adminAt:indexPath];
    if (!m) { // 空态占位
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"c" forIndexPath:indexPath];
        cell.textLabel.text = @"还没有管理员";
        cell.textLabel.textColor = IMTheme.textSecondary;
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    IMDetailMemberCell *cell = [tableView dequeueReusableCellWithIdentifier:@"m" forIndexPath:indexPath];
    [cell configureWithMember:m isMe:[m.userID isEqualToString:self.userID]];
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    // 「添加管理员」与空态占位是普通设置行（44），成员行是 60。
    return ([self isAddRow:indexPath] || (indexPath.section == IMAdminSecAdmins && ![self adminAt:indexPath])) ? 44 : 60;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isAddRow:indexPath]) { [self openAdminPicker]; return; }
    IMGroupMember *m = indexPath.section == IMAdminSecOwner
        ? [IMGroupAdminLogic ownerFromMembers:self.group.members]
        : [self adminAt:indexPath];
    [self openPeerDetail:m];
}

/// 左滑撤销（仅群主，且只对管理员行）。
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.isOwner) { return nil; }
    IMGroupMember *m = [self adminAt:indexPath];
    if (!m) { return nil; }
    __weak typeof(self) ws = self;
    UIContextualAction *revoke = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"撤销" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [ws confirmRevoke:m];
        done(YES); // 关掉滑动态，真正的成败由二次确认后的请求决定
    }];
    revoke.image = [UIImage systemImageNamed:@"person.badge.minus"];
    return [UISwipeActionsConfiguration configurationWithActions:@[revoke]];
}

/// 长按菜单：查看资料 / 撤销管理员（与详情页成员菜单同族）。
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    IMGroupMember *m = indexPath.section == IMAdminSecOwner
        ? [IMGroupAdminLogic ownerFromMembers:self.group.members]
        : [self adminAt:indexPath];
    if (!m) { return nil; }
    BOOL canRevoke = self.isOwner && m.role == IMGroupRoleAdmin;
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
        [items addObject:[UIAction actionWithTitle:@"查看资料"
                                             image:[UIImage systemImageNamed:@"person.crop.circle"]
                                        identifier:nil handler:^(UIAction *a) { [ws openPeerDetail:m]; }]];
        if (canRevoke) {
            UIAction *revoke = [UIAction actionWithTitle:@"撤销管理员"
                                                   image:[UIImage systemImageNamed:@"person.badge.minus"]
                                              identifier:nil handler:^(UIAction *a) { [ws confirmRevoke:m]; }];
            revoke.attributes = UIMenuElementAttributesDestructive;
            [items addObject:revoke];
        }
        return [UIMenu menuWithTitle:m.localDisplayName children:items];
    }];
}

#pragma mark - 动作

/// 打开成员资料页（与详情页成员行点击同一落点）。点自己不进（那是"编辑资料"的事）。
- (void)openPeerDetail:(IMGroupMember *)m {
    if (!m || [m.userID isEqualToString:self.userID]) { return; }
    IMChatDetailViewController *vc = [[IMChatDetailViewController alloc] initSingleWithHost:self.host userID:self.userID
                                                                                     peerID:m.userID
                                                                               peerNickname:m.displayName
                                                                              peerAvatarURL:m.avatarURL];
    vc.showsMessagePill = YES;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)confirmRevoke:(IMGroupMember *)m {
    NSString *name = m.localDisplayName; // 备注优先，本机渲染（发出去的只有 uid）
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"撤销管理员"
                                                                  message:[NSString stringWithFormat:@"撤销 %@ 的管理员身份？", name]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"撤销" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [ws setRole:@"member" forUserID:m.userID successToast:@"已撤销管理员"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 单个角色变更：成功 → 重拉刷新 + 通知上一页（**不做乐观更新**，角色即权限）。
- (void)setRole:(NSString *)role forUserID:(NSString *)uid successToast:(NSString *)toast {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self im_showToast:@"未登录"]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService setGroupRoleWithToken:token convID:self.convID userID:uid role:role
                                            completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:[IMGroupAdminLogic toastForError:error]]; return; }
        [self im_showToast:toast];
        [self reload];
        if (self.onChanged) { self.onChanged(); }
    }];
}

/// 添加管理员：候选＝本群普通成员（排除群主/现有管理员/我），一次 ≤5 人，串行下发。
- (void)openAdminPicker {
    NSArray<IMGroupMember *> *candidates = [IMGroupAdminLogic adminCandidatesFromMembers:self.group.members
                                                                                myUserID:self.userID];
    __weak typeof(self) ws = self;
    // onDone 回调时选人页仍在最上层：全失败要「停在选人页」，吐司就得挂它——挂本页等于画在看不见的地方。
    __block __weak IMFriendPickerViewController *wsPicker = nil;
    IMFriendPickerViewController *picker =
        [[IMFriendPickerViewController alloc] initWithHost:self.host userID:self.userID
                                                candidates:[IMGroupAdminLogic pickerCardsFromMembers:candidates]
                                               excludedIDs:nil
                                                     title:@"添加管理员"
                                              confirmTitle:@"确定"
                                                    onDone:^(NSArray<NSString *> *selectedIDs) {
        [ws addAdmins:[IMGroupAdminLogic clampBatchSelection:selectedIDs] host:wsPicker];
    }];
    wsPicker = picker;
    picker.maxSelection = IMGroupAdminMaxBatch;
    picker.capToast = [NSString stringWithFormat:@"一次最多添加 %lu 位管理员", (unsigned long)IMGroupAdminMaxBatch];
    picker.searchPlaceholder = @"搜索群成员";
    picker.emptyText = @"群里还没有其他成员";
    [self.navigationController pushViewController:picker animated:YES];
}

/// 串行逐个 PUT role（后端无批量接口；并发会让系统消息乱序），逐条汇总成败。
/// host = 选人页（发起这次批量的那一页），全失败时吐司挂它并停在原地。
- (void)addAdmins:(NSArray<NSString *> *)uids host:(nullable UIViewController *)host {
    if (uids.count == 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [(host ?: self) im_showToast:@"未登录"]; return; }
    [self runAddAdmins:uids index:0 token:token succeeded:0 failed:0 firstError:nil host:host];
}

- (void)runAddAdmins:(NSArray<NSString *> *)uids index:(NSUInteger)i token:(NSString *)token
           succeeded:(NSUInteger)ok failed:(NSUInteger)bad firstError:(nullable NSString *)firstError
                host:(nullable UIViewController *)host {
    if (i >= uids.count) {
        NSString *toast = [IMGroupAdminLogic batchToastWithSucceeded:ok failed:bad firstError:firstError];
        if (ok == 0) {
            // 全失败：停在选人页，让用户换个人或退回去重来（§4.2）。
            [(host ?: self) im_showToast:toast];
            return;
        }
        // 成功一个就得刷（那几位已生效，部分失败也一样）。**先弹回本页再吐司**——
        // 吐司挂 self.view，弹回之前本页还不可见，先吐就等于吐给空气。
        [self.navigationController popToViewController:self animated:YES];
        [self im_showToast:toast];
        [self reload];
        if (self.onChanged) { self.onChanged(); }
        return;
    }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService setGroupRoleWithToken:token convID:self.convID userID:uids[i] role:@"admin"
                                            completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        NSString *nextFirstError = firstError;
        if (error && nextFirstError == nil) { nextFirstError = [IMGroupAdminLogic toastForError:error]; }
        [self runAddAdmins:uids index:i + 1 token:token
                 succeeded:ok + (error ? 0 : 1) failed:bad + (error ? 1 : 0) firstError:nextFirstError host:host];
    }];
}

@end
