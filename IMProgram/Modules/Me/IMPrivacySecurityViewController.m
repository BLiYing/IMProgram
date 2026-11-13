//  IMPrivacySecurityViewController.m

#import "IMPrivacySecurityViewController.h"
#import "IMBlockedListViewController.h"
#import "IMChangePasswordViewController.h"
#import "IMClearAllViewController.h"
#import "IMExportDataViewController.h"
#import "IMTwoStepViewController.h"
#import "IMEmailLoginViewController.h"
#import "IMEmailLogin.h"
#import "IMHTTPService+Email.h"
#import "IMTwoStep.h"
#import "IMHTTPService+TwoStep.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "UIViewController+IMToast.h"
#import "IMLog.h"
#import "IMLocalization.h"
#import "IMAutoDelete.h"
#import "IMAutoDeleteTierViewController.h"
#import "IMHTTPService+AutoDelete.h"
#import "IMPrivacyVisibility.h"
#import "IMPrivacyVisibilityViewController.h"
#import "IMPhoneBindViewController.h"
#import "IMHTTPService+Phone.h"

#pragma mark - 行模型

/// 行数据：图标 + 标题 + 右侧 value + handler + isPlaceholder（灰置占位）。
@interface IMPSRow : NSObject
@property (nonatomic, copy) NSString *rowId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *systemImage;
@property (nonatomic, strong) UIColor *iconBgColor;
@property (nonatomic, copy, nullable) NSString *rightValue;
@property (nonatomic, assign) BOOL isPlaceholder;
@property (nonatomic, copy) void (^handler)(void);
@end
@implementation IMPSRow
@end

/// 组：可选 header 与 footer 说明；一组多行。
@interface IMPSGroup : NSObject
@property (nonatomic, copy, nullable) NSString *header;
@property (nonatomic, copy, nullable) NSString *footer;
@property (nonatomic, copy) NSArray<IMPSRow *> *rows;
@end
@implementation IMPSGroup
@end

#pragma mark - Cell（对齐设计文档 §5：icon 29×29 圆角6，主标题 17pt regular，value 17pt secondary，占位半档灰）

@interface IMPSCell : UITableViewCell
- (void)configureWithRow:(IMPSRow *)row;
@end

@implementation IMPSCell {
    UIView *_iconBg;
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_valueLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _iconBg = [UIView new];
        _iconBg.translatesAutoresizingMaskIntoConstraints = NO;
        _iconBg.layer.cornerRadius = 6; // §5.3
        _iconBg.layer.masksToBounds = YES;
        [self.contentView addSubview:_iconBg];

        _iconView = [UIImageView new];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.tintColor = UIColor.whiteColor;
        _iconView.contentMode = UIViewContentModeCenter;
        [_iconBg addSubview:_iconView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; // 17pt
        _titleLabel.textColor = UIColor.labelColor;
        [self.contentView addSubview:_titleLabel];

        _valueLabel = [UILabel new];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; // 17pt
        _valueLabel.textColor = UIColor.secondaryLabelColor;
        _valueLabel.textAlignment = NSTextAlignmentRight;
        [_valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        // 长右值（邮箱地址）单行、中间截断，让位给标题（优先级低于标题的 750）；短值不受影响。
        _valueLabel.numberOfLines = 1;
        _valueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_valueLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh - 1 forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconBg.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [_iconBg.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconBg.widthAnchor  constraintEqualToConstant:29],
            [_iconBg.heightAnchor constraintEqualToConstant:29],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconBg.trailingAnchor constant:12], // §5.3 图标↔标题
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

            [_valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:8],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithRow:(IMPSRow *)row {
    _titleLabel.text = row.title;
    // 占位行：title=.secondaryLabel（灰半档）；value=.tertiaryLabel（再半档）；icon 全彩保留（§2.5）。
    _titleLabel.textColor = row.isPlaceholder ? UIColor.secondaryLabelColor : UIColor.labelColor;
    _valueLabel.text = row.rightValue;
    _valueLabel.textColor = row.isPlaceholder ? UIColor.tertiaryLabelColor : UIColor.secondaryLabelColor;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    _iconView.image = [[UIImage systemImageNamed:row.systemImage] imageByApplyingSymbolConfiguration:cfg];
    _iconBg.backgroundColor = row.iconBgColor;

    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator; // 占位行也保留 chevron（暗示可点开）
    self.accessibilityHint = row.isPlaceholder ? IMLocalized(@"ps.coming_soon_hint") : nil;
}

@end

#pragma mark - 控制器

@interface IMPrivacySecurityViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<IMPSGroup *> *groups;
@property (nonatomic, strong) IMPSRow *blockedRow; ///< 引用留着，count 拉回后就地更新 rightValue
@property (nonatomic, strong) IMPSRow *emailRow; ///< 邮箱登录（活行）：进页 / 子页返回时 GET 状态，右值 = 邮箱 / 未绑定
@property (nonatomic, strong) IMPSRow *twoStepRow; ///< 两步验证（活行）：进页 / 子页返回时 GET 状态，加载前右值留空
@property (nonatomic, strong) IMPSRow *passwordRow;   ///< 登录密码（活行）：右值 已设置 / 未设置（PHONE_AUTH_DESIGN §6）
@property (nonatomic, strong) IMPSRow *loginPhoneRow; ///< 登录手机号（活行）：右值 打码号码 / 未绑定；短信不可用且未绑定时不显示
@property (nonatomic, strong) IMPSGroup *protectGroup;
@property (nonatomic, copy) NSArray<IMPSRow *> *protectRowsBase; ///< 账号保护组除「登录手机号」外的行
@property (nonatomic, strong, nullable) IMSecurityState *security; ///< GET /users/me/security；nil = 还没取到
@property (nonatomic, strong) IMPSRow *autoDeleteRow; ///< 自动删除消息（账号默认档位）活行：GET /users/me/privacy 回来后就地更新右值
@property (nonatomic, assign) int64_t autoDeleteDefaultSec;
@property (nonatomic, strong) IMPSRow *lastSeenRow; ///< 谁能看到 ▸ 上次上线（活行）
@property (nonatomic, strong) IMPSRow *avatarRow;   ///< 谁能看到 ▸ 头像（活行）
@property (nonatomic, strong) IMPSRow *bioRow;      ///< 谁能看到 ▸ 个人简介（活行）
@property (nonatomic, strong) IMPSRow *phoneRow;    ///< 谁能看到 ▸ 手机号码（活行）
/// 当前档位（GET 回来前用服务端默认值），按 IMPrivacyVisibilityKind 下标存取。
@property (nonatomic, strong) NSMutableArray<NSString *> *levels;
@end

@implementation IMPrivacySecurityViewController

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
    self.title = IMLocalized(@"settings.row.privacy"); // 与设置页入口 title 完全一致（§0）
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.levels = [NSMutableArray array];
    for (IMPrivacyVisibilityKind k = IMPrivacyVisibilityKindLastSeen; k < IMPrivacyVisibilityKindCount; k++) {
        [self.levels addObject:IMPrivacyVisibilityDefault(k)];
    }
    [self buildGroups];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:IMPSCell.class forCellReuseIdentifier:@"ps"];
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshBlockedCount];
    [self refreshPrivacySettings];
    [self refreshTwoStepStatus];
    [self refreshEmailStatus];
    [self refreshSecurityState];
}

#pragma mark - 数据

- (void)buildGroups {
    __weak typeof(self) ws = self;

    // 组 A · 安全（P0）
    IMPSRow *blocked = [IMPSRow new];
    blocked.rowId = @"blocked"; blocked.title = IMLocalized(@"blocked.title"); blocked.systemImage = @"nosign";
    blocked.iconBgColor = UIColor.systemRedColor;
    blocked.handler = ^{ [ws openBlocked]; };
    self.blockedRow = blocked;

    // 「登录密码」= 原「修改密码」行改名，位置与图标不变（PHONE_AUTH_DESIGN §6）。
    IMPSRow *changePwd = [IMPSRow new];
    changePwd.rowId = @"changePwd"; changePwd.title = IMLocalized(@"security.password"); changePwd.systemImage = @"key.fill";
    changePwd.iconBgColor = UIColor.systemBlueColor;
    changePwd.handler = ^{ [ws openChangePassword]; };
    self.passwordRow = changePwd;

    IMPSGroup *groupA = [IMPSGroup new];
    groupA.footer = IMLocalized(@"ps.group_a_footer");
    groupA.rows = @[blocked, changePwd];

    // 组 B · 账号保护（占位）
    IMPSGroup *groupB = [IMPSGroup new];
    groupB.header = IMLocalized(@"ps.section.account_protection");
    groupB.footer = IMLocalized(@"security.protect.footer");
    IMPSRow *phone = [IMPSRow new];
    phone.rowId = @"loginPhone"; phone.title = IMLocalized(@"security.phone"); phone.systemImage = @"iphone";
    phone.iconBgColor = UIColor.systemPinkColor;
    phone.handler = ^{ [ws openLoginPhone]; };
    self.loginPhoneRow = phone;
    self.protectRowsBase = @[
        [self twoStepLiveRow],
        [self placeholder:IMLocalized(@"ps.row.passkey") symbol:@"key.horizontal.fill" bg:UIColor.systemPurpleColor value:IMLocalized(@"common.off")],
        [self emailLoginLiveRow],
    ];
    self.protectGroup = groupB;
    [self applyProtectRows];

    // 组 C · 会话隐私：自动删除消息（活行，右值 = 账号默认档位，AUTO_DELETE_DESIGN §3.3 A）
    IMPSRow *autoDelete = [IMPSRow new];
    autoDelete.rowId = @"autoDelete"; autoDelete.title = IMLocalized(@"ps.row.auto_delete_messages"); autoDelete.systemImage = @"timer";
    autoDelete.iconBgColor = UIColor.systemOrangeColor;
    autoDelete.rightValue = IMAutoDeleteTierTitle(self.autoDeleteDefaultSec);
    autoDelete.handler = ^{ [ws openAutoDelete]; };
    self.autoDeleteRow = autoDelete;
    IMPSGroup *groupC = [IMPSGroup new];
    groupC.header = IMLocalized(@"ps.section.chat_privacy");
    groupC.footer = IMLocalized(@"ps.chat_privacy_footer");
    groupC.rows = @[autoDelete];

    // 组 D · 谁能看到：四行均为活行（PRIVACY_VISIBILITY_DESIGN §4 + PROFILE_BIO_DESIGN §2.4）；生日不做，已删
    self.phoneRow = [self visibilityRow:IMPrivacyVisibilityKindPhone symbol:@"phone.fill" bg:UIColor.systemGreenColor];
    self.lastSeenRow = [self visibilityRow:IMPrivacyVisibilityKindLastSeen symbol:@"eye.fill" bg:UIColor.systemBlueColor];
    self.avatarRow = [self visibilityRow:IMPrivacyVisibilityKindAvatar symbol:@"person.crop.circle.fill" bg:UIColor.systemPurpleColor];
    self.bioRow = [self visibilityRow:IMPrivacyVisibilityKindBio symbol:@"text.alignleft" bg:UIColor.systemYellowColor];
    IMPSGroup *groupD = [IMPSGroup new];
    groupD.header = IMLocalized(@"ps.section.who_can_see");
    groupD.footer = IMLocalized(@"ps.who_can_see_footer");
    groupD.rows = @[self.phoneRow, self.lastSeenRow, self.avatarRow, self.bioRow];

    // 组 E · 数据：清除所有对话（CLEAR_ALL_CONVERSATIONS_DESIGN，红底活行）与导出我的数据（DATA_EXPORT_DESIGN §5）均为活行；破坏性行不登记设置搜索
    IMPSRow *exportData = [IMPSRow new];
    exportData.rowId = @"exportData"; exportData.title = IMLocalized(@"ps.row.export_data");
    exportData.systemImage = @"arrow.up.doc.fill"; exportData.iconBgColor = UIColor.systemBlueColor;
    exportData.handler = ^{ [ws openExportData]; };
    IMPSRow *clearAll = [IMPSRow new];
    clearAll.rowId = @"clearAllChats"; clearAll.title = IMLocalized(@"privacy.clear_all.row");
    clearAll.systemImage = @"trash.fill"; clearAll.iconBgColor = UIColor.systemRedColor; // #FF3B30（PRIVACY_SECURITY_DESIGN §2.4 预留，转活换红）
    clearAll.handler = ^{ [ws openClearAll]; };
    IMPSGroup *groupE = [IMPSGroup new];
    groupE.header = IMLocalized(@"ps.section.data");
    groupE.rows = @[clearAll, exportData];

    self.groups = @[groupA, groupB, groupC, groupD, groupE];
}

/// 两步验证活行：右值 = 开启 / 关闭（进页取一次，加载前留空，失败当关闭且不弹错）；点击进「两步验证」页。
- (IMPSRow *)twoStepLiveRow {
    __weak typeof(self) ws = self;
    IMPSRow *r = [IMPSRow new];
    r.rowId = @"twoStep"; r.title = IMLocalized(@"ps.row.two_factor"); r.systemImage = @"lock.shield.fill";
    r.iconBgColor = UIColor.systemGrayColor;
    r.handler = ^{ [ws openTwoStep]; };
    self.twoStepRow = r;
    return r;
}

/// 邮箱登录活行（EMAIL_LOGIN_DESIGN §2.1）：右值 = 邮箱地址 / 未绑定；进页与子页返回都重新取值，不做本地缓存；加载前留空。
- (IMPSRow *)emailLoginLiveRow {
    __weak typeof(self) ws = self;
    IMPSRow *r = [IMPSRow new];
    r.rowId = @"emailLogin"; r.title = IMLocalized(@"ps.row.email_login"); r.systemImage = @"envelope.fill";
    r.iconBgColor = UIColor.systemTealColor;
    r.handler = ^{ [ws openEmailLogin]; };
    self.emailRow = r;
    return r;
}

- (IMPSRow *)placeholder:(NSString *)title symbol:(NSString *)symbol bg:(UIColor *)bg value:(nullable NSString *)value {
    __weak typeof(self) ws = self;
    IMPSRow *r = [IMPSRow new];
    r.rowId = title; r.title = title; r.systemImage = symbol; r.iconBgColor = bg;
    r.rightValue = value; r.isPlaceholder = YES;
    r.handler = ^{ [ws im_showComingSoon:title]; };
    return r;
}

- (IMPSRow *)visibilityRow:(IMPrivacyVisibilityKind)kind symbol:(NSString *)symbol bg:(UIColor *)bg {
    __weak typeof(self) ws = self;
    IMPSRow *r = [IMPSRow new];
    r.rowId = IMPrivacyVisibilityJSONKey(kind); r.title = IMLocalized(IMPrivacyVisibilityRowTitleKey(kind));
    r.systemImage = symbol; r.iconBgColor = bg;
    r.rightValue = IMPrivacyVisibilityTitle(self.levels[kind]);
    r.handler = ^{ [ws openVisibility:kind]; };
    return r;
}

/// 拉一次黑名单，右值显数量。best-effort：失败保留旧值不刷新，避免抖动闪。
- (void)refreshBlockedCount {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *loginErr) {
        __strong typeof(ws) self = ws;
        if (!self || token.length == 0) { return; }
        [IMHTTPService.sharedService friendsWithToken:token status:@"blocked" completion:^(NSArray<IMUserCard *> *list, NSError *err) {
            __strong typeof(ws) self = ws;
            if (!self || err) { return; }
            NSString *val = list.count > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)list.count] : nil;
            self.blockedRow.rightValue = val;
            // 只 reload 第 0 组第 0 行（避免整表跳）。
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]]
                                  withRowAnimation:UITableViewRowAnimationNone];
        }];
    }];
}

/// 取一次两步验证状态（进页 / 子页返回时刷新右值）。失败当关闭，不弹错。
- (void)refreshTwoStepStatus {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *loginErr) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (token.length == 0) { [self applyTwoStepEnabled:nil]; return; }
        [IMHTTPService.sharedService fetchTwoStepStateWithToken:token completion:^(IMTwoStepState *state, NSError *err) {
            [ws applyTwoStepEnabled:state ? @(state.enabled) : nil];
        }];
    }];
}

/// enabled == nil 表示这次没取到：已有读数就保留（一次瞬时失败不能把「开启」翻成「关闭」），从没取到过才当关闭。
- (void)applyTwoStepEnabled:(nullable NSNumber *)enabled {
    if (!enabled && self.twoStepRow.rightValue.length > 0) { return; }
    self.twoStepRow.rightValue = IMTwoStepRowValueText(enabled ?: @NO);
    for (NSUInteger s = 0; s < self.groups.count; s++) { // 只刷这一行（同 blockedRow），避免整表跳
        NSUInteger r = [self.groups[s].rows indexOfObjectIdenticalTo:self.twoStepRow];
        if (r != NSNotFound) {
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)r inSection:(NSInteger)s]]
                                  withRowAnimation:UITableViewRowAnimationNone];
            return;
        }
    }
}

#pragma mark - 登录密码 / 登录手机号（PHONE_AUTH_DESIGN §6）

/// 「登录手机号」排账号保护组第一行；状态未知、或短信不可用且没绑定时不显示。
- (void)applyProtectRows {
    self.protectGroup.rows = IMSecurityShowsPhoneRow(self.security)
        ? [@[self.loginPhoneRow] arrayByAddingObjectsFromArray:self.protectRowsBase] : self.protectRowsBase;
}

/// 取一次安全状态（进页 / 子页返回时）。失败保留旧值，不弹错。
- (void)refreshSecurityState {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *loginErr) {
        if (token.length == 0) { return; }
        [IMHTTPService.sharedService fetchSecurityStateWithToken:token completion:^(IMSecurityState *state, NSError *err) {
            if (state) { [ws applySecurityState:state]; }
        }];
    }];
}

- (void)applySecurityState:(IMSecurityState *)state {
    self.security = state;
    self.passwordRow.rightValue = IMSecurityPasswordRowValue(state);
    self.loginPhoneRow.rightValue = IMSecurityPhoneRowValue(state);
    [self applyProtectRows];
    [self.tableView reloadData];
}

- (void)openLoginPhone {
    IMSecurityState *state = self.security;
    if (!state) { return; }
    if (IMSecurityPhoneRowAction(state) == IMPhoneRowActionSMSUnavailable) { // 已绑定但短信不可用：新号码收不到码，换不了
        [self im_showToast:IMLocalized(@"err.200040")];
        return;
    }
    IMPhoneBindViewController *vc = [[IMPhoneBindViewController alloc] initWithHost:self.host userID:self.userID security:state];
    __weak typeof(self) ws = self;
    vc.onBound = ^(NSString *masked) {
        state.phoneBound = YES;
        state.phoneMasked = masked;
        [ws applySecurityState:state];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

/// 取一次邮箱状态刷新右值。失败：已有读数就保留（瞬时失败不能把邮箱翻成「未绑定」），从没取到过就留空，不弹错。
- (void)refreshEmailStatus {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *loginErr) {
        if (token.length == 0) { return; }
        [IMHTTPService.sharedService fetchEmailStateWithToken:token completion:^(IMEmailState *state, NSError *err) {
            [ws applyEmailState:state];
        }];
    }];
}

- (void)applyEmailState:(nullable IMEmailState *)state {
    if (!state) { return; }
    self.emailRow.rightValue = IMEmailRowValueText(state);
    for (NSUInteger s = 0; s < self.groups.count; s++) {
        NSUInteger r = [self.groups[s].rows indexOfObjectIdenticalTo:self.emailRow];
        if (r != NSNotFound) {
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)r inSection:(NSInteger)s]]
                                  withRowAnimation:UITableViewRowAnimationNone];
            return;
        }
    }
}

/// 取一次隐私设置（进页 / 子页返回时）：自动删除默认档 + 谁能看到两项同一个 GET。best-effort：失败保留旧值。
- (void)refreshPrivacySettings {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService fetchPrivacySettingsWithToken:token completion:^(IMPrivacySettings *settings, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error || !settings) { return; }
        self.autoDeleteDefaultSec = settings.autoDeleteDefaultSec;
        self.autoDeleteRow.rightValue = IMAutoDeleteTierTitle(settings.autoDeleteDefaultSec);
        for (IMPrivacyVisibilityKind k = IMPrivacyVisibilityKindLastSeen; k < IMPrivacyVisibilityKindCount; k++) {
            [self applyVisibility:[settings visibilityForKind:k] kind:k reload:NO];
        }
        [self.tableView reloadData];
    }];
}

/// 按 kind 取活行（switch 穷举，新增项目漏写会在编译期给 -Wswitch 警告，而不是悄悄写到别的行）。
- (IMPSRow *)visibilityRowForKind:(IMPrivacyVisibilityKind)kind {
    switch (kind) {
        case IMPrivacyVisibilityKindLastSeen: return self.lastSeenRow;
        case IMPrivacyVisibilityKindAvatar:   return self.avatarRow;
        case IMPrivacyVisibilityKindBio:      return self.bioRow;
        case IMPrivacyVisibilityKindPhone:    return self.phoneRow;
        case IMPrivacyVisibilityKindCount:    break;
    }
    NSAssert(NO, @"未知的隐私项目 %ld", (long)kind);
    return self.avatarRow;
}

- (void)applyVisibility:(NSString *)level kind:(IMPrivacyVisibilityKind)kind reload:(BOOL)reload {
    self.levels[kind] = level;
    IMPSRow *row = [self visibilityRowForKind:kind];
    row.rightValue = IMPrivacyVisibilityTitle(level);
    if (reload) { [self.tableView reloadData]; }
}

- (void)applyAutoDeleteDefault:(int64_t)sec {
    self.autoDeleteDefaultSec = sec;
    self.autoDeleteRow.rightValue = IMAutoDeleteTierTitle(sec);
    [self.tableView reloadData];
}

#pragma mark - 动作

/// 档位选择页（账号默认）：选中即保存、不弹确认；失败 toast + ✓ 回滚（逻辑在选择页的账号默认工厂里，设置搜索直达共用）。
- (void)openAutoDelete {
    __weak typeof(self) ws = self;
    IMAutoDeleteTierViewController *vc = [IMAutoDeleteTierViewController
        accountDefaultPickerWithInitialSec:self.autoDeleteDefaultSec onSaved:^(int64_t sec) { [ws applyAutoDeleteDefault:sec]; }];
    [self.navigationController pushViewController:vc animated:YES];
}

/// 档位单选页（上次上线 / 头像 / 个人简介 / 手机号码）：选中即存、不弹确认；失败 toast + ✓ 回滚在选择页里，成功后回写行右值。
- (void)openVisibility:(IMPrivacyVisibilityKind)kind {
    __weak typeof(self) ws = self;
    NSString *level = self.levels[kind];
    IMPrivacyVisibilityViewController *vc = [[IMPrivacyVisibilityViewController alloc]
        initWithKind:kind currentLevel:level onSaved:^(NSString *saved) { [ws applyVisibility:saved kind:kind reload:YES]; }];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openBlocked {
    IMBlockedListViewController *vc = [[IMBlockedListViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openExportData {
    IMExportDataViewController *vc = [[IMExportDataViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openClearAll {
    IMClearAllViewController *vc = [[IMClearAllViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openTwoStep {
    IMTwoStepViewController *vc = [[IMTwoStepViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openEmailLogin {
    IMEmailLoginViewController *vc = [[IMEmailLoginViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openChangePassword {
    IMChangePasswordViewController *vc = [[IMChangePasswordViewController alloc] initWithHost:self.host userID:self.userID security:self.security];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)self.groups.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.groups[section].rows.count;
}
- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.groups[section].header;
}
- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.groups[section].footer;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMPSCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ps" forIndexPath:indexPath];
    [cell configureWithRow:self.groups[indexPath.section].rows[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IMPSRow *row = self.groups[indexPath.section].rows[indexPath.row];
    if (row.handler) { row.handler(); }
}

@end
