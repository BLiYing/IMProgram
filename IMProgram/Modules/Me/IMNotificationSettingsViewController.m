//  IMNotificationSettingsViewController.m

#import "IMNotificationSettingsViewController.h"
#import "IMNotificationTypeViewController.h"
#import "IMNotificationSettings.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMLocalization.h"

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
    [self buildGroups];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self buildGroups]; // 从子页返回：私聊/群聊右值（开·默认 / 关）可能已改
    [self.tableView reloadData];
}

- (void)settingsChanged {
    [self buildGroups];
    [self.tableView reloadData];
}

/// 「开 · <提示音名>」/「关」右值（§2.2）。
- (NSString *)summaryForType:(IMNotificationTypeSettings *)type {
    if (!type.enabled) { return IMLocalized(@"notif.value.off"); }
    NSDictionary<NSString *, NSString *> *names = @{
        IMNotificationSoundIDNone: IMLocalized(@"notif.sound.none"),
        IMNotificationSoundIDDefault: IMLocalized(@"notif.sound.default"),
        IMNotificationSoundIDChord: IMLocalized(@"notif.sound.chord"),
        IMNotificationSoundIDChime: IMLocalized(@"notif.sound.chime"),
        IMNotificationSoundIDRise: IMLocalized(@"notif.sound.rise"),
        IMNotificationSoundIDDrop: IMLocalized(@"notif.sound.drop"),
    };
    NSString *soundName = names[type.sound] ?: IMLocalized(@"notif.sound.default");
    return IMLocalizedFormat(@"notif.value.on_sound", soundName);
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
    inAppPreviewRow.isPlaceholder = YES; // P1，画成灰置占位行（§2.2）
    inAppPreviewRow.rightValue = IMLocalized(@"ps.coming_soon_hint");
    inAppPreviewRow.handler = ^{ [ws im_showComingSoon:IMLocalized(@"notif.in_app.preview")]; };

    NSMutableArray<IMNSRow *> *inAppRows = [NSMutableArray arrayWithObject:inAppSoundRow];
    // 设备不支持触感（无 Taptic Engine，实际上就是 iPad）时整行不画（§2.2 iOS 备注）。
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) {
        [inAppRows addObject:inAppVibrateRow];
    }
    [inAppRows addObject:inAppPreviewRow];

    IMNSGroup *inAppGroup = [IMNSGroup new];
    inAppGroup.header = IMLocalized(@"notif.section.in_app");
    inAppGroup.footer = IMLocalized(@"notif.in_app.footer");
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

    // P2 占位组：锁屏与后台通知（整组画成灰置，点了「即将上线」，见 §0/§2.2）。
    IMNSRow *showRow = [IMNSRow new];
    showRow.title = IMLocalized(@"notif.system.show");
    showRow.isPlaceholder = YES;
    showRow.rightValue = IMLocalized(@"ps.coming_soon_hint");
    showRow.handler = ^{ [ws im_showComingSoon:IMLocalized(@"notif.system.show")]; };

    IMNSRow *permissionRow = [IMNSRow new];
    permissionRow.title = IMLocalized(@"notif.system.permission");
    permissionRow.isPlaceholder = YES;
    permissionRow.rightValue = IMLocalized(@"notif.system.permission_off");
    permissionRow.handler = ^{ [ws im_showComingSoon:IMLocalized(@"notif.system.permission")]; };

    IMNSGroup *systemGroup = [IMNSGroup new];
    systemGroup.header = IMLocalized(@"notif.section.system");
    systemGroup.footer = IMLocalized(@"notif.system.footer");
    systemGroup.rows = @[showRow, permissionRow];

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

- (void)confirmReset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:IMLocalized(@"notif.reset.confirm_title")
                                                                     message:IMLocalized(@"notif.reset.confirm_message")
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [IMNotificationSettings.shared resetToDefaults]; // 不取消任何会话的免打扰（§3.6，与 Telegram 刻意不同）
        [ws buildGroups];
        [ws.tableView reloadData];
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
