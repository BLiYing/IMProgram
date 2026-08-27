//  IMPrivacySecurityViewController.m

#import "IMPrivacySecurityViewController.h"
#import "IMBlockedListViewController.h"
#import "IMChangePasswordViewController.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "UIViewController+IMToast.h"
#import "IMLog.h"

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
    self.accessibilityHint = row.isPlaceholder ? @"即将上线" : nil;
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
    self.title = @"隐私与安全"; // 与设置页入口 title 完全一致（§0）
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
    blocked.rowId = @"blocked"; blocked.title = @"已屏蔽的用户"; blocked.systemImage = @"nosign";
    blocked.iconBgColor = UIColor.systemRedColor;
    blocked.handler = ^{ [ws openBlocked]; };
    self.blockedRow = blocked;

    IMPSRow *changePwd = [IMPSRow new];
    changePwd.rowId = @"changePwd"; changePwd.title = @"修改密码"; changePwd.systemImage = @"key.fill";
    changePwd.iconBgColor = UIColor.systemBlueColor;
    changePwd.handler = ^{ [ws openChangePassword]; };

    IMPSGroup *groupA = [IMPSGroup new];
    groupA.footer = @"已屏蔽的用户不能给你发消息，也看不到你的资料。";
    groupA.rows = @[blocked, changePwd];

    // 组 B · 账号保护（占位）
    IMPSGroup *groupB = [IMPSGroup new];
    groupB.header = @"账号保护";
    groupB.footer = @"绑定第二因子后，即使密码泄露也无法登录你的账号。";
    groupB.rows = @[
        [self placeholder:@"两步验证" symbol:@"lock.shield.fill" bg:UIColor.systemGrayColor value:@"关闭"],
        [self placeholder:@"通行密钥" symbol:@"key.horizontal.fill" bg:UIColor.systemPurpleColor value:@"关闭"],
        [self placeholder:@"邮箱登录" symbol:@"envelope.fill" bg:UIColor.systemTealColor value:nil],
    ];

    // 组 C · 会话隐私（占位）
    IMPSGroup *groupC = [IMPSGroup new];
    groupC.header = @"会话隐私";
    groupC.footer = @"为你开始的每个新会话默认开启阅后自删。";
    groupC.rows = @[
        [self placeholder:@"自动删除消息" symbol:@"timer" bg:UIColor.systemOrangeColor value:@"关闭"],
    ];

    // 组 D · 谁能看到（占位，一整组 P2）
    IMPSGroup *groupD = [IMPSGroup new];
    groupD.header = @"谁能看到";
    groupD.footer = @"这些设置决定他人在你的资料页看到多少。";
    groupD.rows = @[
        [self placeholder:@"手机号码" symbol:@"phone.fill" bg:UIColor.systemGreenColor value:@"我的联系人"],
        [self placeholder:@"上次上线" symbol:@"eye.fill" bg:UIColor.systemBlueColor value:@"我的联系人"],
        [self placeholder:@"头像" symbol:@"person.crop.circle.fill" bg:UIColor.systemPurpleColor value:@"所有人"],
        [self placeholder:@"个人简介" symbol:@"text.alignleft" bg:UIColor.systemYellowColor value:@"所有人"],
        [self placeholder:@"生日" symbol:@"gift.fill" bg:UIColor.systemPinkColor value:@"我的联系人"],
    ];

    // 组 E · 数据（占位）
    IMPSGroup *groupE = [IMPSGroup new];
    groupE.header = @"数据";
    groupE.rows = @[
        [self placeholder:@"清除所有对话" symbol:@"trash.fill" bg:UIColor.systemGrayColor value:nil],
        [self placeholder:@"导出我的数据" symbol:@"arrow.up.doc.fill" bg:UIColor.systemBlueColor value:nil],
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
