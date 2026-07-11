//  IMSettingsViewController.m
//  「我」页：数据驱动的分组设置表（UITableViewStyleInsetGrouped）。
//  新增设置项 = 往 groups 数组里 append 一条 IMSettingsRow，渲染层不改。

#import "IMSettingsViewController.h"
#import "IMProfileEditViewController.h"
#import "IMBlockedListViewController.h"
#import "IMFavoritesViewController.h"
#import "IMLoginViewController.h"
#import "IMSocketManager.h"
#import "IMSessionStore.h"
#import "IMAnimator.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "UILabel+IMAvatar.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"

#pragma mark - 行模型（数据驱动单一来源）

/// 一行设置：图标（白色 SF Symbol + 彩色圆角底）+ 标题 + 可选右值 + 点击回调。
@interface IMSettingsRow : NSObject
@property (nonatomic, copy)   NSString *rowId;
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy, nullable) NSString *systemImage;
@property (nonatomic, strong, nullable) UIColor *iconBgColor;
@property (nonatomic, copy, nullable) NSString *rightValue;
@property (nonatomic, assign) BOOL destructive;   ///< 红字（退出登录）
@property (nonatomic, copy, nullable) void (^handler)(void);
@end

@implementation IMSettingsRow
+ (instancetype)rowWithId:(NSString *)rowId title:(NSString *)title image:(nullable NSString *)image
                  iconBg:(nullable UIColor *)iconBg right:(nullable NSString *)right
              destructive:(BOOL)destructive handler:(nullable void (^)(void))handler {
    IMSettingsRow *r = [IMSettingsRow new];
    r.rowId = rowId; r.title = title; r.systemImage = image;
    r.iconBgColor = iconBg; r.rightValue = right; r.destructive = destructive; r.handler = handler;
    return r;
}
@end

#pragma mark - 行 Cell（彩色图标方块 + 标题 + 右值 + chevron）

@interface IMSettingsCell : UITableViewCell
- (void)configureWithRow:(IMSettingsRow *)row;
@end

@implementation IMSettingsCell {
    UIImageView *_iconView;
    UIView *_iconBg;
    UILabel *_titleLabel;
    UILabel *_valueLabel;
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

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:17];
        _titleLabel.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_titleLabel];

        _valueLabel = [UILabel new];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [UIFont systemFontOfSize:16];
        _valueLabel.textColor = IMTheme.textSecondary;
        _valueLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_valueLabel];
        [_valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        [NSLayoutConstraint activateConstraints:@[
            [_iconBg.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [_iconBg.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconBg.widthAnchor constraintEqualToConstant:30],
            [_iconBg.heightAnchor constraintEqualToConstant:30],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:18],
            [_iconView.heightAnchor constraintEqualToConstant:18],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconBg.trailingAnchor constant:IMTheme.space3],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

            [_valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:IMTheme.space2],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithRow:(IMSettingsRow *)row {
    _titleLabel.text = row.title;
    _titleLabel.textColor = row.destructive ? UIColor.systemRedColor : IMTheme.textPrimary;
    _valueLabel.text = row.rightValue;

    BOOL hasIcon = row.systemImage.length > 0;
    _iconBg.hidden = !hasIcon;
    _iconView.image = hasIcon ? [UIImage systemImageNamed:row.systemImage] : nil;
    _iconBg.backgroundColor = row.iconBgColor ?: IMTheme.accent;

    self.accessoryType = row.destructive ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
}

@end

#pragma mark - 头部资料 Cell（圆形头像 + 昵称/uid）

@interface IMProfileHeaderCell : UITableViewCell
- (void)configureWithUserID:(NSString *)userID nickname:(nullable NSString *)nickname avatarURL:(nullable NSString *)avatarURL;
@end

@implementation IMProfileHeaderCell {
    UILabel *_avatar;
    UILabel *_name;
    UILabel *_uid;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 30;
        _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];

        _name = [UILabel new];
        _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
        _name.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_name];

        _uid = [UILabel new];
        _uid.translatesAutoresizingMaskIntoConstraints = NO;
        _uid.font = [UIFont systemFontOfSize:15];
        _uid.textColor = IMTheme.textSecondary;
        [self.contentView addSubview:_uid];

        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:60],
            [_avatar.heightAnchor constraintEqualToConstant:60],

            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:IMTheme.space3],
            [_name.topAnchor constraintEqualToAnchor:_avatar.topAnchor constant:6],
            [_name.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],

            [_uid.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_uid.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:4],
            [_uid.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        ]];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}
- (void)configureWithUserID:(NSString *)userID nickname:(nullable NSString *)nickname avatarURL:(nullable NSString *)avatarURL {
    NSString *display = nickname.length ? nickname : userID;
    [_avatar im_setAvatarURL:avatarURL seed:userID displayName:display]; // 有头像图渲染图，否则首字母圈
    _name.text = display;
    _uid.text = [NSString stringWithFormat:@"uid %@", userID];
}
@end

#pragma mark - 控制器

@interface IMSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSArray<IMSettingsRow *> *> *groups; // 普通分组（不含头部资料）
@property (nonatomic, copy, nullable) NSString *myNickname;  // 本人资料（拉取后填头部）
@property (nonatomic, copy, nullable) NSString *myAvatarURL;
@end

@implementation IMSettingsViewController

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
    self.title = @"我";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    [self buildGroups];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:IMSettingsCell.class forCellReuseIdentifier:@"row"];
    [self.tableView registerClass:IMProfileHeaderCell.class forCellReuseIdentifier:@"profile"];
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadMyProfile]; // 拉本人昵称/头像填头部（编辑保存后返回也会刷新）
}

/// 用已登录的 currentToken 拉本人资料，填头部昵称+头像；失败静默（头部回退 uid+首字母圈）。
- (void)loadMyProfile {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService myProfileWithToken:token completion:^(IMUserCard *_Nullable profile, NSError *_Nullable err) {
        if (err || !profile) { return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) ss = ws; if (!ss) { return; }
            ss.myNickname = profile.displayName;
            ss.myAvatarURL = profile.avatarURL;
            [ss.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
        });
    }];
}

/// 单一数据来源：section 0 永远是头部资料行；之后是 groups 各组。
- (void)buildGroups {
    __weak typeof(self) ws = self;

    // 组1（对齐 Telegram「我」页第一组）：收藏消息 / 最近通话 / 已登录设备 / 聊天文件夹。
    NSArray<IMSettingsRow *> *groupA = @[
        [IMSettingsRow rowWithId:@"saved" title:@"收藏消息" image:@"bookmark.fill"
                          iconBg:UIColor.systemBlueColor right:nil destructive:NO
                         handler:^{ [ws openFavorites]; }],
        [IMSettingsRow rowWithId:@"recentCalls" title:@"最近通话" image:@"phone.fill"
                          iconBg:UIColor.systemGreenColor right:nil destructive:NO
                         handler:^{ [ws comingSoon:@"最近通话"]; }],
        [IMSettingsRow rowWithId:@"devices" title:@"已登录设备" image:@"laptopcomputer"
                          iconBg:UIColor.systemOrangeColor right:nil destructive:NO
                         handler:^{ [ws comingSoon:@"已登录设备"]; }],
        [IMSettingsRow rowWithId:@"folders" title:@"聊天文件夹" image:@"folder.fill"
                          iconBg:UIColor.systemBlueColor right:nil destructive:NO
                         handler:^{ [ws comingSoon:@"聊天文件夹"]; }],
    ];

    NSArray<IMSettingsRow *> *groupB = @[
        [IMSettingsRow rowWithId:@"notifications" title:@"通知与提示音" image:@"bell.badge.fill"
                          iconBg:UIColor.systemRedColor right:nil destructive:NO
                         handler:^{ [ws comingSoon:@"通知与提示音"]; }],
        [IMSettingsRow rowWithId:@"privacy" title:@"隐私与安全" image:@"lock.fill"
                          iconBg:UIColor.systemGrayColor right:nil destructive:NO
                         handler:^{ [ws openBlocked]; }],
        [IMSettingsRow rowWithId:@"storage" title:@"数据与存储" image:@"externaldrive.fill"
                          iconBg:UIColor.systemGreenColor right:nil destructive:NO
                         handler:^{ [ws comingSoon:@"数据与存储"]; }],
        [IMSettingsRow rowWithId:@"appearance" title:@"外观" image:@"circle.lefthalf.filled"
                          iconBg:UIColor.systemBlueColor right:nil destructive:NO
                         handler:^{ [ws comingSoon:@"外观"]; }],
        [IMSettingsRow rowWithId:@"powerSaving" title:@"省电模式" image:@"bolt.fill"
                          iconBg:UIColor.systemYellowColor right:@"关闭" destructive:NO
                         handler:^{ [ws comingSoon:@"省电模式"]; }],
        [IMSettingsRow rowWithId:@"language" title:@"语言" image:@"globe"
                          iconBg:UIColor.systemPurpleColor right:@"简体中文" destructive:NO
                         handler:^{ [ws comingSoon:@"语言"]; }],
    ];

    NSArray<IMSettingsRow *> *groupC = @[
        [IMSettingsRow rowWithId:@"logout" title:@"退出登录" image:nil
                          iconBg:nil right:nil destructive:YES
                         handler:^{ [ws logout]; }],
    ];

    self.groups = @[groupA, groupB, groupC];
}

#pragma mark - 动作

- (void)comingSoon:(NSString *)title { [self im_showComingSoon:title]; }

- (void)openFavorites {
    IMFavoritesViewController *fav = [IMFavoritesViewController new];
    [self.navigationController pushViewController:fav animated:YES];
}

- (void)openProfile {
    IMProfileEditViewController *edit = [[IMProfileEditViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:edit animated:YES];
}

- (void)openBlocked {
    IMBlockedListViewController *blocked = [[IMBlockedListViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:blocked animated:YES];
}

- (void)logout {
    [IMSocketManager.sharedManager disconnect];
    [IMSessionStore clear]; // 退出登录：清持久化会话，下次启动回登录页
    UIWindow *window = self.view.window;
    IMLoginViewController *login = [IMLoginViewController new];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:login];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1 + (NSInteger)self.groups.count; // section 0 = 头部资料
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) { return 1; }
    return (NSInteger)self.groups[section - 1].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? 84 : 50;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        IMProfileHeaderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"profile" forIndexPath:indexPath];
        [cell configureWithUserID:self.userID nickname:self.myNickname avatarURL:self.myAvatarURL];
        return cell;
    }
    IMSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    [cell configureWithRow:self.groups[indexPath.section - 1][indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [IMAnimator selectionChanged];
    if (indexPath.section == 0) { [self openProfile]; return; }
    IMSettingsRow *row = self.groups[indexPath.section - 1][indexPath.row];
    if (row.handler) { row.handler(); }
}

@end
