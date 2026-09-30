//  IMNotificationSettingsViewController.m

#import "IMNotificationSettingsViewController.h"
#import "IMNotificationTypeViewController.h"
#import "IMNotificationSettings.h"
#import "IMTheme.h"
#import "IMLocalization.h"
#import "IMPushSettings.h"
#import "IMPushTokenManager.h"
#import <UserNotifications/UserNotifications.h>

#pragma mark - 行模型（数据驱动，同 IMSettingsViewController/IMPrivacySecurityViewController 先例）

@interface IMNSRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *systemImage;
@property (nonatomic, strong, nullable) UIColor *iconBg;
@property (nonatomic, copy, nullable) NSString *rightValue; // 有值=disclosure 行；nil 且非 switch=纯文字
@property (nonatomic, assign) BOOL isSwitch;
@property (nonatomic, assign) BOOL switchValue;
@property (nonatomic, assign) BOOL isPlaceholder; // 灰置（P1/P2 占位），点了弹「即将上线」
@property (nonatomic, assign) BOOL destructive;
@property (nonatomic, copy, nullable) void (^handler)(void);          // disclosure/占位/destructive 行点击
@property (nonatomic, copy, nullable) void (^switchHandler)(BOOL on); // switch 行值变化
@end
@implementation IMNSRow
@end

@interface IMNSGroup : NSObject
@property (nonatomic, copy, nullable) NSString *header;
@property (nonatomic, copy, nullable) NSString *footer;
@property (nonatomic, copy) NSArray<IMNSRow *> *rows;
@end
@implementation IMNSGroup
@end

#pragma mark - Cell（图标可选 + 标题 + 右值/开关）

@interface IMNSCell : UITableViewCell
- (void)configureWithRow:(IMNSRow *)row;
@end

@implementation IMNSCell {
    UIView *_iconBg;
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_valueLabel;
    UISwitch *_toggle;
    NSLayoutConstraint *_titleLeadingToIcon;
    NSLayoutConstraint *_titleLeadingToEdge;
    void (^_switchHandler)(BOOL on);
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
        _iconView.contentMode = UIViewContentModeCenter;
        [_iconBg addSubview:_iconView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:17];
        [self.contentView addSubview:_titleLabel];

        _valueLabel = [UILabel new];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [UIFont systemFontOfSize:16];
        _valueLabel.textColor = IMTheme.textSecondary;
        _valueLabel.textAlignment = NSTextAlignmentRight;
        [_valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_valueLabel];

        _toggle = [UISwitch new];
        [_toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        self.accessoryView = nil; // 按需在 configure 里挂/摘（disclosure 行不显示开关）

        _titleLeadingToIcon = [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconBg.trailingAnchor constant:IMTheme.space3];
        _titleLeadingToEdge = [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor];

        [NSLayoutConstraint activateConstraints:@[
            [_iconBg.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [_iconBg.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconBg.widthAnchor constraintEqualToConstant:29],
            [_iconBg.heightAnchor constraintEqualToConstant:29],
            [_iconView.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
            _titleLeadingToIcon,
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:IMTheme.space2],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithRow:(IMNSRow *)row {
    _titleLabel.text = row.title;
    _titleLabel.textColor = row.destructive ? UIColor.systemRedColor : (row.isPlaceholder ? IMTheme.textSecondary : IMTheme.textPrimary);

    BOOL hasIcon = row.systemImage.length > 0;
    _iconBg.hidden = !hasIcon;
    _iconView.image = hasIcon ? [UIImage systemImageNamed:row.systemImage] : nil;
    _iconBg.backgroundColor = row.iconBg ?: IMTheme.accent;
    _titleLeadingToIcon.active = hasIcon;
    _titleLeadingToEdge.active = !hasIcon;

    _switchHandler = row.switchHandler;
    if (row.isSwitch) {
        _toggle.on = row.switchValue;
        self.accessoryView = _toggle;
        _valueLabel.text = nil;
        self.accessoryType = UITableViewCellAccessoryNone;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        self.accessoryView = nil;
        _valueLabel.text = row.rightValue;
        _valueLabel.textColor = row.isPlaceholder ? IMTheme.textTertiary : IMTheme.textSecondary;
        self.accessoryType = row.destructive ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    self.accessibilityHint = row.isPlaceholder ? IMLocalized(@"ps.coming_soon_hint") : nil;
}

- (void)toggled:(UISwitch *)sender {
    if (_switchHandler) { _switchHandler(sender.on); }
}

@end

#pragma mark - 控制器

@interface IMNotificationSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<IMNSGroup *> *groups;
@property (nonatomic, assign) UNAuthorizationStatus notifAuthStatus; // M5：系统通知权限，refreshPermissionStatus 异步刷新
@end

@implementation IMNotificationSettingsViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IMLocalized(@"ios.settings.row.notifications");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:IMNSCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:self.tableView];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged)
                                               name:IMNotificationSettingsDidChangeNotification object:nil];
    // M5：接收离线推送开关变化时刷新（跨设置页/别处改的话本页也要跟着变）+ 系统通知权限可能在
    // 系统设置里被用户改动，回到前台时重新查一次（见 refreshPermissionStatus）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged)
                                               name:IMPushSettingsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshPermissionStatus)
                                               name:UIApplicationDidBecomeActiveNotification object:nil];
    [self buildGroups];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self buildGroups]; // 从子页返回：私聊/群聊右值（开·默认 / 关）可能已改
    [self.tableView reloadData];
    [self refreshPermissionStatus]; // 系统通知权限可能在系统设置页被改过（M5）
}

/// 异步查系统通知权限并刷新本页（M5）：已开启/未开启/未设置三态，见 `permissionValueText`。
- (void)refreshPermissionStatus {
    __weak typeof(self) ws = self;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            self.notifAuthStatus = settings.authorizationStatus;
            [self buildGroups];
            [self.tableView reloadData];
        });
    }];
}

- (void)settingsChanged {
    [self buildGroups];
    [self.tableView reloadData];
}

/// 「开 · <提示音名>」/「关」右值（§2.2）。
- (NSString *)summaryForType:(IMNotificationTypeSettings *)type {
    if (!type.enabled) { return IMLocalized(@"notif.value.off"); }
    return IMLocalizedFormat(@"notif.value.on_sound", IMNotificationSoundDisplayName(type.sound));
}

- (void)buildGroups {
    __weak typeof(self) ws = self;
    IMNotificationSettings *settings = IMNotificationSettings.shared;

    IMNSRow *privateRow = [IMNSRow new];
    privateRow.title = IMLocalized(@"notif.row.private");
    privateRow.systemImage = @"person.fill";
    privateRow.iconBg = UIColor.systemBlueColor;
    privateRow.rightValue = [self summaryForType:settings.privateType];
    privateRow.handler = ^{ [ws openType:NO]; };

    IMNSRow *groupRow = [IMNSRow new];
    groupRow.title = IMLocalized(@"notif.row.group");
    groupRow.systemImage = @"person.2.fill";
    groupRow.iconBg = UIColor.systemGreenColor;
    groupRow.rightValue = [self summaryForType:settings.groupType];
    groupRow.handler = ^{ [ws openType:YES]; };

    IMNSGroup *messageGroup = [IMNSGroup new];
    messageGroup.header = IMLocalized(@"notif.section.message");
    messageGroup.footer = IMLocalized(@"notif.message.footer");
    messageGroup.rows = @[privateRow, groupRow];

    IMNSRow *inAppSoundRow = [IMNSRow new];
    inAppSoundRow.title = IMLocalized(@"notif.in_app.sound");
    inAppSoundRow.isSwitch = YES;
    inAppSoundRow.switchValue = settings.inAppSound;
    inAppSoundRow.switchHandler = ^(BOOL on) { IMNotificationSettings.shared.inAppSound = on; };

    IMNSRow *inAppVibrateRow = [IMNSRow new];
    inAppVibrateRow.title = IMLocalized(@"notif.in_app.vibrate");
    inAppVibrateRow.isSwitch = YES;
    inAppVibrateRow.switchValue = settings.inAppVibrate;
    inAppVibrateRow.switchHandler = ^(BOOL on) { IMNotificationSettings.shared.inAppVibrate = on; };

    IMNSRow *inAppPreviewRow = [IMNSRow new];
    inAppPreviewRow.title = IMLocalized(@"notif.in_app.preview");
    inAppPreviewRow.isSwitch = YES; // P1：真开关，绑定 inApp.preview（应用内横幅用，§1.3）
    inAppPreviewRow.switchValue = settings.inAppPreview;
    inAppPreviewRow.switchHandler = ^(BOOL on) { IMNotificationSettings.shared.inAppPreview = on; };

    NSMutableArray<IMNSRow *> *inAppRows = [NSMutableArray arrayWithObject:inAppSoundRow];
    // 设备不支持触感（无 Taptic Engine，实际上就是 iPad）时整行不画（§2.2 iOS 备注）。
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) {
        [inAppRows addObject:inAppVibrateRow];
    }
    [inAppRows addObject:inAppPreviewRow];

    IMNSGroup *inAppGroup = [IMNSGroup new];
    inAppGroup.header = IMLocalized(@"notif.section.in_app");
    inAppGroup.footer = IMLocalized(@"notif.in_app.preview_footer"); // P1：组脚注换成横幅说明（§1.3）
    inAppGroup.rows = inAppRows;

    IMNSRow *includeMutedRow = [IMNSRow new];
    includeMutedRow.title = IMLocalized(@"notif.badge.include_muted");
    includeMutedRow.isSwitch = YES;
    includeMutedRow.switchValue = settings.badgeIncludeMuted;
    includeMutedRow.switchHandler = ^(BOOL on) { IMNotificationSettings.shared.badgeIncludeMuted = on; };

    IMNSGroup *badgeGroup = [IMNSGroup new];
    badgeGroup.header = IMLocalized(@"notif.section.badge");
    badgeGroup.footer = IMLocalized(@"notif.badge.footer");
    badgeGroup.rows = @[includeMutedRow];

    // 锁屏与后台通知（M5 做实，不再是占位）：通知权限 + 接收离线推送（本设备）。
    IMNSRow *permissionRow = [IMNSRow new];
    permissionRow.title = IMLocalized(@"notif.system.permission");
    permissionRow.rightValue = [self permissionValueText];
    permissionRow.handler = ^{ [ws handlePermissionRowTap]; };

    IMNSRow *receivePushRow = [IMNSRow new];
    receivePushRow.title = IMLocalized(@"notif.system.receive_push");
    receivePushRow.isSwitch = YES;
    receivePushRow.switchValue = IMPushSettings.shared.receiveOfflinePush;
    receivePushRow.switchHandler = ^(BOOL on) { [ws applyReceiveOfflinePushToggle:on]; };

    IMNSGroup *systemGroup = [IMNSGroup new];
    systemGroup.header = IMLocalized(@"notif.section.system");
    systemGroup.footer = IMLocalized(@"notif.system.footer_apns");
    systemGroup.rows = @[permissionRow, receivePushRow];

    IMNSRow *resetRow = [IMNSRow new];
    resetRow.title = IMLocalized(@"notif.reset");
    resetRow.destructive = YES;
    resetRow.handler = ^{ [ws confirmReset]; };

    IMNSGroup *resetGroup = [IMNSGroup new];
    resetGroup.footer = IMLocalized(@"notif.reset.footer");
    resetGroup.rows = @[resetRow];

    self.groups = @[messageGroup, inAppGroup, badgeGroup, systemGroup, resetGroup];
}

#pragma mark - 动作

- (void)openType:(BOOL)isGroup {
    IMNotificationTypeViewController *vc = [[IMNotificationTypeViewController alloc] initWithHost:self.host userID:self.userID isGroup:isGroup];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 锁屏与后台通知（M5）

/// 「通知权限」右值：已开启/未开启/未设置三态（notif.system.permission_on/off/undetermined）。
- (NSString *)permissionValueText {
    switch (self.notifAuthStatus) {
        case UNAuthorizationStatusAuthorized:
        case UNAuthorizationStatusProvisional:
        case UNAuthorizationStatusEphemeral:
            return IMLocalized(@"notif.system.permission_on");
        case UNAuthorizationStatusDenied:
            return IMLocalized(@"notif.system.permission_off");
        case UNAuthorizationStatusNotDetermined:
        default:
            return IMLocalized(@"notif.system.permission_undetermined");
    }
}

/// 点「通知权限」行：未决定→请求系统授权；已拒绝→弹提示引导去系统设置；已开启→直接跳系统设置
/// （PUSH_M5_DESIGN §5）。
- (void)handlePermissionRowTap {
    __weak typeof(self) ws = self;
    switch (self.notifAuthStatus) {
        case UNAuthorizationStatusNotDetermined: {
            UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
            [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:options
                                                                               completionHandler:^(BOOL granted, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [ws refreshPermissionStatus];
                    if (granted) { [IMPushTokenManager.shared registerIfEligible]; }
                });
            }];
            break;
        }
        case UNAuthorizationStatusDenied: {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                message:IMLocalized(@"notif.system.permission_denied_hint") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"notif.system.open_settings") style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction *action) { [ws openSystemSettings]; }]];
            [self presentViewController:alert animated:YES completion:nil];
            break;
        }
        default:
            [self openSystemSettings];
            break;
    }
}

- (void)openSystemSettings {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if (url) { [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil]; }
}

/// 「接收离线推送（本设备）」开关：开→若已授权立即注册+上报令牌；关→删除本机已登记的令牌
/// （PUSH_M5_DESIGN §1.1/§5）。
- (void)applyReceiveOfflinePushToggle:(BOOL)on {
    IMPushSettings.shared.receiveOfflinePush = on;
    if (on) {
        [IMPushTokenManager.shared enableAndRegisterIfAuthorized];
    } else {
        [IMPushTokenManager.shared disableAndDeleteToken];
    }
}

- (void)confirmReset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:IMLocalized(@"notif.reset.confirm_title")
                                                                     message:IMLocalized(@"notif.reset.confirm_message")
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        // 不取消任何会话的免打扰（§3.6，与 Telegram 刻意不同）。不再手动刷新：setter 同步发变更通知，settingsChanged 已刷
        [IMNotificationSettings.shared resetToDefaults];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)self.groups.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.groups[section].rows.count; }
- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.groups[section].header; }
- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return self.groups[section].footer; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMNSCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    [cell configureWithRow:self.groups[indexPath.section].rows[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IMNSRow *row = self.groups[indexPath.section].rows[indexPath.row];
    if (row.isSwitch) { return; } // 开关行不响应整行点击，只响应 UISwitch 本身
    if (row.handler) { row.handler(); }
}

@end
