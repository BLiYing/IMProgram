//  IMSettingsViewController.m
//  「我」页：数据驱动的分组设置表（UITableViewStyleInsetGrouped）。
//  新增设置项 = 往 groups 数组里 append 一条 IMSettingsRow，渲染层不改。

#import "IMSettingsViewController.h"
#import "IMProfileEditViewController.h"
#import "IMAppearanceViewController.h"
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
#import "IMGlass.h"

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
@property (nonatomic, copy, nullable) NSString *myPhone;
@property (nonatomic, strong) UIView *profileHeader;
@property (nonatomic, strong) UIView *profileOverlay;
@property (nonatomic, strong) UILabel *profileAvatar;
@property (nonatomic, strong) UILabel *profileName;
@property (nonatomic, strong) UILabel *profileMeta;
@property (nonatomic, strong) CAShapeLayer *profileAvatarMask;
@property (nonatomic, strong) UIVisualEffectView *profileAvatarBlur;
@property (nonatomic, strong) UIView *profileAvatarFade;
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
    self.title = @"";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    [self buildGroups];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:IMSettingsCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:self.tableView];
    [self buildProfileHeader];
}

- (void)buildProfileHeader {
    CGFloat W = self.view.bounds.size.width;
    // tableHeader 只负责为资料头部留出滚动空间；头像/文字悬浮在 table 之上，才能像详情页一样连续形变。
    self.profileHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 350)];
    self.profileHeader.backgroundColor = UIColor.clearColor;
    self.tableView.tableHeaderView = self.profileHeader;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"qrcode"]
                                         style:UIBarButtonItemStylePlain target:self action:@selector(showQRCode)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel = @"我的二维码";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"编辑" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(openProfile)];

    self.profileOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    self.profileOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.profileOverlay.backgroundColor = UIColor.clearColor;
    self.profileOverlay.userInteractionEnabled = NO;
    [self.view addSubview:self.profileOverlay];

    self.profileAvatar = [UILabel new];
    self.profileAvatar.textAlignment = NSTextAlignmentCenter;
    self.profileAvatar.textColor = UIColor.whiteColor;
    self.profileAvatar.font = [UIFont systemFontOfSize:34 weight:UIFontWeightSemibold];
    self.profileAvatar.layer.masksToBounds = YES;
    [self.profileOverlay addSubview:self.profileAvatar];

    self.profileAvatarBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.profileAvatarBlur.userInteractionEnabled = NO;
    self.profileAvatarBlur.alpha = 0;
    [self.profileAvatar addSubview:self.profileAvatarBlur];
    self.profileAvatarFade = [UIView new];
    self.profileAvatarFade.backgroundColor = UIColor.blackColor;
    self.profileAvatarFade.userInteractionEnabled = NO;
    self.profileAvatarFade.alpha = 0;
    [self.profileAvatar addSubview:self.profileAvatarFade];

    self.profileName = [UILabel new];
    self.profileName.textAlignment = NSTextAlignmentCenter;
    self.profileName.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
    self.profileName.textColor = IMTheme.textPrimary;
    [self.profileOverlay addSubview:self.profileName];

    self.profileMeta = [UILabel new];
    self.profileMeta.textAlignment = NSTextAlignmentCenter;
    self.profileMeta.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    self.profileMeta.textColor = IMTheme.textSecondary;
    [self.profileOverlay addSubview:self.profileMeta];
    [self refreshProfileHeader];
    [self applyProfileHeaderMorph];
}

- (void)refreshProfileHeader {
    NSString *display = self.myNickname.length ? self.myNickname : self.userID;
    self.profileName.text = display;
    NSString *phone = self.myPhone.length ? self.myPhone : self.userID;
    self.profileMeta.text = [NSString stringWithFormat:@"%@ · @%@", phone, self.userID];
    [self.profileAvatar im_setAvatarURL:self.myAvatarURL seed:self.userID displayName:display];
    [self.profileAvatar bringSubviewToFront:self.profileAvatarBlur];
    [self.profileAvatar bringSubviewToFront:self.profileAvatarFade];
    [self applyProfileHeaderMorph];
}

- (void)showQRCode {
    [self im_showComingSoon:@"我的二维码"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.title = @"";
    [self loadMyProfile]; // 拉本人昵称/头像填头部（编辑保存后返回也会刷新）
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.profileOverlay.frame = self.view.bounds;
    [self applyProfileHeaderMorph];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self applyProfileHeaderMorph];
}

- (void)applyProfileHeaderMorph {
    CGFloat W = self.view.bounds.size.width;
    if (W <= 0 || !self.profileAvatar) { return; }
    CGFloat raw = self.tableView.contentOffset.y + self.tableView.adjustedContentInset.top;
    CGFloat linear = MIN(MAX(raw / 170.0, 0), 1);
    CGFloat q = linear * linear * (3 - 2 * linear);
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat restD = MIN(132, W * 0.34);
    CGFloat restCY = top + 154;
    CGFloat islandBottom = MAX(36, top - 8);
    CGFloat contactEnd = 0.40;
    CGFloat swallow = 0, w = restD, h = restD, cy = restCY;
    BOOL attached = q >= contactEnd;
    if (!attached) {
        CGFloat c = q / contactEnd;
        c = c * c * (3 - 2 * c);
        w = h = restD + (64 - restD) * c;
        cy = restCY + (islandBottom + h * 0.5 - 2 - restCY) * c;
    } else {
        swallow = (q - contactEnd) / (1 - contactEnd);
        swallow = swallow * swallow * (3 - 2 * swallow);
        w = 64 + (18 - 64) * swallow;
        h = 64 + (6 - 64) * swallow;
        cy = islandBottom - 5 + h * 0.5;
    }
    self.profileAvatar.transform = CGAffineTransformIdentity;
    self.profileAvatar.frame = CGRectMake((W - w) / 2, cy - h / 2, w, h);
    self.profileAvatar.layer.cornerRadius = attached ? 0 : MIN(w, h) / 2;
    self.profileAvatarBlur.frame = self.profileAvatar.bounds;
    self.profileAvatarFade.frame = self.profileAvatar.bounds;
    self.profileAvatarBlur.alpha = MAX(0, MIN(1, swallow * 1.10 - 0.10));
    self.profileAvatarFade.alpha = MAX(0, MIN(1, swallow * 1.55 - 0.25));

    if (!attached) {
        self.profileAvatar.layer.mask = nil;
    } else {
        if (!self.profileAvatarMask) { self.profileAvatarMask = [CAShapeLayer layer]; }
        CGFloat cx = w * 0.5;
        CGFloat shoulder = w * (0.49 - 0.10 * swallow);
        CGFloat neckHalf = MAX(2, w * (0.17 - 0.05 * swallow));
        CGFloat neckY = h * (0.13 + 0.08 * swallow);
        CGFloat bellyY = h * (0.43 + 0.04 * swallow);
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(cx - neckHalf, 0)];
        [path addLineToPoint:CGPointMake(cx + neckHalf, 0)];
        [path addCurveToPoint:CGPointMake(cx + shoulder, bellyY)
                controlPoint1:CGPointMake(cx + neckHalf, neckY)
                controlPoint2:CGPointMake(cx + shoulder, h * 0.19)];
        [path addCurveToPoint:CGPointMake(cx, h)
                controlPoint1:CGPointMake(cx + shoulder, h * 0.78)
                controlPoint2:CGPointMake(cx + w * 0.20, h)];
        [path addCurveToPoint:CGPointMake(cx - shoulder, bellyY)
                controlPoint1:CGPointMake(cx - w * 0.20, h)
                controlPoint2:CGPointMake(cx - shoulder, h * 0.78)];
        [path addCurveToPoint:CGPointMake(cx - neckHalf, 0)
                controlPoint1:CGPointMake(cx - shoulder, h * 0.20)
                controlPoint2:CGPointMake(cx - neckHalf, neckY)];
        [path closePath];
        self.profileAvatarMask.frame = self.profileAvatar.bounds;
        self.profileAvatarMask.path = path.CGPath;
        self.profileAvatar.layer.mask = self.profileAvatarMask;
    }

    CGFloat labelsAlpha = MIN(MAX(1 - q * 2.3, 0), 1);
    CGFloat nameY = cy + h / 2 + 18;
    self.profileName.frame = CGRectMake(20, nameY, W - 40, 40);
    self.profileMeta.frame = CGRectMake(20, nameY + 43, W - 40, 26);
    self.profileName.alpha = labelsAlpha;
    self.profileMeta.alpha = labelsAlpha;
    self.profileAvatar.alpha = swallow > 0.88 ? MAX(0, 1 - (swallow - 0.88) / 0.12) : 1;

    NSString *display = self.myNickname.length ? self.myNickname : self.userID;
    NSString *wantedTitle = q > 0.72 ? display : @"";
    if (![self.title isEqualToString:wantedTitle]) {
        self.title = wantedTitle;
        [self.navigationController.view setNeedsLayout];
    }
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
            ss.myPhone = profile.phone;
            [ss refreshProfileHeader];
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
                         handler:^{ [ws.navigationController pushViewController:[IMAppearanceViewController new] animated:YES]; }],
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
    return (NSInteger)self.groups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.groups[section].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 50;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    [cell configureWithRow:self.groups[indexPath.section][indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [IMAnimator selectionChanged];
    IMSettingsRow *row = self.groups[indexPath.section][indexPath.row];
    if (row.handler) { row.handler(); }
}

@end
