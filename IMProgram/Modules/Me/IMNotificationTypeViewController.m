//  IMNotificationTypeViewController.m

#import "IMNotificationTypeViewController.h"
#import "IMNotificationSoundViewController.h"
#import "IMNotificationSettings.h"
#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMHTTPService.h"
#import "IMChatViewController.h"
#import "IMForwardPickerViewController.h"
#import "IMNotifExceptionPickerFilter.h"
#import "IMMuteState.h"
#import "IMMuteDurationMenu.h"
#import "IMMuteExpiryScheduler.h"
#import "IMTimeUtil.h"
#import "UIViewController+IMToast.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"
#import "IMLocalization.h"
#import "IMLog.h"

typedef NS_ENUM(NSInteger, IMNotifTypeSection) {
    IMNotifTypeSectionToggles = 0,
    IMNotifTypeSectionSound,
    IMNotifTypeSectionExceptions,
};

#pragma mark - 开关行 Cell

@interface IMNotifSwitchCell : UITableViewCell
@property (nonatomic, copy) void (^onChange)(BOOL on);
- (void)configureWithTitle:(NSString *)title on:(BOOL)on dimmed:(BOOL)dimmed;
@end

@implementation IMNotifSwitchCell {
    UISwitch *_toggle;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _toggle = [UISwitch new];
        [_toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        self.accessoryView = _toggle;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}
- (void)configureWithTitle:(NSString *)title on:(BOOL)on dimmed:(BOOL)dimmed {
    self.textLabel.text = title;
    self.textLabel.textColor = dimmed ? IMTheme.textSecondary : IMTheme.textPrimary; // §2.3：关掉「显示通知」后下方两行灰置但保留、可操作
    _toggle.on = on;
}
- (void)toggled:(UISwitch *)sender {
    if (self.onChange) { self.onChange(sender.on); }
}
@end

#pragma mark - 「标题 + 右值 + chevron」行 Cell（强制 Value1 样式，registerClass: 默认走 Default 样式没有 detailTextLabel）

@interface IMNotifValueCell : UITableViewCell
@end
@implementation IMNotifValueCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
}
@end

#pragma mark - 例外行 Cell（头像 40 / 名字 17 / 右值次要色，§4）

@interface IMNotifExceptionCell : UITableViewCell
- (void)configureWithConversation:(IMConversation *)conversation;
@end

@implementation IMNotifExceptionCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_value;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 20;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:17];
        _name.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_name];

        _value = [UILabel new];
        _value.translatesAutoresizingMaskIntoConstraints = NO;
        _value.font = [UIFont systemFontOfSize:15];
        _value.textColor = IMTheme.textSecondary;
        _value.textAlignment = NSTextAlignmentRight;
        [_value setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_value];

        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:40],
            [_avatar.heightAnchor constraintEqualToConstant:40],
            [_avatar.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [_avatar.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],

            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:IMTheme.space3],
            [_name.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

            [_value.leadingAnchor constraintGreaterThanOrEqualToAnchor:_name.trailingAnchor constant:IMTheme.space2],
            [_value.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [_value.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}
- (void)configureWithConversation:(IMConversation *)conversation {
    NSString *display = conversation.displayName;
    NSString *avatarURL = conversation.isGroup ? conversation.avatarURL : conversation.peerAvatarURL;
    NSString *seed = conversation.isGroup ? conversation.convID : conversation.peer;
    [_avatar im_setAvatarURL:avatarURL seed:seed displayName:display];
    _name.text = display;
    // 例外列表本身就是"有效免打扰"的会话集合（reloadExceptions 已按 IMIsMutedNow 过滤），
    // 这里只需拼「免打扰」/「免打扰至...」+ @我仍提醒变体（P1 §4.1 副标题文案）。
    _value.text = IMMuteExceptionSubtitle(conversation.muteUntil, IMNowMillis(), conversation.mentionUnread);
}
@end

#pragma mark - 「添加例外」行 Cell（绿色圆形 + 号，§2 / 草图 02-A：常驻「例外」组的第一行）

@interface IMNotifAddExceptionCell : UITableViewCell
@end
@implementation IMNotifAddExceptionCell {
    UIView *_circle;
    UILabel *_title;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _circle = [UIView new];
        _circle.translatesAutoresizingMaskIntoConstraints = NO;
        _circle.backgroundColor = IMTheme.accent; // 草图 --app-accent：本端主题绿，非硬编码颜色
        _circle.layer.cornerRadius = 14;
        _circle.layer.masksToBounds = YES;
        [self.contentView addSubview:_circle];

        UIImageView *plus = [UIImageView new];
        plus.translatesAutoresizingMaskIntoConstraints = NO;
        plus.image = [UIImage systemImageNamed:@"plus"];
        plus.tintColor = UIColor.whiteColor;
        plus.contentMode = UIViewContentModeCenter;
        [_circle addSubview:plus];

        _title = [UILabel new];
        _title.translatesAutoresizingMaskIntoConstraints = NO;
        _title.font = [UIFont systemFontOfSize:17];
        _title.textColor = IMTheme.accent;
        _title.text = IMLocalized(@"notif.exceptions.add");
        [self.contentView addSubview:_title];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_circle.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_circle.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_circle.widthAnchor constraintEqualToConstant:28],
            [_circle.heightAnchor constraintEqualToConstant:28],
            [plus.centerXAnchor constraintEqualToAnchor:_circle.centerXAnchor],
            [plus.centerYAnchor constraintEqualToAnchor:_circle.centerYAnchor],
            [_title.leadingAnchor constraintEqualToAnchor:_circle.trailingAnchor constant:IMTheme.space3],
            [_title.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_title.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
        self.accessoryType = UITableViewCellAccessoryNone;
    }
    return self;
}
@end

#pragma mark - 控制器

@interface IMNotificationTypeViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong, nullable) IMDatabaseAccountContext *databaseContext;
@property (nonatomic, copy) NSArray<IMConversation *> *exceptions; // 该类型下 muted=YES 的会话，按最后消息时间倒序
@end

@implementation IMNotificationTypeViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID isGroup:(BOOL)isGroup {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _isGroup = isGroup;
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        _exceptions = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(self.isGroup ? @"notif.type.group_title" : @"notif.type.private_title");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:IMNotifSwitchCell.class forCellReuseIdentifier:@"switch"];
    [self.tableView registerClass:IMNotifValueCell.class forCellReuseIdentifier:@"disclosure"];
    [self.tableView registerClass:IMNotifExceptionCell.class forCellReuseIdentifier:@"exception"];
    [self.tableView registerClass:IMNotifAddExceptionCell.class forCellReuseIdentifier:@"addException"];
    [self.view addSubview:self.tableView];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged)
                                               name:IMNotificationSettingsDidChangeNotification object:nil];
    // 定时免打扰到期 / App 回前台（§4.4）：本页在屏时也要跟着掉出例外列表，不必等下次 viewWillAppear。
    for (NSNotificationName n in @[IMMuteExpiryDidChangeNotification, UIApplicationDidBecomeActiveNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMuteExpiryChanged) name:n object:nil];
    }
}

- (void)onMuteExpiryChanged {
    [self reloadExceptions];
    [self.tableView reloadData];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadExceptions];
    [self.tableView reloadData];
}

- (void)settingsChanged {
    [self.tableView reloadData];
}

- (IMNotificationTypeSettings *)typeSettings {
    return self.isGroup ? IMNotificationSettings.shared.groupType : IMNotificationSettings.shared.privateType;
}

/// 本机会话表里该类型**有效**免打扰（IMIsMutedNow）的会话，按最后消息时间倒序（§3.5）。
/// 定时免打扰到期后要自然从这里消失——不能再直接读 c.muted（§4.3）。
- (void)reloadExceptions {
    __block NSArray<IMConversation *> *cached = @[];
    [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:^(IMDatabase *database) {
        cached = database.cachedConversations;
    }];
    BOOL wantGroup = self.isGroup;
    int64_t now = IMNowMillis();
    NSArray<IMConversation *> *filtered = [cached filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(IMConversation *c, NSDictionary *bindings) {
            return IMIsMutedNow(c.muted, c.muteUntil, now) && c.isGroup == wantGroup;
        }]];
    self.exceptions = [filtered sortedArrayUsingComparator:^NSComparisonResult(IMConversation *a, IMConversation *b) {
        if (a.timestamp == b.timestamp) { return NSOrderedSame; }
        return a.timestamp > b.timestamp ? NSOrderedAscending : NSOrderedDescending;
    }];
    [IMMuteExpiryScheduler.shared rescheduleWithConversations:cached]; // 顺路重排到期定时器（列表页/详情页可能都没打开）
}

#pragma mark - 动作

- (void)enabledChanged:(BOOL)on {
    IMNotificationTypeSettings *type = self.typeSettings;
    // 不再手动 reload：setter 同步发变更通知，本页的 settingsChanged 已整表刷新（再刷一遍是重复功）
    [IMNotificationSettings.shared setEnabled:on preview:type.preview sound:type.sound forGroup:self.isGroup];
}

- (void)previewChanged:(BOOL)on {
    IMNotificationTypeSettings *type = self.typeSettings;
    [IMNotificationSettings.shared setEnabled:type.enabled preview:on sound:type.sound forGroup:self.isGroup];
}

- (void)openSoundPicker {
    IMNotificationSoundViewController *vc = [[IMNotificationSoundViewController alloc] initForGroup:self.isGroup];
    [self.navigationController pushViewController:vc animated:YES];
}

/// 取消免打扰：PUT 整体替换，必须把 pinned_at / marked_unread 原样带回
/// （§3.5，iOS IMChatDetailViewController+Actions 已踩过这个坑，CODING_STYLE §8）。
- (void)unmute:(IMConversation *)conversation atIndexPath:(NSIndexPath *)indexPath {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || conversation.convID.length == 0) { return; }
    __weak typeof(self) ws = self;
    // 取消免打扰须显式带 mute_until=0（不能省略——省略会被服务端解读成"保留原值"，见 PROTOCOL.md §6.10）。
    [IMHTTPService.sharedService updateConversationSettingsWithToken:token convID:conversation.convID
        pinnedAt:conversation.pinnedAt muted:NO muteUntil:@0 markedUnread:conversation.markedUnread
        completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: IMLocalized(@"conv.error.settings_failed")]; return; }
        conversation.muted = NO;
        conversation.muteUntil = 0;
        [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:^(IMDatabase *database) {
            [database applyCachedSettingsForConversation:conversation.convID pinnedAt:conversation.pinnedAt
                                                     muted:NO muteUntil:0 markedUnread:conversation.markedUnread];
        }];
        NSMutableArray<IMConversation *> *mutable = [self.exceptions mutableCopy];
        [mutable removeObject:conversation];
        self.exceptions = mutable;
        // 「例外」组常驻（已拍板 ②，第一期 b4d9c88「没有例外就整组不显示」已随本批改回）：
        // 最后一个也取消了，组里只剩「添加例外」一行，只删这一行，整组不消失。
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }];
}

/// 「添加例外」：复用转发选择页（单选·立即模式），过滤出该类型、还没免打扰、非系统通知的会话；
/// 选中即走「取消免打扰」的镜像操作——设免打扰，同样必须原样带回 pinned_at/marked_unread（§2）。
- (void)addException {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    BOOL wantGroup = self.isGroup;
    int64_t now = IMNowMillis();
    __weak typeof(self) ws = self;
    IMForwardPickerViewController *picker = [[IMForwardPickerViewController alloc]
        initWithHost:self.host token:token onDone:^(NSArray<IMConversation *> *selected) {
        // 选完会话先弹时长菜单，再真正设免打扰（§4.2「选择页」行）；此时 picker 的 nav 已经 dismiss 完，
        // ws（本页）已回到最上层，present 时机安全。
        if (selected.count > 0) { [ws presentMuteMenuForNewException:selected.firstObject]; }
    }];
    picker.immediateSingleSelect = YES;
    picker.titleOverride = IMLocalized(@"notif.exceptions.add");
    picker.footerText = IMLocalized(wantGroup ? @"notif.exceptions.pick_footer_group" : @"notif.exceptions.pick_footer_private");
    picker.emptyText = IMLocalized(@"notif.exceptions.pick_empty");
    picker.extraFilter = ^BOOL(IMConversation *c) {
        return IMNotifExceptionPickerMatches(c.isGroup, IMIsMutedNow(c.muted, c.muteUntil, now), c.peer, wantGroup);
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

/// 选完会话弹时长菜单（不已免打扰，恒不出「取消免打扰」项）。
- (void)presentMuteMenuForNewException:(IMConversation *)conversation {
    __weak typeof(self) ws = self;
    [IMMuteDurationMenu presentFromViewController:self sourceView:nil sourceRect:CGRectZero
        conversationName:conversation.displayName showUnmuteFirst:NO
        completion:^(BOOL unmuted, int64_t muteUntil) {
            if (!unmuted) { [ws muteNewException:conversation muteUntil:muteUntil]; }
        }];
}

- (void)muteNewException:(IMConversation *)conversation muteUntil:(int64_t)muteUntil {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || conversation.convID.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService updateConversationSettingsWithToken:token convID:conversation.convID
        pinnedAt:conversation.pinnedAt muted:YES muteUntil:@(muteUntil) markedUnread:conversation.markedUnread
        completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: IMLocalized(@"conv.error.settings_failed")]; return; }
        conversation.muted = YES;
        conversation.muteUntil = muteUntil;
        [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:^(IMDatabase *database) {
            [database applyCachedSettingsForConversation:conversation.convID pinnedAt:conversation.pinnedAt
                                                     muted:YES muteUntil:muteUntil markedUnread:conversation.markedUnread];
        }];
        [self reloadExceptions];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:IMNotifTypeSectionExceptions]
                       withRowAnimation:UITableViewRowAnimationAutomatic];
    }];
}

- (void)openConversation:(IMConversation *)conversation {
    if (conversation.isGroup) {
        [IMChatViewController openInNavigationController:self.navigationController host:self.host userID:self.userID
                                               groupConvID:conversation.convID groupName:conversation.displayName
                                                   readSeq:conversation.readSeq unread:conversation.unread
                                              groupReadSeq:conversation.groupReadSeq groupAvatarURL:conversation.avatarURL];
    } else {
        [IMChatViewController openInNavigationController:self.navigationController host:self.host userID:self.userID
                                                    peerID:conversation.peer readSeq:conversation.readSeq
                                                    unread:conversation.unread peerReadSeq:conversation.peerReadSeq
                                              peerNickname:conversation.displayName peerAvatarURL:conversation.peerAvatarURL];
    }
}

#pragma mark - UITableView

// 「例外」组常驻（P1 §2 / 已拍板 ②）：第一期「没有免打扰会话就整组不显示」（b4d9c88）随本批改回——
// 组首固定一行绿色「添加例外」，没有免打扰会话时这一组只剩这一行，不再为空。
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((IMNotifTypeSection)section) {
        case IMNotifTypeSectionToggles: return 2;
        case IMNotifTypeSectionSound: return 1;
        case IMNotifTypeSectionExceptions: return 1 + (NSInteger)self.exceptions.count; // 首行「添加例外」+ 各免打扰会话
    }
    return 0;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == IMNotifTypeSectionSound) { return IMLocalized(@"notif.sound.title"); }
    if (section == IMNotifTypeSectionExceptions) { return IMLocalized(@"notif.section.exceptions"); }
    return nil;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == IMNotifTypeSectionToggles) { return IMLocalized(@"notif.type.preview_footer"); }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMNotificationTypeSettings *type = self.typeSettings;
    if (indexPath.section == IMNotifTypeSectionToggles) {
        IMNotifSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"switch" forIndexPath:indexPath];
        __weak typeof(self) ws = self;
        if (indexPath.row == 0) {
            [cell configureWithTitle:IMLocalized(@"notif.type.enabled") on:type.enabled dimmed:NO];
            cell.onChange = ^(BOOL on) { [ws enabledChanged:on]; };
        } else {
            [cell configureWithTitle:IMLocalized(@"notif.type.preview") on:type.preview dimmed:!type.enabled];
            cell.onChange = ^(BOOL on) { [ws previewChanged:on]; };
        }
        return cell;
    }
    if (indexPath.section == IMNotifTypeSectionSound) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"disclosure" forIndexPath:indexPath];
        cell.textLabel.text = IMLocalized(@"notif.type.sound");
        cell.textLabel.textColor = type.enabled ? IMTheme.textPrimary : IMTheme.textSecondary;
        cell.detailTextLabel.text = IMNotificationSoundDisplayName(type.sound);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    // 例外组：row 0 固定「添加例外」，其余是本类型下 muted=YES 的会话（row-1 对应 exceptions 下标）。
    if (indexPath.row == 0) {
        return [tableView dequeueReusableCellWithIdentifier:@"addException" forIndexPath:indexPath];
    }
    IMNotifExceptionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"exception" forIndexPath:indexPath];
    [cell configureWithConversation:self.exceptions[indexPath.row - 1]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == IMNotifTypeSectionSound) { [self openSoundPicker]; return; }
    if (indexPath.section != IMNotifTypeSectionExceptions) { return; }
    if (indexPath.row == 0) { [self addException]; return; }
    NSInteger i = indexPath.row - 1;
    if (i < (NSInteger)self.exceptions.count) { [self openConversation:self.exceptions[i]]; }
}

- (nullable UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != IMNotifTypeSectionExceptions || indexPath.row == 0) { return nil; } // 「添加例外」行不可滑
    NSInteger i = indexPath.row - 1;
    if (i >= (NSInteger)self.exceptions.count) { return nil; }
    IMConversation *conversation = self.exceptions[i];
    __weak typeof(self) ws = self;
    UIContextualAction *unmute = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:IMLocalized(@"conv.menu.unmute") handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            [ws unmute:conversation atIndexPath:indexPath];
            done(YES);
        }];
    unmute.backgroundColor = IMTheme.accent;
    return [UISwipeActionsConfiguration configurationWithActions:@[unmute]];
}

@end
