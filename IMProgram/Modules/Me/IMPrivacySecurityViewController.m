//  IMPrivacySecurityViewController.m

#import "IMPrivacySecurityViewController.h"
#import "IMBlockedListViewController.h"
#import "IMChangePasswordViewController.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "UIViewController+IMToast.h"
#import "IMLog.h"
#import "IMLocalization.h"

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
        [_valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
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

    IMPSRow *changePwd = [IMPSRow new];
    changePwd.rowId = @"changePwd"; changePwd.title = IMLocalized(@"settings.change_password"); changePwd.systemImage = @"key.fill";
    changePwd.iconBgColor = UIColor.systemBlueColor;
    changePwd.handler = ^{ [ws openChangePassword]; };

    IMPSGroup *groupA = [IMPSGroup new];
    groupA.footer = IMLocalized(@"ps.group_a_footer");
    groupA.rows = @[blocked, changePwd];

    // 组 B · 账号保护（占位）
    IMPSGroup *groupB = [IMPSGroup new];
    groupB.header = IMLocalized(@"ps.section.account_protection");
    groupB.footer = IMLocalized(@"ps.account_protection_footer");
    groupB.rows = @[
        [self placeholder:IMLocalized(@"ps.row.two_factor") symbol:@"lock.shield.fill" bg:UIColor.systemGrayColor value:IMLocalized(@"common.off")],
        [self placeholder:IMLocalized(@"ps.row.passkey") symbol:@"key.horizontal.fill" bg:UIColor.systemPurpleColor value:IMLocalized(@"common.off")],
        [self placeholder:IMLocalized(@"ps.row.email_login") symbol:@"envelope.fill" bg:UIColor.systemTealColor value:nil],
    ];

    // 组 C · 会话隐私（占位）
    IMPSGroup *groupC = [IMPSGroup new];
    groupC.header = IMLocalized(@"ps.section.chat_privacy");
    groupC.footer = IMLocalized(@"ps.chat_privacy_footer");
    groupC.rows = @[
        [self placeholder:IMLocalized(@"ps.row.auto_delete_messages") symbol:@"timer" bg:UIColor.systemOrangeColor value:IMLocalized(@"common.off")],
    ];

    // 组 D · 谁能看到（占位，一整组 P2）
    IMPSGroup *groupD = [IMPSGroup new];
    groupD.header = IMLocalized(@"ps.section.who_can_see");
    groupD.footer = IMLocalized(@"ps.who_can_see_footer");
    groupD.rows = @[
        [self placeholder:IMLocalized(@"ps.row.phone_number") symbol:@"phone.fill" bg:UIColor.systemGreenColor value:IMLocalized(@"common.my_contacts")],
        [self placeholder:IMLocalized(@"ps.row.last_seen") symbol:@"eye.fill" bg:UIColor.systemBlueColor value:IMLocalized(@"common.my_contacts")],
        [self placeholder:IMLocalized(@"ps.row.avatar") symbol:@"person.crop.circle.fill" bg:UIColor.systemPurpleColor value:IMLocalized(@"common.everyone")],
        [self placeholder:IMLocalized(@"ps.row.bio") symbol:@"text.alignleft" bg:UIColor.systemYellowColor value:IMLocalized(@"common.everyone")],
        [self placeholder:IMLocalized(@"ps.row.birthday") symbol:@"gift.fill" bg:UIColor.systemPinkColor value:IMLocalized(@"common.my_contacts")],
    ];

    // 组 E · 数据（占位）
    IMPSGroup *groupE = [IMPSGroup new];
    groupE.header = IMLocalized(@"ps.section.data");
    groupE.rows = @[
        [self placeholder:IMLocalized(@"ps.row.clear_all_chats") symbol:@"trash.fill" bg:UIColor.systemGrayColor value:nil],
        [self placeholder:IMLocalized(@"ps.row.export_data") symbol:@"arrow.up.doc.fill" bg:UIColor.systemBlueColor value:nil],
    ];

    self.groups = @[groupA, groupB, groupC, groupD, groupE];
}

- (IMPSRow *)placeholder:(NSString *)title symbol:(NSString *)symbol bg:(UIColor *)bg value:(nullable NSString *)value {
    __weak typeof(self) ws = self;
    IMPSRow *r = [IMPSRow new];
    r.rowId = title; r.title = title; r.systemImage = symbol; r.iconBgColor = bg;
    r.rightValue = value; r.isPlaceholder = YES;
    r.handler = ^{ [ws im_showComingSoon:title]; };
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

#pragma mark - 动作

- (void)openBlocked {
    IMBlockedListViewController *vc = [[IMBlockedListViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openChangePassword {
    IMChangePasswordViewController *vc = [[IMChangePasswordViewController alloc] initWithHost:self.host userID:self.userID];
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
