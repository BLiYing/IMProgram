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
#import "IMProgram-Swift.h"

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

@interface IMSettingsViewController () <UITableViewDataSource, UITableViewDelegate, IMLiquidNavigationBarDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSArray<IMSettingsRow *> *> *groups; // 普通分组（不含头部资料）
@property (nonatomic, copy, nullable) NSString *myNickname;  // 本人资料（拉取后填头部）
@property (nonatomic, copy, nullable) NSString *myAvatarURL;
@property (nonatomic, copy, nullable) NSString *myPhone;
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

#pragma mark - 头部形变（滚动驱动）

static CGFloat IMClamp(CGFloat x, CGFloat a, CGFloat b) { return MIN(MAX(x, a), b); }
static CGFloat IMSmooth(CGFloat x) { x = IMClamp(x, 0, 1); return x * x * (3 - 2 * x); }

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
    // 自持 bar：共享 imLiquidBar 对本页已隐藏，左（二维码）右（编辑）按钮必须由本 VC 直接配置并响应。
    self.liquidNavigationBar.delegate = self;
    self.liquidNavigationBar.leftImage = [UIImage systemImageNamed:@"qrcode"];
    self.liquidNavigationBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.liquidNavigationBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.liquidNavigationBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.liquidNavigationBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.liquidNavigationBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.liquidNavigationBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:56],
    ]];
    [self.view bringSubviewToFront:self.profileName];
    [self.view bringSubviewToFront:self.profileMeta];
}

#pragma mark - IMLiquidNavigationBarDelegate（自持 bar 的左/右按钮响应）

- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar { [self showQRCode]; }
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar { [self showQRCode]; }
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar { [self openProfile]; }

- (void)refreshProfileHeader {
    NSString *display = self.myNickname.length ? self.myNickname : self.userID;
    self.profileName.text = display;
    NSString *phone = self.myPhone.length ? self.myPhone : self.userID;
    self.profileMeta.text = [NSString stringWithFormat:@"%@ · @%@", phone, self.userID];
    [self.profileAvatar im_setAvatarURL:self.myAvatarURL seed:self.userID displayName:display];
    // topCover 必须盖在头像之上，才能把 blur/gradient/黑色 fade 应用到头像图像上。
    [self.dropletContainer bringSubviewToFront:self.dropletTopCover];
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
    [self.navigationController.view setNeedsLayout];
}

- (CGFloat)im_navigationBackgroundProgress {
    CGFloat raw = self.tableView.contentOffset.y + self.tableView.adjustedContentInset.top;
    CGFloat progress = MIN(MAX(raw / 120.0, 0), 1);
    return progress * progress * (3 - 2 * progress);
}

- (void)applyProfileHeaderMorph {
    CGFloat W = self.view.bounds.size.width;
    if (W <= 0 || !self.profileAvatar) { return; }
    CGFloat raw = self.tableView.contentOffset.y + self.tableView.adjustedContentInset.top;
    // Telegram PeerInfoHeaderNode: contentOffset / 120 驱动灵动岛遮罩（maskValue）。
    CGFloat q = MIN(MAX(raw / 120.0, 0), 1);
    // 头像缩放/上移吃 titleCollapseFraction = contentOffset / 128（`PeerInfoHeaderNode.swift` L1624/L1759），
    // 与 maskValue 微异步是 Telegram 原始节奏。
    CGFloat tcf = MIN(MAX(raw / 128.0, 0), 1);
    // 本页由主导航额外增加 56pt safe-area；头像基准必须使用设备状态栏 inset，避免落到标题栏下方。
    CGFloat top = self.view.window.safeAreaInsets.top;
    // 与 IMChatDetailViewController 完全对齐：restD=100（=avatarSize），restCY=top+72（=statusBarHeight+22+50）。
    // 只有头像等于 171pt Lottie 圆内接尺寸时，露出的差集才会最小，暗色是随进度慢慢出现的一圈，
    // 而不是一滑动就把黑色 bottomCover 整片让出来。
    CGFloat restD = 100;
    CGFloat restCY = top + 72;
    CGFloat avatarScale = 1 - 0.45 * tcf;
    CGFloat diameter = restD * avatarScale;
    // avatarOffset = apparentTitleLockOffset(7·tcf) + 10·tcf = 17·tcf（L1660/L1760）。
    CGFloat cy = restCY - raw + 17 * tcf;

    // 静态水滴容器：高度覆盖遮罩带 + rest 头像。所有 mask/covers 在容器坐标系内以固定像素坐标定位，
    // 头像上滑期间它们保持在灵动岛下方（屏幕 Y 47.5..218.5）不动。
    CGRect containerFrame = CGRectMake(0, 0, W, MAX(restCY + restD / 2 + 8, 260));
    if (!CGRectEqualToRect(self.dropletContainer.frame, containerFrame)) {
        self.dropletContainer.frame = containerFrame;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // 头像在容器坐标系内移动/缩放。始终保持 cornerRadius=r（圆形），
    // 由 dropletContainer.maskView 进一步塑成水滴——避免出现方形被切割的过渡瞬间。
    self.profileAvatar.transform = CGAffineTransformIdentity;
    self.profileAvatar.frame = CGRectMake(W / 2 - diameter / 2, cy - diameter / 2, diameter, diameter);
    self.profileAvatar.layer.cornerRadius = diameter / 2;

    CGRect maskFrame = CGRectMake(W / 2 - 85.5, 47.5, 171, 171);
    self.dropletBottomCover.frame = maskFrame;
    self.dropletTopCover.frame = maskFrame;
    self.dropletMask.frame = maskFrame;

    if (q > 0.03) {
        self.dropletBottomCover.hidden = NO;
        self.dropletBottomCover.backgroundColor = [UIColor colorWithWhite:0 alpha:q];
        self.dropletTopCover.hidden = NO;
        [self.dropletTopCover setProgress:q];
        [self.dropletMask setProgress:q];
        if (self.dropletContainer.maskView != self.dropletMask) {
            self.dropletContainer.maskView = self.dropletMask;
        }
    } else {
        self.dropletBottomCover.hidden = YES;
        self.dropletBottomCover.backgroundColor = [UIColor colorWithWhite:0 alpha:0];
        self.dropletTopCover.hidden = YES;
        [self.dropletTopCover setProgress:0];
        [self.dropletMask setProgress:0];
        if (self.dropletContainer.maskView != nil) {
            self.dropletContainer.maskView = nil;
        }
    }
    [CATransaction commit];
    self.profileAvatar.alpha = 1;

    // 与详情页 IMChatDetailViewController 同一套：profileName 以【更慢】速度上移（从第 1pt 起就与头像/
    // 水滴拉开距离、永远留在水滴下方），到达标题栏行后【锁死】不再上移；profileMeta（手机号·@uid）与
    // name 共用同一 shift → 恒定间距一起上移。缩放与迁移进度同步。
    // 本页自持 liquidNavigationBar（共享 imLiquidBar 已隐藏），profileName bringSubviewToFront 到 bar 之上，
    // 锁点取 top+19（bar title 中心）——name 缩放上移后居中进标题栏，与详情页完全对称。
    CGFloat nameH = 34, metaH = 22;
    CGFloat staticRestNameTop = restCY + restD / 2 + 8;               // 用静态 restCY，不含 -raw
    CGFloat staticRestNameCenterY = staticRestNameTop + nameH / 2;

    CGFloat kNameSpeed = 0.85;              // < 1 → 与头像拉开距离
    CGFloat kLockCenterY = top + 19;        // 锁到自持 bar 的 title 中心（同详情页），name 居中进标题栏
    CGFloat nameCenterY = MAX(kLockCenterY, staticRestNameCenterY - kNameSpeed * raw);
    CGFloat nameShift = nameCenterY - staticRestNameCenterY;          // ≤ 0
    CGFloat migrate = (staticRestNameCenterY > kLockCenterY)
        ? MIN(MAX(nameShift / (kLockCenterY - staticRestNameCenterY), 0), 1) : 0;
    CGFloat titleScale = 1.0 - (1.0 - 17.0 / 28.0) * migrate;   // 28pt name → ≈17pt
    CGFloat metaScale  = 1.0 - (1.0 - 13.0 / 17.0) * migrate;   // 17pt meta → ≈13pt

    // 写 frame 前先复位 transform，避免 UIKit 反解出现漂移。
    self.profileName.transform = CGAffineTransformIdentity;
    self.profileMeta.transform = CGAffineTransformIdentity;
    self.profileName.frame = CGRectMake(0, staticRestNameTop, W, nameH);
    self.profileMeta.frame = CGRectMake(0, staticRestNameTop + nameH + 2, W, metaH);  // 与 name 固定间距
    self.profileName.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, nameShift), titleScale, titleScale);
    self.profileMeta.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, nameShift), metaScale, metaScale);
    self.profileName.alpha = 1;
    self.profileMeta.alpha = 1.0 - migrate;   // 一起上移、恒定间距，同时渐进淡出（migrate=1 时完全透明）

    // 自持导航栏配置（与详情页对称）：profileName 标签本身承担 title，禁用 bar 的内置 title 显示。
    self.liquidNavigationBar.compactContentProgress = 0;
    self.liquidNavigationBar.immersiveAppearanceProgress = 0;
    self.liquidNavigationBar.backgroundEffectProgress = IMSmooth((tcf - 0.28) / 0.72);

    // title 保持空（不用共享 bar 的 title）——profileName 标签本身承担标题角色。
    if (self.title.length) {
        self.title = @"";
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
