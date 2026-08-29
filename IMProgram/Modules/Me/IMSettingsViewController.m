//  IMSettingsViewController.m
//  「我」页：数据驱动的分组设置表（UITableViewStyleInsetGrouped）。
//  新增设置项 = 往 groups 数组里 append 一条 IMSettingsRow，渲染层不改。

#import "IMSettingsViewController.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar / kIMLiquidBarHeight
#import "IMProfileEditViewController.h"
#import "IMQRCardViewController.h"
#import "IMContactShare.h"
#import "IMAppearanceViewController.h"
#import "IMDataStorageViewController.h"
#import "IMBlockedListViewController.h"
#import "IMPrivacySecurityViewController.h"
#import "IMDeviceListViewController.h"
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
#import "IMDropletHeaderMorph.h"
#import "IMProgram-Swift.h"
#import "IMAccountIdentity.h"

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
    NSString *display = IMDisplayName(nickname, nil);
    [_avatar im_setAvatarURL:avatarURL seed:userID displayName:display]; // 有头像图渲染图，否则首字母圈
    _name.text = display;
    _uid.text = [NSString stringWithFormat:@"uid %@", userID];
}
@end

#pragma mark - 控制器

@interface IMSettingsViewController () <UITableViewDataSource, UITableViewDelegate, IMLiquidNavigationBarDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSArray<IMSettingsRow *> *> *groups; // 普通分组（不含头部资料）
@property (nonatomic, copy, nullable) NSString *myNickname;  // 本人资料（拉取后填头部）
@property (nonatomic, copy, nullable) NSString *myAvatarURL;
@property (nonatomic, copy, nullable) NSString *myPhone;
@property (nonatomic, copy, nullable) NSString *myUsername; ///< 公开句柄，头部显示为 @xxx
@property (nonatomic, strong) UIView *profileHeader;
@property (nonatomic, strong) UIView *profileOverlay;
/// 静态坐标容器：承载头像 + 灵动岛 171pt 遮罩/覆盖层，与 IMChatDetailViewController 相同——
/// 遮罩挂到容器本身而不是缩到 55pt 的头像，避免大遮罩被头像 bounds 切成矩形。
@property (nonatomic, strong) UIView *dropletContainer;
@property (nonatomic, strong) UIView *dropletBottomCover;                     ///< Telegram bottomCoverNode
@property (nonatomic, strong) IMTelegramAvatarEffectsView *dropletTopCover;   ///< Telegram topCoverNode（blur+gradient+fade）
@property (nonatomic, strong) IMTelegramAvatarMaskView *dropletMask;          ///< 171pt UserAvatarMask（挂到 dropletContainer.maskView）
@property (nonatomic, strong) UILabel *profileAvatar;
@property (nonatomic, strong) UILabel *profileName;
@property (nonatomic, strong) UILabel *profileMeta;
@property (nonatomic, strong) IMLiquidNavigationBar *liquidNavigationBar;  ///< 「我」页沉浸式导航栏，与详情页对称
@property (nonatomic, strong) IMDropletHeaderMorph *headerMorph;           ///< 共享 Zone① 头部形变（与详情页同一套）
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

#pragma mark - 头部形变（滚动驱动，Zone① 由 IMDropletHeaderMorph 共享驱动）

- (void)buildProfileHeader {
    CGFloat W = self.view.bounds.size.width;
    // tableHeader 只负责为资料头部留出滚动空间；头像/文字悬浮在 table 之上，才能像详情页一样连续形变。
    self.profileHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 230)];
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

    // 名字/副标题不能挂到 dropletContainer——mask 会同时把它们裁掉；单独挂在 profileOverlay 上，保持完整可见。
    // 静态水滴容器：宽度铺满、位置钉在导航栏下方；头像/黑底/effects 都在其内部围绕 (W/2, top+72) 布局。
    self.dropletContainer = [UIView new];
    self.dropletContainer.backgroundColor = UIColor.clearColor;
    self.dropletContainer.userInteractionEnabled = NO;
    self.dropletContainer.clipsToBounds = NO;
    [self.view addSubview:self.dropletContainer];

    self.dropletBottomCover = [UIView new];
    self.dropletBottomCover.userInteractionEnabled = NO;
    self.dropletBottomCover.hidden = YES;
    self.dropletBottomCover.backgroundColor = [UIColor colorWithWhite:0 alpha:0];
    [self.dropletContainer addSubview:self.dropletBottomCover];

    self.profileAvatar = [UILabel new];
    self.profileAvatar.textAlignment = NSTextAlignmentCenter;
    self.profileAvatar.textColor = UIColor.whiteColor;
    self.profileAvatar.font = [UIFont systemFontOfSize:34 weight:UIFontWeightSemibold];
    self.profileAvatar.layer.masksToBounds = YES;
    [self.dropletContainer addSubview:self.profileAvatar];

    self.dropletTopCover = [[IMTelegramAvatarEffectsView alloc] initWithFrame:CGRectZero];
    self.dropletTopCover.userInteractionEnabled = NO;
    self.dropletTopCover.hidden = YES;
    [self.dropletContainer addSubview:self.dropletTopCover];

    // Lottie 遮罩：只在 q>0.03 时挂到 dropletContainer.maskView，其余时刻脱挂让所有子层完整可见。
    self.dropletMask = [[IMTelegramAvatarMaskView alloc] initWithFrame:CGRectZero];
    self.dropletMask.userInteractionEnabled = NO;

    self.profileName = [UILabel new];
    self.profileName.textAlignment = NSTextAlignmentCenter;
    self.profileName.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
    self.profileName.textColor = IMTheme.textPrimary;
    // 直接挂在 self.view（不是 profileOverlay），锁定后才能 bringSubviewToFront 到 bar 之上充当 title。
    [self.view addSubview:self.profileName];

    self.profileMeta = [UILabel new];
    self.profileMeta.textAlignment = NSTextAlignmentCenter;
    self.profileMeta.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    self.profileMeta.textColor = IMTheme.textSecondary;
    [self.view addSubview:self.profileMeta];
    [self refreshProfileHeader];
    [self applyProfileHeaderMorph];

    // 沉浸式导航栏：与 IMChatDetailViewController 完全对称，name 锁定时进到标题栏里。
    // 初始文本从 profileName 读取（refreshProfileHeader 已填）。
    NSString *nameText = self.profileName.text ?: @"";
    NSString *metaText = self.profileMeta.text ?: @"";
    self.liquidNavigationBar = [[IMLiquidNavigationBar alloc] initWithTitle:nameText
                                                                     subtitle:metaText
                                                                  actionTitle:@"编辑"];
    // 自持 bar：本页自绘沉浸式标题栏（导航容器不为 ownsBar 页注入栏），左（二维码）右（编辑）按钮由本 VC 直接配置并响应。
    self.liquidNavigationBar.delegate = self;
    self.liquidNavigationBar.leftImage = [UIImage systemImageNamed:@"qrcode"];
    self.liquidNavigationBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.liquidNavigationBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.liquidNavigationBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.liquidNavigationBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.liquidNavigationBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.liquidNavigationBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:kIMLiquidBarHeight],
    ]];
    [self.view bringSubviewToFront:self.profileName];
    [self.view bringSubviewToFront:self.profileMeta];

    // 共享 Zone① 头部形变驱动：与详情页 IMChatDetailViewController 同一套，改一处两页同步。
    self.headerMorph = [IMDropletHeaderMorph new];
    self.headerMorph.container = self.dropletContainer;
    self.headerMorph.avatar = self.profileAvatar;
    self.headerMorph.bottomCover = self.dropletBottomCover;
    self.headerMorph.topCover = self.dropletTopCover;
    self.headerMorph.mask = self.dropletMask;
    self.headerMorph.name = self.profileName;
    self.headerMorph.meta = self.profileMeta;
    self.headerMorph.bar = self.liquidNavigationBar;
    self.headerMorph.nameRestFont = 28;   // 我页 name 28pt（详情页 26pt）
    self.headerMorph.metaRestFont = 17;   // 我页 meta 17pt（详情页 15pt）
    self.headerMorph.metaFades = YES;     // 我页手机号·uid 迁移途中渐进淡出（详情页成员数不淡出）
    [self applyProfileHeaderMorph];
}

#pragma mark - IMLiquidNavigationBarDelegate（自持 bar 的左/右按钮响应）

- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { [self showQRCode]; }
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self showQRCode]; }
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { [self openProfile]; }

- (void)refreshProfileHeader {
    // 回退链止于昵称：userID 是 10 位内部数字 ID，露出来对用户毫无意义（见 ACCOUNT_IDENTITY_REDESIGN.md §5.2）。
    NSString *display = self.myNickname.length ? self.myNickname : (self.myUsername.length ? self.myUsername : @"未命名用户");
    self.profileName.text = display;
    // 副标题只放公开句柄；手机号有才补在前面。
    // 旧实现是 "<phone ?: userID> · @<userID>"，绝大多数账号没填手机号，于是渲染成 "1001 · @1001" 的重复，
    // 且 @ 后面跟的是内部 ID 而非真正的公开句柄。
    NSString *handle = self.myUsername.length ? [@"@" stringByAppendingString:self.myUsername] : @"";
    self.profileMeta.text = self.myPhone.length
        ? [NSString stringWithFormat:@"%@ · %@", self.myPhone, handle]
        : handle;
    [self.profileAvatar im_setAvatarURL:self.myAvatarURL seed:self.userID displayName:display];
    // topCover 必须盖在头像之上，才能把 blur/gradient/黑色 fade 应用到头像图像上。
    [self.dropletContainer bringSubviewToFront:self.dropletTopCover];
    [self applyProfileHeaderMorph];
}


/// 入口 ③：把自己的名片发到选中的会话。昵称用 `myNickname`（本人真实昵称，本人无"自己给自己的备注"之说）。
- (void)shareMyContactCard {
    [IMContactShare presentPickerFrom:self selfUID:self.userID userID:self.userID
                             nickname:self.myNickname avatarURL:self.myAvatarURL];
}
- (void)showQRCode {
    IMQRCardViewController *card = [[IMQRCardViewController alloc] initMyCardWithHost:self.host userID:self.userID
                                                                           nickname:self.myNickname avatarURL:self.myAvatarURL];
    [self.navigationController pushViewController:card animated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.title = @"";
    [self loadMyProfile]; // 拉本人昵称/头像填头部（编辑保存后返回也会刷新）
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.profileOverlay.frame = self.view.bounds;
    [self syncHeaderScrollRoom];
    [self applyProfileHeaderMorph];
}

/// #1：大屏机型（如 17 Pro Max）上「我」页内容常常一屏放得下 → tableView 不可滚 → raw 恒为 0 → name 永远
/// 不迁移进标题栏。这里补足底部 inset，保证最大 raw ≥ 收拢距离 H，让 name 能完整走到标题栏（migrate=1）。
- (void)syncHeaderScrollRoom {
    CGFloat viewH = self.tableView.bounds.size.height;
    if (viewH <= 0) { return; }
    CGFloat H = 144 + 8;   // 收拢距离 + 余量，确保 migrate 能到 1
    // 当前（不含我们要加的 bottom）能达到的最大 raw = contentOffset.y_max + adjustedContentInset.top。
    CGFloat safeBottom = self.tableView.adjustedContentInset.bottom - self.tableView.contentInset.bottom;
    CGFloat maxRawWithoutOurs = self.tableView.contentSize.height + safeBottom - viewH
                              + self.tableView.adjustedContentInset.top;
    CGFloat bottom = MAX(0, H - maxRawWithoutOurs);
    if (ABS(self.tableView.contentInset.bottom - bottom) > 0.5) {
        UIEdgeInsets in = self.tableView.contentInset;
        in.bottom = bottom;
        self.tableView.contentInset = in;
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // 3(2) 下拉钳制：顶部橡皮筋最多 44pt 即钳住，配合共享驱动 off≥0 冻结 → 头像与 name 永不重叠。
    CGFloat minY = -scrollView.adjustedContentInset.top - 44;
    if (scrollView.contentOffset.y < minY) {
        scrollView.contentOffset = CGPointMake(scrollView.contentOffset.x, minY);
    }
    [self applyProfileHeaderMorph];
    // 本页自持标题栏（容器对自持页早退、不注入），滚动期间无需再驱动容器布局。
}

/// Zone① 松手临界吸附（与详情页共用同一驱动）。raw = contentOffset.y + adjustedContentInset.top。
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity
                    targetContentOffset:(inout CGPoint *)targetContentOffset {
    CGFloat adj = scrollView.adjustedContentInset.top;
    CGFloat H = 144;
    CGFloat offNow = scrollView.contentOffset.y + adj;
    CGFloat projRaw = targetContentOffset->y + adj;
    if (offNow < H && projRaw < H) {
        CGFloat snap = [IMDropletHeaderMorph snapTargetForOffset:offNow velocity:velocity.y collapseOffset:H];
        if (snap >= 0) { targetContentOffset->y = snap - adj; }  // 换回 contentOffset 坐标
    }
}

- (CGFloat)im_navigationBackgroundProgress {
    CGFloat raw = self.tableView.contentOffset.y + self.tableView.adjustedContentInset.top;
    CGFloat progress = MIN(MAX(raw / 120.0, 0), 1);
    return progress * progress * (3 - 2 * progress);
}

- (void)applyProfileHeaderMorph {
    CGFloat W = self.view.bounds.size.width;
    if (W <= 0 || !self.profileAvatar) { return; }
    // raw = 相对页面顶部的滚动距离（主导航额外 +56 safe-area 已计入 adjustedContentInset）。
    CGFloat raw = self.tableView.contentOffset.y + self.tableView.adjustedContentInset.top;
    // Zone① 全部形变交给共享驱动（与详情页同一套）；topInset 用设备状态栏 inset。
    // 驱动内部 off=MAX(0,raw)：下拉(raw<0)时头像/name 冻结在 rest，天然不会与 name 重叠（配合下方钳制）。
    self.headerMorph.topInset = self.view.window.safeAreaInsets.top;
    self.headerMorph.collapseOffset = 144;
    [self.headerMorph applyForOffset:raw width:W];

    // title 保持空（不用共享 bar 的 title）——profileName 标签本身承担标题角色。
    if (self.title.length) {
        self.title = @"";
        [self im_refreshNavigationBar];
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
            ss.myUsername = profile.username;
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
                         handler:^{ [ws openDevices]; }],
        [IMSettingsRow rowWithId:@"folders" title:@"聊天文件夹" image:@"folder.fill"
                          iconBg:UIColor.systemBlueColor right:nil destructive:NO
                         handler:^{ [ws comingSoon:@"聊天文件夹"]; }],
        // 入口 ③「分享我的名片」（CONTACT_CARD_DESIGN §4.4）：与左上角的「我的二维码」并列——
        // 二维码给**面对面**，名片消息给**线上**。
        [IMSettingsRow rowWithId:@"shareMyCard" title:@"分享我的名片" image:@"person.crop.square"
                          iconBg:UIColor.systemTealColor right:nil destructive:NO
                         handler:^{ [ws shareMyContactCard]; }],
    ];

    NSArray<IMSettingsRow *> *groupB = @[
        [IMSettingsRow rowWithId:@"notifications" title:@"通知与提示音" image:@"bell.badge.fill"
                          iconBg:UIColor.systemRedColor right:nil destructive:NO
                         handler:^{ [ws comingSoon:@"通知与提示音"]; }],
        [IMSettingsRow rowWithId:@"privacy" title:@"隐私与安全" image:@"lock.fill"
                          iconBg:UIColor.systemGrayColor right:nil destructive:NO
                         handler:^{ [ws openBlocked]; }],
        [IMSettingsRow rowWithId:@"storage" title:@"数据和存储" image:@"externaldrive.fill"
                          iconBg:UIColor.systemGreenColor right:nil destructive:NO
                         handler:^{ [ws.navigationController pushViewController:[IMDataStorageViewController new] animated:YES]; }],
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
    // 「隐私与安全」入口改为容器页——不再直接跳黑名单。
    // 容器内首行「已屏蔽的用户」再 push IMBlockedListViewController，保留旧路径。
    IMPrivacySecurityViewController *vc = [[IMPrivacySecurityViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openDevices {
    IMDeviceListViewController *devices = [[IMDeviceListViewController alloc] initWithHost:self.host userID:self.userID];
    [self.navigationController pushViewController:devices animated:YES];
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
