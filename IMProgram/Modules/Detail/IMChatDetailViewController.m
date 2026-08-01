//  IMChatDetailViewController.m

#import "IMChatDetailViewController.h"
#import "IMChatDetailTabs.h"
#import "IMGroupManageViewController.h"

#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMProtocol.h"
#import "IMDatabase.h"
#import "IMMessageModel.h"
#import "IMConversation.h"
#import "IMGroupInfo.h"
#import "IMUserCard.h"

#import "IMChatViewController.h"
#import "IMGroupMemberPickerViewController.h"
#import "IMConversationMediaViewController.h"
#import "IMMediaViewerViewController.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaUtil.h"
#import "IMPopoverCard.h"
#import "IMGlass.h"
#import "UILabel+IMAvatar.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import <objc/runtime.h>
#import "IMProgram-Swift.h"

#pragma mark - 形变头像视图（图片铺满 + 首字母回退，圆角随外部调节；供头部形变用）

/// 形变头像：容器负责圆角/裁剪（随滚动 morph）。**首字母底 + 图片都用 frame-based 子视图，layoutSubviews
/// 显式铺满**——用全局同款 `IMImageLoader` + `avatarColorForSeed`（视觉与列表/成员一致），但不嵌约束到 label
/// （之前把约束图钉在 0×0 起步的 frame-based label 上，约束解析不出尺寸→图停在 0×0，只剩浅色底=空白怪形）。
@interface IMDetailAvatarView : UIView
@property (nonatomic, strong) UILabel *letter;
@property (nonatomic, strong) UIImageView *photo;
- (void)setAvatarURL:(nullable NSString *)url seed:(NSString *)seed name:(nullable NSString *)name;
- (void)applyAbsorptionMaskProgress:(CGFloat)progress;
@end

@implementation IMDetailAvatarView {
    NSUInteger _token;
    CAShapeLayer *_absorptionMask;
    UIVisualEffectView *_absorptionBlur;
    UIView *_absorptionFade;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        _letter = [[UILabel alloc] initWithFrame:self.bounds];
        _letter.textAlignment = NSTextAlignmentCenter;
        _letter.textColor = UIColor.whiteColor;
        [self addSubview:_letter];
        _photo = [[UIImageView alloc] initWithFrame:self.bounds];
        _photo.contentMode = UIViewContentModeScaleAspectFill;
        _photo.clipsToBounds = YES;
        _photo.hidden = YES;
        [self addSubview:_photo];                 // 图在首字母之上
        // Telegram 的吸附不只改变轮廓，还会随着遮罩进度增加暗色模糊和黑色覆盖，
        // 让头像在接近系统黑色灵动岛时自然“融进去”。
        _absorptionBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        _absorptionBlur.userInteractionEnabled = NO;
        _absorptionBlur.alpha = 0;
        [self addSubview:_absorptionBlur];
        _absorptionFade = [UIView new];
        _absorptionFade.userInteractionEnabled = NO;
        _absorptionFade.backgroundColor = UIColor.blackColor;
        _absorptionFade.alpha = 0;
        [self addSubview:_absorptionFade];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _letter.frame = self.bounds;
    _photo.frame = self.bounds;                   // 显式铺满，随 morph 每帧更新
    _absorptionBlur.frame = self.bounds;
    _absorptionFade.frame = self.bounds;
    _letter.font = [UIFont systemFontOfSize:MAX(10, self.bounds.size.width * 0.4) weight:UIFontWeightSemibold];
}
- (void)setAvatarURL:(NSString *)url seed:(NSString *)seed name:(NSString *)name {
    NSString *n = name.length ? name : seed;
    _letter.text = n.length >= 2 ? [n substringFromIndex:n.length - 2] : n;
    self.backgroundColor = [IMTheme avatarColorForSeed:seed];
    _photo.image = nil; _photo.hidden = YES;
    NSUInteger token = ++_token;
    if (url.length == 0) { return; }
    __weak typeof(self) ws = self;
    [[IMImageLoader shared] loadImageURL:url completion:^(UIImage *img) {
        __strong typeof(ws) self = ws;
        if (!self || !img || token != self->_token) { return; }
        self->_photo.image = img;
        self->_photo.frame = self.bounds;          // 应用时再钉一次 frame，防止 0×0 起步残留
        self->_photo.hidden = NO;
    }];
}
- (void)applyAbsorptionMaskProgress:(CGFloat)progress {
    progress = MIN(MAX(progress, 0), 1);
    if (progress <= 0.001 || CGRectIsEmpty(self.bounds)) {
        self.layer.mask = nil;
        _absorptionBlur.alpha = 0;
        _absorptionFade.alpha = 0;
        return;
    }

    if (!_absorptionMask) { _absorptionMask = [CAShapeLayer layer]; }
    CGFloat w = CGRectGetWidth(self.bounds), h = CGRectGetHeight(self.bounds);
    CGFloat cx = w * 0.5;
    // 顶部使用短平口藏入灵动岛下方，随后以两段连续贝塞尔曲线形成窄颈和圆润腹部。
    // 相比尖头水滴，这种“桥接/融合”轮廓更接近 Telegram 的 UserAvatarMask 动画。
    CGFloat shoulder = w * (0.49 - 0.10 * progress);
    CGFloat neckHalf = MAX(2, w * (0.17 - 0.05 * progress));
    CGFloat neckY = h * (0.13 + 0.08 * progress);
    CGFloat bellyY = h * (0.43 + 0.04 * progress);
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
    _absorptionMask.frame = self.bounds;
    _absorptionMask.path = path.CGPath;
    self.layer.mask = _absorptionMask;
    _absorptionBlur.alpha = MIN(MAX(-0.10 + progress * 1.10, 0), 1);
    _absorptionFade.alpha = MIN(MAX(-0.25 + progress * 1.55, 0), 1);
}
@end

#pragma mark - 成员行 Cell

@interface IMDetailMemberCell : UITableViewCell
- (void)configureWithMember:(IMGroupMember *)m isMe:(BOOL)isMe;
@end

@implementation IMDetailMemberCell {
    UILabel *_avatar; UILabel *_name; UILabel *_sub; UILabel *_role;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        _avatar = [UILabel new]; _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor; _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 20; _avatar.layer.masksToBounds = YES;
        [self.contentView addSubview:_avatar];
        _name = [UILabel new]; _name.translatesAutoresizingMaskIntoConstraints = NO;
        _name.font = [UIFont systemFontOfSize:16]; _name.textColor = IMTheme.textPrimary;
        [self.contentView addSubview:_name];
        _sub = [UILabel new]; _sub.translatesAutoresizingMaskIntoConstraints = NO;
        _sub.font = [UIFont systemFontOfSize:12]; _sub.textColor = IMTheme.textSecondary;
        [self.contentView addSubview:_sub];
        _role = [UILabel new]; _role.translatesAutoresizingMaskIntoConstraints = NO;
        _role.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium]; _role.textAlignment = NSTextAlignmentCenter;
        _role.layer.cornerRadius = 8; _role.layer.masksToBounds = YES;
        [self.contentView addSubview:_role];
        [_role setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_role setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
            [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:40], [_avatar.heightAnchor constraintEqualToConstant:40],
            [_name.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [_name.topAnchor constraintEqualToAnchor:_avatar.topAnchor],
            [_name.trailingAnchor constraintLessThanOrEqualToAnchor:_role.leadingAnchor constant:-8],
            [_sub.leadingAnchor constraintEqualToAnchor:_name.leadingAnchor],
            [_sub.topAnchor constraintEqualToAnchor:_name.bottomAnchor constant:2],
            [_role.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_role.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_role.heightAnchor constraintEqualToConstant:20],
            [_role.widthAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
    }
    return self;
}
- (void)configureWithMember:(IMGroupMember *)m isMe:(BOOL)isMe {
    [_avatar im_setAvatarURL:m.avatarURL seed:m.userID displayName:m.displayName];
    _name.text = isMe ? [NSString stringWithFormat:@"%@（我）", m.displayName] : m.displayName;
    _sub.text = m.userID;
    if (m.role == IMGroupRoleOwner) {
        _role.hidden = NO; _role.text = @"群主"; _role.textColor = IMTheme.accent;
        _role.backgroundColor = [IMTheme.accent colorWithAlphaComponent:0.15];
    } else if (m.role == IMGroupRoleAdmin) {
        _role.hidden = NO; _role.text = @"管理员"; _role.textColor = UIColor.systemGreenColor;
        _role.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.15];
    } else {
        _role.hidden = YES; _role.text = @"";
    }
}
@end

#pragma mark - 媒体宫格 Cell（内嵌 3 列 CollectionView，供「媒体」页签内联展示）

@interface IMDetailMediaGridCell : UICollectionViewCell
- (void)configureWithItem:(IMMediaItem *)item;
@end
@implementation IMDetailMediaGridCell {
    UIImageView *_thumb; UIImageView *_play; NSString *_url;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _thumb = [UIImageView new];
        _thumb.contentMode = UIViewContentModeScaleAspectFill; _thumb.clipsToBounds = YES;
        _thumb.backgroundColor = UIColor.tertiarySystemFillColor;
        _thumb.frame = self.contentView.bounds;
        _thumb.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.contentView addSubview:_thumb];
        _play = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.circle.fill"]];
        _play.tintColor = UIColor.whiteColor; _play.hidden = YES;
        _play.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_play];
        [NSLayoutConstraint activateConstraints:@[
            [_play.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_play.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}
- (void)configureWithItem:(IMMediaItem *)item {
    _url = item.url; _thumb.image = nil; _play.hidden = !item.isVideo;
    __weak typeof(self) ws = self; NSString *want = item.url;
    void (^apply)(UIImage *) = ^(UIImage *img) {
        __strong typeof(ws) self = ws;
        if (self && [self->_url isEqualToString:want]) { self->_thumb.image = img; }
    };
    if (item.isVideo) { [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:item.url completion:apply]; }
    else { [[IMImageLoader shared] loadImageURL:item.url completion:apply]; }
}
- (void)prepareForReuse { [super prepareForReuse]; _thumb.image = nil; }
@end

@interface IMDetailMediaContainerCell : UITableViewCell <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy, nullable) void (^onPick)(IMMediaItem *item);
- (void)setItems:(NSArray<IMMediaItem *> *)items;
+ (CGFloat)heightForCount:(NSInteger)count width:(CGFloat)width;
@end
@implementation IMDetailMediaContainerCell {
    UICollectionView *_cv; NSArray<IMMediaItem *> *_items;
}
+ (CGFloat)tileForWidth:(CGFloat)width { CGFloat cols = 3, sp = 2; return floor((width - (cols - 1) * sp) / cols); }
+ (CGFloat)heightForCount:(NSInteger)count width:(CGFloat)width {
    if (count == 0) { return 0; }
    CGFloat tile = [self tileForWidth:width];
    NSInteger rows = (count + 2) / 3;
    return rows * tile + (rows - 1) * 2;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        UICollectionViewFlowLayout *l = [UICollectionViewFlowLayout new];
        l.minimumInteritemSpacing = 2; l.minimumLineSpacing = 2;
        _cv = [[UICollectionView alloc] initWithFrame:self.contentView.bounds collectionViewLayout:l];
        _cv.backgroundColor = UIColor.clearColor; _cv.scrollEnabled = NO;
        _cv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _cv.dataSource = self; _cv.delegate = self;
        [_cv registerClass:IMDetailMediaGridCell.class forCellWithReuseIdentifier:@"g"];
        [self.contentView addSubview:_cv];
    }
    return self;
}
- (void)setItems:(NSArray<IMMediaItem *> *)items { _items = items; [_cv reloadData]; }
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return _items.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    IMDetailMediaGridCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"g" forIndexPath:ip];
    [c configureWithItem:_items[ip.item]];
    return c;
}
- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat t = [IMDetailMediaContainerCell tileForWidth:cv.bounds.size.width];
    return CGSizeMake(t, t);
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    if (self.onPick) { self.onPick(_items[ip.item]); }
}
@end

#pragma mark - 详情页

/// 页面分区（动态组装到 _sections）。
typedef NS_ENUM(NSInteger, IMDetailSection) {
    IMDetailSectionPills = 0,  ///< 操作排（静音/搜索/更多）
    IMDetailSectionInfo,       ///< 单聊：备注名 / 用户名
    IMDetailSectionSettings,   ///< 置顶 / 免打扰（+群主管理员：群管理）
    IMDetailSectionTabs,       ///< 分类页签内容（header=分段控件）
};

static CGFloat const kPillsRowH = 78;

@interface IMChatDetailViewController () <UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate, IMLiquidNavigationBarDelegate>
// 身份
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, assign) BOOL isGroup;
// 单聊对端
@property (nonatomic, copy, nullable) NSString *peerID;
@property (nonatomic, copy, nullable) NSString *peerNickname;
@property (nonatomic, copy, nullable) NSString *peerAvatarURL;
@property (nonatomic, assign) BOOL peerBlocked;
// showsMessagePill 已提升为公开属性（见 .h）：单聊从群成员/通讯录等外部进入时显示「消息」入口。
// 群
@property (nonatomic, copy, nullable) NSString *groupName;
@property (nonatomic, strong, nullable) IMGroupInfo *group;
// 会话设置
@property (nonatomic, assign) int64_t pinnedAt;
@property (nonatomic, assign) BOOL muted;
// UI
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) IMDetailAvatarView *avatarView;
@property (nonatomic, strong) UILabel *nameOnImage;   ///< 图上名（photo 模式顶部）
@property (nonatomic, strong) UILabel *subOnImage;
@property (nonatomic, strong) UILabel *nameBelow;     ///< 圆头像下居中名
@property (nonatomic, strong) UILabel *subBelow;
@property (nonatomic, strong) IMLiquidNavigationBar *liquidNavigationBar;
@property (nonatomic, strong) UIView *pillsView;            ///< 搜索/更多独立按钮，放在 tableHeader 中避开 grouped 卡片背景
// 页签
@property (nonatomic, strong) UISegmentedControl *segmented;
@property (nonatomic, strong) UIView *stickyBar;               ///< 页签滚到顶时的悬浮吸顶条（透明，仅托分段控件）
@property (nonatomic, strong) UISegmentedControl *stickySeg;   ///< 吸顶条内镜像分段控件
@property (nonatomic, strong) NSArray<IMChatDetailTab *> *tabs;
@property (nonatomic, assign) NSInteger selectedTab;
@property (nonatomic, strong) NSArray<IMMediaItem *> *tabMedia;    ///< 当前媒体项（媒体页签）
@property (nonatomic, strong) NSArray<IMMessageModel *> *tabRows;  ///< 当前文件/语音/链接消息
// 布局
@property (nonatomic, assign) BOOL hasPhoto;
@property (nonatomic, assign) CGFloat topInset;
@property (nonatomic, assign) BOOL didHapticCircle;
@property (nonatomic, assign) BOOL didHapticAbsorb;
@end

@implementation IMChatDetailViewController

#pragma mark - 生命周期

- (instancetype)initSingleWithHost:(NSString *)host userID:(NSString *)userID peerID:(NSString *)peerID
                      peerNickname:(NSString *)peerNickname peerAvatarURL:(NSString *)peerAvatarURL {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy]; _userID = [userID copy]; _peerID = [peerID copy];
        // 本地备注名优先（仅自己可见，替代对端昵称显示）。
        NSString *remark = [NSUserDefaults.standardUserDefaults stringForKey:
                            [NSString stringWithFormat:@"im_remark_%@_%@", userID, peerID]];
        _peerNickname = remark.length ? [remark copy] : [peerNickname copy];
        _peerAvatarURL = [peerAvatarURL copy];
        _convID = IMConversationID(userID, peerID);
        _isGroup = NO;
        // URL 只决定圆形头像内容，不再触发全幅大图头部。
        _hasPhoto = NO;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (instancetype)initGroupWithHost:(NSString *)host userID:(NSString *)userID convID:(NSString *)convID
                       groupName:(NSString *)groupName groupAvatarURL:(NSString *)groupAvatarURL {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy]; _userID = [userID copy]; _convID = [convID copy];
        _groupName = [groupName copy]; _isGroup = YES;
        _peerAvatarURL = [groupAvatarURL copy];   // 复用字段承载群头像，供 headerAvatarURL 立即取用
        _hasPhoto = NO;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.selectedTab = 0;
    [self buildTableView];
    [self buildHeaderOverlay];
    [self rebuildTabs];

    // 初始数据：会话设置（置顶/免打扰）；群→群资料；单聊→拉黑态。
    [self loadConversationSettings];
    if (self.isGroup) {
        [self loadGroupInfo];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onGroupEvent:)
                                                   name:IMSocketDidReceiveGroupEventNotification object:nil];
    } else {
        [self loadPeerBlockState];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onConvUpdate:)
                                               name:IMSocketDidUpdateConversationNotification object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Telegram 风格详情页：保留 UINavigationController 堆栈和侧滑返回，但隐藏系统导航栏。
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // 主导航容器始终隐藏系统 UINavigationBar。返回时若临时恢复系统栏，会与统一 Glass 导航栏叠加产生双标题/双阴影。
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.topInset = self.view.safeAreaInsets.top;
    CGFloat W = self.view.bounds.size.width;
    // 头部占位高度（含顶部安全区）。
    CGFloat headerH = [self headerHeight];
    UIView *spacer = self.tableView.tableHeaderView;
    if (ABS(spacer.frame.size.height - headerH) > 0.5) {
        spacer.frame = CGRectMake(0, 0, W, headerH);
        self.tableView.tableHeaderView = spacer; // 触发重新测量
    }
    self.pillsView.frame = CGRectMake(0, self.topInset + 208, W, kPillsRowH);
    CGFloat barH = self.topInset + 44;
    self.stickyBar.frame = CGRectMake(0, barH, W, 44);
    [self layoutSegmented:self.stickySeg inWidth:W];
    [self syncScrollInset];
    [self applyHeaderMorph]; // 尺寸变化后重算
    [self updatePillsVisibility];
}

/// 所有详情页统一使用圆形头像头部；URL 仅替换头像内容。
- (CGFloat)absorbOffset { return 180; } // 头像完全被吸附所需上滑距离
- (CGFloat)headerHeight {
    return self.topInset + 200 + 8 + kPillsRowH;
}

/// 补足底部 inset，确保内容够短时也能上滑到「吸附」与「页签贴顶」位（否则松手回弹、动效走不完）。
- (void)syncScrollInset {
    CGFloat viewH = self.tableView.bounds.size.height;
    if (viewH <= 0) { return; }
    CGFloat wantMax = [self absorbOffset] + 24;
    NSInteger tabSec = [self indexOfSection:IMDetailSectionTabs];
    if (tabSec != NSNotFound) {
        CGRect hr = [self.tableView rectForHeaderInSection:tabSec];
        wantMax = MAX(wantMax, hr.origin.y - (self.topInset + 44) + 24); // 页签能滚到贴顶
    }
    CGFloat naturalMax = self.tableView.contentSize.height - viewH; // 不含 inset 的最大 offset
    CGFloat bottom = MAX(0, wantMax - naturalMax);
    if (ABS(self.tableView.contentInset.bottom - bottom) > 0.5) {
        self.tableView.contentInset = UIEdgeInsetsMake(0, 0, bottom, 0);
    }
}

#pragma mark - 构建 UI

- (void)buildTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.sectionHeaderTopPadding = 0;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"plain"];
    [self.tableView registerClass:IMDetailMemberCell.class forCellReuseIdentifier:@"member"];
    [self.tableView registerClass:IMDetailMediaContainerCell.class forCellReuseIdentifier:@"mediagrid"];
    UIView *spacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 300)];
    spacer.backgroundColor = UIColor.clearColor;
    self.pillsView = [self buildPillsView];
    [spacer addSubview:self.pillsView];
    self.tableView.tableHeaderView = spacer;
    [self.view addSubview:self.tableView];

    // 横滑切换页签（左/右）；成员行区域让位给行滑动删除（见 shouldReceiveTouch）。
    UISwipeGestureRecognizer *sl = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeToNextTab:)];
    sl.direction = UISwipeGestureRecognizerDirectionLeft; sl.delegate = self;
    UISwipeGestureRecognizer *sr = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeToPrevTab:)];
    sr.direction = UISwipeGestureRecognizerDirectionRight; sr.delegate = self;
    [self.tableView addGestureRecognizer:sl];
    [self.tableView addGestureRecognizer:sr];
}

- (UIView *)buildPillsView {
    UIView *host = [UIView new];
    host.backgroundColor = UIColor.clearColor;
    NSMutableArray *specs = [NSMutableArray array];
    if (self.isGroup) {
        [specs addObject:@{@"t": @"搜索", @"s": @"magnifyingglass", @"a": @"search"}];
    } else {
        if (self.showsMessagePill) {
            [specs addObject:@{@"t": @"消息", @"s": @"bubble.right.fill", @"a": @"message"}];
        }
        [specs addObject:@{@"t": @"呼叫", @"s": @"phone.fill", @"a": @"call"}];
        [specs addObject:@{@"t": @"视频", @"s": @"video.fill", @"a": @"video"}];
    }
    [specs addObject:@{@"t": @"更多", @"s": @"ellipsis", @"a": @"more"}];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 9;
    [host addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:host.topAnchor constant:6],
        [stack.bottomAnchor constraintEqualToAnchor:host.bottomAnchor constant:-6],
    ]];
    for (NSDictionary *spec in specs) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *cfg = IMGlassButtonConfiguration();
        cfg.image = [UIImage systemImageNamed:spec[@"s"]];
        cfg.title = spec[@"t"];
        cfg.imagePlacement = NSDirectionalRectEdgeTop;
        cfg.imagePadding = 4;
        cfg.baseForegroundColor = IMTheme.accent;
        cfg.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *old) {
            NSMutableDictionary *attrs = [old mutableCopy];
            attrs[NSFontAttributeName] = [UIFont systemFontOfSize:11];
            return attrs;
        };
        cfg.cornerStyle = UIButtonConfigurationCornerStyleLarge;
        button.configuration = cfg;
        button.accessibilityLabel = spec[@"a"];
        [button addTarget:self action:([spec[@"a"] isEqualToString:@"more"] ? @selector(moreTapped:) : @selector(pillTapped:))
         forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    }
    return host;
}

/// 给分段控件挂"点击即贴顶"的 tap（与其自身选择手势并存），支持单 tab / 重复点当前 tab 也贴顶。
- (void)addTabPinTapTo:(UISegmentedControl *)seg {
    UITapGestureRecognizer *tp = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tabBarTapped)];
    tp.cancelsTouchesInView = NO; tp.delaysTouchesBegan = NO; tp.delegate = self;
    [seg addGestureRecognizer:tp];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }

/// 成员行上的横滑留给「移除」滑动动作，不触发页签切换；其余区域（媒体/文件/链接/空白）横滑切页签。
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    if (![gr isKindOfClass:UISwipeGestureRecognizer.class]) { return YES; }
    if (self.tabs.count == 0) { return NO; }
    CGPoint p = [touch locationInView:self.tableView];
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
    if (ip && [self sectionKindAt:ip.section] == IMDetailSectionTabs) {
        IMChatDetailTab *t = self.tabs[self.selectedTab];
        if (t.kind == IMDetailTabKindMembers && ip.row > 0) { return NO; } // 成员行 → 行滑动删除
    }
    return YES;
}

- (void)buildHeaderOverlay {
    NSString *seed = self.isGroup ? self.convID : (self.peerID ?: @"");
    NSString *name = self.displayTitle;
    NSString *url = [self headerAvatarURL];

    self.avatarView = [[IMDetailAvatarView alloc] initWithFrame:CGRectZero];
    [self.avatarView setAvatarURL:url seed:seed name:name];
    self.avatarView.userInteractionEnabled = YES;
    [self.avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped)]];
    [self.view addSubview:self.avatarView];

    self.nameOnImage = [self makeNameLabel:22 color:UIColor.whiteColor shadow:YES];
    self.nameOnImage.textAlignment = NSTextAlignmentLeft;
    self.subOnImage = [self makeNameLabel:13 color:[UIColor.whiteColor colorWithAlphaComponent:0.85] shadow:YES];
    self.subOnImage.textAlignment = NSTextAlignmentLeft;
    self.nameBelow = [self makeNameLabel:20 color:IMTheme.textPrimary shadow:NO];
    self.subBelow = [self makeNameLabel:13 color:IMTheme.textSecondary shadow:NO];
    for (UILabel *l in @[self.nameOnImage, self.subOnImage, self.nameBelow, self.subBelow]) { [self.view addSubview:l]; }
    self.nameOnImage.text = name; self.nameBelow.text = name;
    self.subOnImage.text = self.displaySubtitle; self.subBelow.text = self.displaySubtitle;

    self.liquidNavigationBar = [[IMLiquidNavigationBar alloc] initWithTitle:name
                                                                     subtitle:self.displaySubtitle
                                                                  actionTitle:@"编辑"];
    self.liquidNavigationBar.delegate = self;
    self.liquidNavigationBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.liquidNavigationBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.liquidNavigationBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.liquidNavigationBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.liquidNavigationBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.liquidNavigationBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:56],
    ]];

    // 吸顶条：页签滚到折叠顶栏下方时出现，只放镜像分段控件——**无整行背景色**（分段控件自带药丸底即可）。
    self.stickyBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.stickyBar.backgroundColor = UIColor.clearColor;
    self.stickyBar.hidden = YES;
    [self.view addSubview:self.stickyBar];
    self.stickySeg = [[UISegmentedControl alloc] initWithItems:@[]];
    self.stickySeg.apportionsSegmentWidthsByContent = YES; // 段宽按内容固定，贴顶前后一致
    [self.stickySeg addTarget:self action:@selector(stickySegChanged:) forControlEvents:UIControlEventValueChanged];
    [self addTabPinTapTo:self.stickySeg];
    [self.stickyBar addSubview:self.stickySeg];

}

- (UILabel *)makeNameLabel:(CGFloat)size color:(UIColor *)color shadow:(BOOL)shadow {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:size weight:(size >= 20 ? UIFontWeightSemibold : UIFontWeightRegular)];
    l.textColor = color; l.textAlignment = NSTextAlignmentCenter;
    if (shadow) { l.layer.shadowColor = UIColor.blackColor.CGColor; l.layer.shadowOpacity = 0.35;
                  l.layer.shadowRadius = 6; l.layer.shadowOffset = CGSizeMake(0, 1); }
    return l;
}

- (NSString *)headerAvatarURL {
    // 群：优先已加载的群资料头像，否则用聊天页透传的（_peerAvatarURL 承载）；单聊：对方头像。
    NSString *raw = self.isGroup ? (self.group.avatarURL.length ? self.group.avatarURL : self.peerAvatarURL)
                                 : self.peerAvatarURL;
    return raw.length ? IMMediaFullURL(raw, self.host) : @"";
}
- (NSString *)displayTitle {
    if (self.isGroup) { return self.group.name.length ? self.group.name : (self.groupName.length ? self.groupName : @"群聊"); }
    return self.peerNickname.length ? self.peerNickname : (self.peerID ?: @"");
}
- (NSString *)displaySubtitle {
    if (self.isGroup) {
        NSUInteger n = self.group.members.count;
        return n > 0 ? [NSString stringWithFormat:@"%lu 位成员", (unsigned long)n] : @"群聊";
    }
    return self.peerID ?: @"";
}

#pragma mark - 头部形变（滚动驱动）

static CGFloat IMClamp(CGFloat x, CGFloat a, CGFloat b) { return MIN(MAX(x, a), b); }
static CGFloat IMSmooth(CGFloat x) { x = IMClamp(x, 0, 1); return x * x * (3 - 2 * x); }
static CGFloat IMLerp(CGFloat a, CGFloat b, CGFloat t) { return a + (b - a) * t; }

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self applyHeaderMorph];
    [self updatePillsVisibility];
    [self updateStickyTabs];
}

- (void)applyHeaderMorph {
    CGFloat W = self.view.bounds.size.width;
    if (W <= 0) { return; }
    CGFloat off = MAX(0, self.tableView.contentOffset.y); // 下拉橡皮筋不参与形变
    CGFloat top = self.topInset;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    // Telegram PeerInfoHeaderNode 以 contentOffset / 120 驱动灵动岛头像遮罩。
    CGFloat q = IMClamp(off / 120.0, 0, 1);
    CGFloat swallow = 0;
    BOOL attachedToIsland = NO;
    CGFloat restD = 92, restCY = top + 58;
    CGFloat islandBottom = MAX(36, top - 9);
    CGFloat contactEnd = 0.38;
    CGFloat w, h, cy;
    if (q < contactEnd) {
        CGFloat contact = IMSmooth(q / contactEnd);
        w = h = IMLerp(restD, 64, contact);
        cy = IMLerp(restCY, islandBottom + h * 0.5 - 2, contact);
    } else {
        swallow = IMSmooth((q - contactEnd) / (1 - contactEnd));
        w = IMLerp(64, 18, swallow);
        h = IMLerp(64, 6, swallow);
        cy = islandBottom - 5 + h * 0.5;
        attachedToIsland = YES;
    }

    // 接触前维持圆形上移；接触后顶部固定，水滴主体向上收缩。
    CGFloat neckPulse = (attachedToIsland && !reduceMotion) ? sin(M_PI * swallow) : 0;
    CGFloat drawW = w * (1 - 0.08 * neckPulse);
    CGFloat drawH = h * (1 + 0.08 * neckPulse);
    self.avatarView.frame = CGRectMake(W / 2 - drawW / 2, cy - drawH / 2, drawW, drawH);
    [self.avatarView applyAbsorptionMaskProgress:(attachedToIsland ? swallow : 0)];
    self.avatarView.layer.cornerRadius = attachedToIsland ? 0 : MIN(drawW, drawH) / 2;
    self.avatarView.alpha = swallow > 0.88 ? IMClamp(1 - (swallow - 0.88) / 0.12, 0, 1) : 1;

    // 统一圆头像下方标题，URL 头像不会切换到另一套大图标题布局。
    self.nameOnImage.alpha = 0;
    self.subOnImage.alpha = 0;
    CGFloat belowIn = IMClamp(1 - q * 2.4, 0, 1);
    CGFloat belowY = cy + drawH / 2 + 8;
    self.nameBelow.frame = CGRectMake(0, belowY, W, 26);
    self.subBelow.frame = CGRectMake(0, belowY + 26, W, 18);

    self.nameBelow.alpha = belowIn;
    self.subBelow.alpha = belowIn;

    // 大图态使用白色导航按钮；头像收成圆形后回到当前深浅模式的 label 色。
    self.liquidNavigationBar.immersiveAppearanceProgress = 0;
    self.liquidNavigationBar.backgroundEffectProgress = IMSmooth((q - 0.28) / 0.72);

    // 初始进入时只保留独立返回按钮；标题胶囊在头像水滴
    // 吸附接近完成时才渐显，恢复详情页原有的滚动形变节奏。
    self.liquidNavigationBar.compactContentProgress = IMSmooth((q - 0.72) / 0.24);

    [self fireHapticsForPhase:q hasPhoto:NO phaseP:1];
}

/// 操作排接近自定义导航栏时平滑淡出，避免搜索/更多按钮穿过返回与编辑按钮。
- (void)updatePillsVisibility {
    if (!self.pillsView.superview) { return; }
    CGRect frameInView = [self.pillsView.superview convertRect:self.pillsView.frame toView:self.view];
    CGFloat topInView = CGRectGetMinY(frameInView);
    CGFloat navigationBottom = self.topInset + 56;
    CGFloat navigationAlpha = IMClamp((topInView - navigationBottom) / 36, 0, 1);
    CGFloat labelAlpha = 1;
    if (self.subBelow.alpha > 0.05) {
        // 圆头像下方标题仍可见时，优先淡出操作排，避免按钮覆盖“3 位成员”等副标题。
        CGFloat clearance = topInView - CGRectGetMaxY(self.subBelow.frame);
        labelAlpha = IMClamp((clearance - 6) / 24, 0, 1);
    }
    CGFloat alpha = MIN(navigationAlpha, labelAlpha);
    self.pillsView.alpha = alpha;
    self.pillsView.userInteractionEnabled = alpha > 0.2;
}

/// 锚点触感：正圆成形（photo p≈1、未进吸附）与吸附完成（q≈1）各一次；反向复位后可再触发。
- (void)fireHapticsForPhase:(CGFloat)q hasPhoto:(BOOL)hasPhoto phaseP:(CGFloat)p {
    if (q >= 0.98 && !self.didHapticAbsorb) {
        self.didHapticAbsorb = YES;
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft] impactOccurred];
    }
    if (q < 0.5) { self.didHapticAbsorb = NO; }
    if (hasPhoto && q <= 0 && p >= 0.98 && !self.didHapticCircle) {
        self.didHapticCircle = YES;
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft] impactOccurred];
    }
    if (p < 0.5) { self.didHapticCircle = NO; }
}

#pragma mark - 数据加载

- (void)loadConversationSettings {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService conversationsWithToken:token completion:^(NSArray<IMConversation *> *convs, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error) { return; }
        for (IMConversation *c in convs) {
            if ([c.convID isEqualToString:self.convID]) {
                self.pinnedAt = c.pinnedAt; self.muted = c.muted;
                [self reloadSettingsAndPills];
                break;
            }
        }
    }];
}

- (void)loadGroupInfo {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService groupInfoWithToken:token convID:self.convID completion:^(IMGroupInfo *group, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || !group) { return; }
        self.group = group;
        self.groupName = group.name;
        BOOL manage = group.myRole == IMGroupRoleOwner || group.myRole == IMGroupRoleAdmin;
        [self.avatarView setAvatarURL:[self headerAvatarURL] seed:self.convID name:group.name];
        // 头像编辑统一由右上角“编辑”进入。
        self.liquidNavigationBar.actionTitle = manage ? @"编辑" : nil;
        [self refreshHeaderTexts];
        [self rebuildTabs];
        [self.tableView reloadData];
        [self.view setNeedsLayout];
    }];
}

- (void)avatarTapped {
    NSString *url = [self headerAvatarURL];
    NSURL *URL = [NSURL URLWithString:url];
    NSString *scheme = URL.scheme.lowercaseString;
    if (url.length == 0 || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        return;
    }
    IMMediaViewerViewController *viewer =
        [IMMediaViewerViewController viewerWithURL:url isVideo:NO
                                   preloadedImage:self.avatarView.photo.image
                                    onOpenGallery:nil];
    viewer.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)loadPeerBlockState {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService friendsWithToken:token status:nil completion:^(NSArray<IMUserCard *> *friends, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error) { return; }
        for (IMUserCard *c in friends) {
            if ([c.userID isEqualToString:self.peerID]) { self.peerBlocked = c.blocked; break; }
        }
        [self.tableView reloadData]; // 刷新「更多」菜单的 拉黑/取消拉黑 文案
    }];
}

- (void)refreshHeaderTexts {
    NSString *name = self.displayTitle, *sub = self.displaySubtitle;
    self.nameOnImage.text = name; self.nameBelow.text = name;
    self.subOnImage.text = sub; self.subBelow.text = sub;
    self.liquidNavigationBar.titleText = name;
    self.liquidNavigationBar.subtitleText = sub;
}

- (void)reloadSettingsAndPills {
    [self.tableView reloadData];
}

#pragma mark - 事件

- (void)onGroupEvent:(NSNotification *)note {
    if (![note.userInfo[kIMConvIDKey] isEqualToString:self.convID]) { return; }
    NSString *event = note.userInfo[kIMGroupEventKey];
    NSString *target = note.userInfo[kIMGroupTargetKey];
    if (([event isEqualToString:@"remove"] && [target isEqualToString:self.userID]) ||
        [event isEqualToString:@"dissolve"]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self loadGroupInfo];
}

- (void)onConvUpdate:(NSNotification *)note {
    if (![note.userInfo[kIMConvIDKey] isEqualToString:self.convID]) { return; }
    [self loadConversationSettings];
}

#pragma mark - 页签

- (void)rebuildTabs {
    NSArray<IMMessageModel *> *msgs = [IMDatabase.sharedDatabase messagesForConv:self.convID];
    self.tabs = [IMChatDetailTabs tabsForMessages:msgs isGroup:self.isGroup];
    if (self.selectedTab >= (NSInteger)self.tabs.count) { self.selectedTab = 0; }
    // 分段控件
    if (!self.segmented) {
        self.segmented = [[UISegmentedControl alloc] initWithItems:@[]];
        self.segmented.apportionsSegmentWidthsByContent = YES; // 段宽按内容固定（单/多 tab 一致）
        [self.segmented addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        [self addTabPinTapTo:self.segmented]; // 单 tab / 重复点当前 tab 也能贴顶
    }
    [self.segmented removeAllSegments];
    [self.stickySeg removeAllSegments];
    [self.tabs enumerateObjectsUsingBlock:^(IMChatDetailTab *t, NSUInteger i, BOOL *stop) {
        [self.segmented insertSegmentWithTitle:t.title atIndex:i animated:NO];
        [self.stickySeg insertSegmentWithTitle:t.title atIndex:i animated:NO];
    }];
    if (self.tabs.count > 0) {
        self.segmented.selectedSegmentIndex = self.selectedTab;
        self.stickySeg.selectedSegmentIndex = self.selectedTab;
    }
    [self recomputeTabContent];
}

- (void)segmentChanged:(UISegmentedControl *)seg { [self switchToTab:seg.selectedSegmentIndex scrollToPin:YES]; }
- (void)stickySegChanged:(UISegmentedControl *)seg { [self switchToTab:seg.selectedSegmentIndex scrollToPin:YES]; }

/// 相邻页签横滑切换（左滑=下一签、右滑=上一签），带水平滑入动画（Fix-B/横滑）。
- (void)swipeToNextTab:(UISwipeGestureRecognizer *)g {
    if (self.selectedTab + 1 < (NSInteger)self.tabs.count) { [self switchToTab:self.selectedTab + 1 scrollToPin:NO]; }
}
- (void)swipeToPrevTab:(UISwipeGestureRecognizer *)g {
    if (self.selectedTab - 1 >= 0) { [self switchToTab:self.selectedTab - 1 scrollToPin:NO]; }
}

/// 分段控件被点击（含单 tab / 重复点当前 tab）→ 仅贴顶（切换由 valueChanged 走 switchToTab）。
- (void)tabBarTapped { [self scrollTabsToPinAnimated:YES]; }

/// 页签贴顶的目标 offset（页签分区顶对齐折叠顶栏下沿）。页签分区之上的内容固定，故此值恒定。
- (CGFloat)pinOffset {
    NSInteger sec = [self indexOfSection:IMDetailSectionTabs];
    if (sec == NSNotFound) { return 0; }
    CGRect hr = [self.tableView rectForHeaderInSection:sec];
    return MAX(0, hr.origin.y - (self.topInset + 44));
}
- (BOOL)tabsArePinned { return self.tableView.contentOffset.y >= [self pinOffset] - 1; }

/// 切换页签：**内容瞬时替换、零动画**。已贴顶→保持贴顶（**绝不回露头部再滑回**，这是之前"先滑到顶再滑回"的根因）；
/// 未贴顶且需要贴顶→平滑滚过去。
- (void)switchToTab:(NSInteger)index scrollToPin:(BOOL)scrollToPin {
    if (index < 0 || index >= (NSInteger)self.tabs.count) { return; }
    if (index == self.selectedTab) { if (scrollToPin && ![self tabsArePinned]) { [self scrollTabsToPinAnimated:YES]; } return; }
    BOOL wasPinned = [self tabsArePinned];
    self.selectedTab = index;
    self.segmented.selectedSegmentIndex = index;
    self.stickySeg.selectedSegmentIndex = index;
    [self recomputeTabContent];
    if ([self indexOfSection:IMDetailSectionTabs] == NSNotFound) { return; }
    [UIView performWithoutAnimation:^{
        [self.tableView reloadData];       // 整表零动画重建：内容瞬时替换，无逐行高度动画
        [self.tableView layoutIfNeeded];
        [self syncScrollInset];            // 先撑够底部 inset，避免下一步 setOffset 被夹到顶
        if (wasPinned) {                   // 已贴顶：直接钉在贴顶位（无任何滚动动画，不露头部）
            self.tableView.contentOffset = CGPointMake(0, [self pinOffset]);
        }
    }];
    if (!wasPinned && scrollToPin) {       // 之前在头部区、点了 tab：平滑滚到贴顶
        __weak typeof(self) ws = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [ws scrollTabsToPinAnimated:YES]; });
    }
}

/// 把页签分区滚到折叠顶栏正下方（贴顶）。
- (void)scrollTabsToPinAnimated:(BOOL)animated {
    if ([self indexOfSection:IMDetailSectionTabs] == NSNotFound) { return; }
    CGFloat maxOff = self.tableView.contentSize.height + self.tableView.contentInset.bottom - self.tableView.bounds.size.height;
    CGFloat target = IMClamp([self pinOffset], 0, MAX(0, maxOff));
    [self.tableView setContentOffset:CGPointMake(0, target) animated:animated];
}

/// 页签分区滚到折叠顶栏下方即显示吸顶条（其下列表继续滚动，无缝衔接）。
- (void)updateStickyTabs {
    NSInteger sec = [self indexOfSection:IMDetailSectionTabs];
    if (sec == NSNotFound || self.tabs.count == 0) { self.stickyBar.hidden = YES; self.segmented.hidden = NO; return; }
    CGRect hr = [self.tableView rectForHeaderInSection:sec];
    CGFloat headerTopInView = hr.origin.y - self.tableView.contentOffset.y;
    BOOL pinned = headerTopInView <= self.topInset + 44 + 0.5;
    self.stickyBar.hidden = !pinned;
    // 贴顶后隐藏表内真分段——吸顶条透明，真 header 上移时会从其后透出，与镜像分段并存（两个 tab 栏）。
    self.segmented.hidden = pinned;
    if (pinned && self.stickySeg.selectedSegmentIndex != self.selectedTab) {
        self.stickySeg.selectedSegmentIndex = self.selectedTab;
    }
}

/// 依当前选中页签，预备内容数组（媒体项 / 文件·语音·链接消息）。
- (void)recomputeTabContent {
    self.tabMedia = @[]; self.tabRows = @[];
    if (self.tabs.count == 0) { return; }
    IMChatDetailTab *t = self.tabs[self.selectedTab];
    if (t.kind == IMDetailTabKindMembers) { return; }
    NSArray<IMMessageModel *> *msgs = [IMDatabase.sharedDatabase messagesForConv:self.convID];
    if (t.kind == IMDetailTabKindMedia) {
        NSMutableArray<IMMediaItem *> *items = [NSMutableArray array];
        for (IMMessageModel *m in msgs) {
            if (![IMChatDetailTabs message:m matchesKind:IMDetailTabKindMedia]) { continue; }
            BOOL isVideo = [m.contentType isEqualToString:@"video"];
            [items addObject:[IMMediaItem itemWithURL:IMMediaFullURL(m.content, self.host) isVideo:isVideo timestamp:m.timestamp]];
        }
        // 新→旧
        self.tabMedia = [items sortedArrayUsingComparator:^NSComparisonResult(IMMediaItem *a, IMMediaItem *b) {
            return a.timestamp > b.timestamp ? NSOrderedAscending : (a.timestamp < b.timestamp ? NSOrderedDescending : NSOrderedSame);
        }];
        return;
    }
    // 文件/语音/链接：过滤 + 新→旧
    NSMutableArray<IMMessageModel *> *rows = [NSMutableArray array];
    for (IMMessageModel *m in msgs) { if ([IMChatDetailTabs message:m matchesKind:t.kind]) { [rows addObject:m]; } }
    self.tabRows = [rows sortedArrayUsingComparator:^NSComparisonResult(IMMessageModel *a, IMMessageModel *b) {
        return a.timestamp > b.timestamp ? NSOrderedAscending : (a.timestamp < b.timestamp ? NSOrderedDescending : NSOrderedSame);
    }];
}

#pragma mark - Section 组装

/// 当前页面的 section 顺序。
- (NSArray<NSNumber *> *)sectionLayout {
    NSMutableArray<NSNumber *> *s = [NSMutableArray array];
    if (!self.isGroup) { [s addObject:@(IMDetailSectionInfo)]; } // 单聊：备注名/用户名
    [s addObject:@(IMDetailSectionSettings)];
    if (self.tabs.count > 0) { [s addObject:@(IMDetailSectionTabs)]; }
    return s;
}
- (IMDetailSection)sectionKindAt:(NSInteger)index { return (IMDetailSection)[[self sectionLayout][index] integerValue]; }
- (NSInteger)indexOfSection:(IMDetailSection)kind {
    NSArray *layout = [self sectionLayout];
    for (NSInteger i = 0; i < (NSInteger)layout.count; i++) { if ([layout[i] integerValue] == kind) { return i; } }
    return NSNotFound;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return [self sectionLayout].count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self sectionKindAt:section]) {
        case IMDetailSectionPills:    return 1;
        case IMDetailSectionInfo:     return 2; // 备注名 + 用户名
        case IMDetailSectionSettings: {
            NSInteger n = 2; // 置顶 + 免打扰
            if (self.isGroup && [self canManageGroup]) { n += 1; } // 群管理
            return n;
        }
        case IMDetailSectionTabs:     return [self tabRowCount];
    }
    return 0;
}

- (NSInteger)tabRowCount {
    if (self.tabs.count == 0) { return 0; }
    IMChatDetailTab *t = self.tabs[self.selectedTab];
    switch (t.kind) {
        case IMDetailTabKindMembers: return 1 + (NSInteger)self.group.members.count; // 添加成员 + 成员
        case IMDetailTabKindMedia:   return self.tabMedia.count > 0 ? 1 : 1;          // 1 个宫格 cell（空态也占位）
        default:                     return MAX(1, (NSInteger)self.tabRows.count);    // 至少 1（空态提示）
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if ([self sectionKindAt:section] != IMDetailSectionTabs) { return nil; }
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 44)];
    [self layoutSegmented:self.segmented inWidth:tableView.bounds.size.width];
    [wrap addSubview:self.segmented];
    return wrap;
}

/// 分段控件按内容宽居中（贴顶条与表内一致，单/多 tab 段宽固定）。
- (void)layoutSegmented:(UISegmentedControl *)seg inWidth:(CGFloat)width {
    CGFloat w = [seg sizeThatFits:CGSizeMake(width - 32, 32)].width;
    w = IMClamp(w, 120, width - 32);        // 下限保证单 tab 也有合理固定宽
    seg.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    seg.frame = CGRectMake((width - w) / 2, 6, w, 32);
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    IMDetailSection kind = [self sectionKindAt:section];
    if (kind == IMDetailSectionTabs) { return 44; }
    if (kind == IMDetailSectionPills) { return 8; }
    return 12;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMDetailSection kind = [self sectionKindAt:indexPath.section];
    if (kind == IMDetailSectionPills) { return kPillsRowH; }
    if (kind == IMDetailSectionTabs && self.tabs.count > 0) {
        IMChatDetailTab *t = self.tabs[self.selectedTab];
        if (t.kind == IMDetailTabKindMembers) { return 60; }
        if (t.kind == IMDetailTabKindMedia) {
            CGFloat w = tableView.bounds.size.width - 32; // InsetGrouped 左右各 ~16
            CGFloat h = [IMDetailMediaContainerCell heightForCount:self.tabMedia.count width:w];
            return h > 0 ? h : 60;
        }
        return 60;
    }
    return 52;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ([self sectionKindAt:indexPath.section]) {
        case IMDetailSectionPills:    return [self pillsCell:tableView];
        case IMDetailSectionInfo:     return [self infoCell:tableView row:indexPath.row];
        case IMDetailSectionSettings: return [self settingsCell:tableView row:indexPath.row];
        case IMDetailSectionTabs:     return [self tabCell:tableView row:indexPath.row];
    }
    return [tableView dequeueReusableCellWithIdentifier:@"plain" forIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
 forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self sectionKindAt:indexPath.section] != IMDetailSectionPills) { return; }
    // insetGrouped 会在展示阶段重新生成分组卡片背景，因此这里再次明确清空，避免按钮下方残留整行圆角底框。
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.backgroundView.backgroundColor = UIColor.clearColor;
    cell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
    [self updatePillsVisibility];
}

#pragma mark - Cells

- (UITableViewCell *)pillsCell:(UITableView *)tv {
    // 不复用普通分组 cell，避免 UIKit 将其他 section 的 grouped 背景配置带到操作排。
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    UIView *clearBackground = [UIView new];
    clearBackground.backgroundColor = UIColor.clearColor;
    cell.backgroundView = clearBackground;
    cell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
    // 操作排按入口定制（去「静音」——下面有免打扰开关，重复）：
    NSMutableArray *specs = [NSMutableArray array];
    if (self.isGroup) {
        [specs addObject:@{@"t": @"搜索", @"s": @"magnifyingglass", @"a": @"search"}];
    } else {
        if (self.showsMessagePill) { // 从群成员/通讯录进 → 多显「消息」（发起单聊）
            [specs addObject:@{@"t": @"消息", @"s": @"bubble.right.fill", @"a": @"message"}];
        }
        [specs addObject:@{@"t": @"呼叫", @"s": @"phone.fill", @"a": @"call"}];       // 语音通话
        [specs addObject:@{@"t": @"视频", @"s": @"video.fill", @"a": @"video"}];      // 视频通话
    }
    [specs addObject:@{@"t": @"更多", @"s": @"ellipsis", @"a": @"more"}];
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectInset(cell.contentView.bounds, 0, 6)];
    stack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    stack.axis = UILayoutConstraintAxisHorizontal; stack.distribution = UIStackViewDistributionFillEqually; stack.spacing = 9;
    for (NSDictionary *spec in specs) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *cfg = IMGlassButtonConfiguration();
        cfg.image = [UIImage systemImageNamed:spec[@"s"]];
        cfg.title = spec[@"t"];
        cfg.imagePlacement = NSDirectionalRectEdgeTop; cfg.imagePadding = 4;
        cfg.baseForegroundColor = IMTheme.accent;
        cfg.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *old) {
            NSMutableDictionary *d = [old mutableCopy]; d[NSFontAttributeName] = [UIFont systemFontOfSize:11]; return d;
        };
        cfg.cornerStyle = UIButtonConfigurationCornerStyleLarge;
        b.configuration = cfg;
        b.accessibilityLabel = spec[@"a"];
        // 「更多」交给 IMPopoverCard 的 UIKit action sheet/popover；iOS 26 自动使用 Liquid Glass。
        [b addTarget:self action:([spec[@"a"] isEqualToString:@"more"] ? @selector(moreTapped:) : @selector(pillTapped:))
      forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:b];
    }
    [cell.contentView addSubview:stack];
    return cell;
}

- (UITableViewCell *)infoCell:(UITableView *)tv row:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.detailTextLabel.textColor = IMTheme.textSecondary;
    if (row == 0) {
        cell.textLabel.text = self.displayTitle;
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = @"备注名 · 点击修改";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = self.peerID;
        cell.textLabel.textColor = IMTheme.accent;
        cell.detailTextLabel.text = @"用户名";
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (UITableViewCell *)settingsCell:(UITableView *)tv row:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.textColor = IMTheme.textPrimary;
    if (row == 0) {
        cell.textLabel.text = @"置顶聊天";
        UISwitch *sw = [UISwitch new]; sw.on = self.pinnedAt > 0; sw.tag = 1;
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (row == 1) {
        cell.textLabel.text = @"消息免打扰";
        UISwitch *sw = [UISwitch new]; sw.on = self.muted; sw.tag = 2;
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else {
        cell.textLabel.text = @"群管理";
        cell.detailTextLabel.text = @"仅群主/管理员";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (UITableViewCell *)tabCell:(UITableView *)tv row:(NSInteger)row {
    IMChatDetailTab *t = self.tabs[self.selectedTab];
    if (t.kind == IMDetailTabKindMembers) {
        if (row == 0) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.textLabel.text = @"添加成员"; cell.textLabel.textColor = IMTheme.accent;
            cell.imageView.image = [UIImage systemImageNamed:@"person.badge.plus"]; cell.imageView.tintColor = IMTheme.accent;
            return cell;
        }
        IMDetailMemberCell *cell = [tv dequeueReusableCellWithIdentifier:@"member"];
        IMGroupMember *m = self.group.members[row - 1];
        [cell configureWithMember:m isMe:[m.userID isEqualToString:self.userID]];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    if (t.kind == IMDetailTabKindMedia) {
        if (self.tabMedia.count == 0) { return [self emptyCell:tv text:@"暂无媒体"]; }
        IMDetailMediaContainerCell *cell = [tv dequeueReusableCellWithIdentifier:@"mediagrid"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        __weak typeof(self) ws = self;
        cell.onPick = ^(IMMediaItem *item) { [ws openMediaItem:item]; };
        [cell setItems:self.tabMedia];
        return cell;
    }
    // 文件/语音/链接
    if (self.tabRows.count == 0) {
        NSString *empty = t.kind == IMDetailTabKindFiles ? @"暂无文件" : (t.kind == IMDetailTabKindVoice ? @"暂无语音" : @"暂无链接");
        return [self emptyCell:tv text:empty];
    }
    IMMessageModel *m = self.tabRows[row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.detailTextLabel.textColor = IMTheme.textSecondary;
    if (t.kind == IMDetailTabKindFiles) {
        cell.textLabel.text = IMMediaFileName(m.content);
        cell.imageView.image = [UIImage systemImageNamed:IMFileGlyphForName(m.content)] ?: [UIImage systemImageNamed:@"doc.fill"];
        cell.imageView.tintColor = IMTheme.accent;
        cell.detailTextLabel.text = [IMTheme timeStringFromMillis:m.timestamp];
    } else if (t.kind == IMDetailTabKindVoice) {
        cell.textLabel.text = @"语音消息";
        cell.imageView.image = [UIImage systemImageNamed:@"waveform"]; cell.imageView.tintColor = IMTheme.accent;
        cell.detailTextLabel.text = [IMTheme timeStringFromMillis:m.timestamp];
    } else {
        cell.textLabel.text = m.content;
        cell.textLabel.textColor = IMTheme.accent; cell.textLabel.numberOfLines = 1;
        cell.imageView.image = [UIImage systemImageNamed:@"link"]; cell.imageView.tintColor = IMTheme.accent;
        cell.detailTextLabel.text = [IMTheme timeStringFromMillis:m.timestamp];
    }
    return cell;
}

- (UITableViewCell *)emptyCell:(UITableView *)tv text:(NSString *)text {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = text; cell.textLabel.textColor = IMTheme.textSecondary;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

#pragma mark - UITableViewDelegate（点选）

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IMDetailSection kind = [self sectionKindAt:indexPath.section];
    if (kind == IMDetailSectionInfo && indexPath.row == 0) { [self editRemark]; return; }
    if (kind == IMDetailSectionSettings) {
        if (indexPath.row == 2) { [self openGroupManage]; }
        return;
    }
    if (kind == IMDetailSectionTabs && self.tabs.count > 0) {
        IMChatDetailTab *t = self.tabs[self.selectedTab];
        if (t.kind == IMDetailTabKindMembers) {
            if (indexPath.row == 0) { [self inviteMembers]; }
            else { [self openPeerDetail:self.group.members[indexPath.row - 1]]; } // tap→对方资料页
        } else if (t.kind == IMDetailTabKindFiles || t.kind == IMDetailTabKindLinks) {
            if (self.tabRows.count > 0) { [self openLink:IMMediaFullURL(self.tabRows[indexPath.row].content, self.host)]; }
        }
    }
}

/// 成员行取对应成员（row>0；否则 nil）。
- (nullable IMGroupMember *)memberAtIndexPath:(NSIndexPath *)ip {
    if ([self sectionKindAt:ip.section] != IMDetailSectionTabs || self.tabs.count == 0) { return nil; }
    if (self.tabs[self.selectedTab].kind != IMDetailTabKindMembers || ip.row == 0) { return nil; }
    NSInteger i = ip.row - 1;
    return (i >= 0 && i < (NSInteger)self.group.members.count) ? self.group.members[i] : nil;
}

/// 我能否移除该成员（owner 可移任何非自己；admin 可移 member）。
- (BOOL)canRemoveMember:(IMGroupMember *)m {
    if (!m || [m.userID isEqualToString:self.userID]) { return NO; }
    IMGroupRole mine = self.group.myRole;
    return mine == IMGroupRoleOwner || (mine == IMGroupRoleAdmin && m.role == IMGroupRoleMember);
}

#pragma mark - 成员行：左滑移除

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMGroupMember *m = [self memberAtIndexPath:indexPath];
    if (![self canRemoveMember:m]) { return nil; }
    __weak typeof(self) ws = self;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"移除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [ws removeMember:m]; done(YES);
    }];
    remove.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[ remove ]];
}

#pragma mark - 成员行：长按上下文菜单（发送消息 / 管理 / 移除）

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    IMGroupMember *m = [self memberAtIndexPath:indexPath];
    if (!m || [m.userID isEqualToString:self.userID]) { return nil; }
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *sug) {
        NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
        [items addObject:[UIAction actionWithTitle:@"发送消息" image:[UIImage systemImageNamed:@"bubble.right"]
                                        identifier:nil handler:^(UIAction *a) { [ws openChatWithMember:m]; }]];
        if (ws.group.myRole == IMGroupRoleOwner && m.role == IMGroupRoleMember) {
            [items addObject:[UIAction actionWithTitle:@"设为管理员" image:[UIImage systemImageNamed:@"person.badge.shield.checkmark"]
                                            identifier:nil handler:^(UIAction *a) { [ws runGroupRole:ws.convID user:m.userID role:@"admin"]; }]];
        }
        if (ws.group.myRole == IMGroupRoleOwner && m.role == IMGroupRoleAdmin) {
            [items addObject:[UIAction actionWithTitle:@"撤销管理员" image:[UIImage systemImageNamed:@"person.badge.minus"]
                                            identifier:nil handler:^(UIAction *a) { [ws runGroupRole:ws.convID user:m.userID role:@"member"]; }]];
        }
        if (ws.group.myRole == IMGroupRoleOwner) {
            [items addObject:[UIAction actionWithTitle:@"转让群主" image:[UIImage systemImageNamed:@"crown"]
                                            identifier:nil handler:^(UIAction *a) { [ws confirmTransfer:m]; }]];
        }
        if ([ws canRemoveMember:m]) {
            UIAction *rm = [UIAction actionWithTitle:@"移除" image:[UIImage systemImageNamed:@"trash"]
                                          identifier:nil handler:^(UIAction *a) { [ws removeMember:m]; }];
            rm.attributes = UIMenuElementAttributesDestructive;
            [items addObject:rm];
        }
        return [UIMenu menuWithTitle:m.displayName children:items];
    }];
}

/// 打开成员的资料页（走单聊右上头像同一逻辑）。
- (void)openPeerDetail:(IMGroupMember *)m {
    if (!m || [m.userID isEqualToString:self.userID]) { return; }
    IMChatDetailViewController *vc = [[IMChatDetailViewController alloc] initSingleWithHost:self.host userID:self.userID
                                                                                    peerID:m.userID
                                                                              peerNickname:m.displayName
                                                                             peerAvatarURL:m.avatarURL];
    vc.showsMessagePill = YES; // 从群成员进 → 操作排显「消息」
    [self.navigationController pushViewController:vc animated:YES];
}

/// 与成员开始单聊（长按「发送消息」）。
- (void)openChatWithMember:(IMGroupMember *)m {
    if (!m || [m.userID isEqualToString:self.userID]) { return; }
    IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:self.host userID:self.userID
                                                                    peerID:m.userID readSeq:0 unread:0 peerReadSeq:0];
    chat.peerNickname = m.displayName;
    chat.peerAvatarURL = m.avatarURL;
    [self.navigationController pushViewController:chat animated:YES];
}

/// 移除成员（带二次确认）。
- (void)removeMember:(IMGroupMember *)m {
    if (![self canRemoveMember:m]) { return; }
    [self confirmDestructive:[NSString stringWithFormat:@"移出「%@」？", m.displayName]
                     message:@"该成员将被移出群聊。" action:@"移除" handler:^{
        NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService removeGroupMemberWithToken:token convID:self.convID userID:m.userID
                                                    completion:^(NSError *error) {
            if (error) { [ws im_showToast:error.localizedDescription]; return; }
            [ws loadGroupInfo];
        }];
    }];
}

#pragma mark - 动作：操作排 / 更多菜单

- (void)pillTapped:(UIButton *)b {
    NSString *a = b.accessibilityLabel;
    if ([a isEqualToString:@"search"]) { [self im_showToast:@"聊天内搜索即将上线"]; }
    else if ([a isEqualToString:@"call"]) { [self im_showToast:@"语音通话即将上线"]; }
    else if ([a isEqualToString:@"video"]) { [self im_showToast:@"视频通话即将上线"]; }
    else if ([a isEqualToString:@"message"]) { [self openChatWithPeerID:self.peerID nickname:self.peerNickname avatarURL:self.peerAvatarURL]; }
}

/// 与某人开始/回到单聊（操作排「消息」）。
- (void)openChatWithPeerID:(NSString *)peerID nickname:(NSString *)nickname avatarURL:(NSString *)avatarURL {
    if (peerID.length == 0 || [peerID isEqualToString:self.userID]) { return; }
    IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:self.host userID:self.userID
                                                                    peerID:peerID readSeq:0 unread:0 peerReadSeq:0];
    chat.peerNickname = nickname; chat.peerAvatarURL = avatarURL;
    [self.navigationController pushViewController:chat animated:YES];
}

/// 「更多」系统菜单：清空记录=普通色；退出/删除群/拉黑=红。
- (void)moreTapped:(UIButton *)anchor {
    NSMutableArray<IMPopoverCardItem *> *items = [NSMutableArray array];
    __weak typeof(self) ws = self;
    if (self.isGroup) {
        [items addObject:[IMPopoverCardItem itemWithTitle:@"清空聊天记录" symbol:@"trash" destructive:NO handler:^{ [ws confirmClearHistory]; }]];
        [items addObject:[IMPopoverCardItem itemWithTitle:@"退出群组" symbol:@"rectangle.portrait.and.arrow.right" destructive:YES handler:^{ [ws confirmLeaveGroup]; }]];
        if (self.group && self.group.myRole == IMGroupRoleOwner) {
            [items addObject:[IMPopoverCardItem itemWithTitle:@"删除群组" symbol:@"trash.fill" destructive:YES handler:^{ [ws confirmDissolve]; }]];
        }
    } else {
        [items addObject:[IMPopoverCardItem itemWithTitle:(self.peerBlocked ? @"取消拉黑" : @"拉黑") symbol:@"hand.raised"
                                             destructive:!self.peerBlocked handler:^{ [ws toggleBlock]; }]];
        [items addObject:[IMPopoverCardItem itemWithTitle:@"清空聊天记录" symbol:@"trash" destructive:NO handler:^{ [ws confirmClearHistory]; }]];
    }
    [IMPopoverCard presentFromAnchor:anchor inHostView:self.view items:items];
}

- (void)confirmDissolve {
    [self confirmDestructive:[NSString stringWithFormat:@"删除并解散「%@」？", self.displayTitle]
                     message:@"所有成员将被移出，聊天记录无法恢复，此操作不可撤销。" action:@"删除" handler:^{
        NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService dissolveGroupWithToken:token convID:self.convID completion:^(NSError *error) {
            if (error) { [ws im_showToast:error.localizedDescription]; return; }
            // 连退两级（详情 + 聊天页）回列表；dissolve 群事件也会触发各页自退（幂等）。
            NSArray *vcs = ws.navigationController.viewControllers;
            NSInteger idx = (NSInteger)vcs.count - 3;
            if (idx >= 0) { [ws.navigationController popToViewController:vcs[idx] animated:YES]; }
            else { [ws.navigationController popViewControllerAnimated:YES]; }
        }];
    }];
}

- (void)confirmClearHistory {
    NSString *msg = self.isGroup ? @"仅清空本机记录，不影响其他成员。" : @"将删除此会话在本机的全部消息，且无法恢复。";
    [self confirmDestructive:@"清空聊天记录？" message:msg action:@"清空" handler:^{
        [IMDatabase.sharedDatabase clearMessagesForConv:self.convID];
        [self rebuildTabs];
        [self.tableView reloadData];
        // 通知底层聊天页清空内存并刷新（否则返回聊天页仍显旧消息）。
        [NSNotificationCenter.defaultCenter postNotificationName:IMChatConversationClearedNotification
                                                          object:nil userInfo:@{kIMConvIDKey: self.convID}];
        [self im_showToast:@"聊天记录已清空"];
    }];
}

- (void)confirmLeaveGroup {
    [self confirmDestructive:[NSString stringWithFormat:@"退出「%@」？", self.displayTitle]
                     message:@"退出后将不再接收此群消息。" action:@"退出" handler:^{
        NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService leaveGroupWithToken:token convID:self.convID completion:^(NSError *error) {
            if (error) { [ws im_showToast:error.localizedDescription]; return; }
            // 连退两级（详情 + 聊天页）回列表。
            NSArray *vcs = ws.navigationController.viewControllers;
            NSInteger idx = (NSInteger)vcs.count - 3;
            if (idx >= 0) { [ws.navigationController popToViewController:vcs[idx] animated:YES]; }
            else { [ws.navigationController popViewControllerAnimated:YES]; }
        }];
    }];
}

/// 通用二次确认（红色破坏性）。
- (void)confirmDestructive:(NSString *)title message:(NSString *)message action:(NSString *)action handler:(void (^)(void))handler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:action style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        if (handler) { handler(); }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 动作：设置 / 编辑 / 拉黑

- (void)switchChanged:(UISwitch *)sw {
    if (sw.tag == 1) { self.pinnedAt = sw.on ? (int64_t)([NSDate date].timeIntervalSince1970 * 1000) : 0; }
    else if (sw.tag == 2) { self.muted = sw.on; }
    [self commitConversationSettings];
}
- (void)commitConversationSettings {
    NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService updateConversationSettingsWithToken:token convID:self.convID
        pinnedAt:self.pinnedAt muted:self.muted markedUnread:NO completion:^(NSError *error) {
        if (error) { [ws im_showToast:error.localizedDescription ?: @"设置失败"]; }
    }];
}

- (void)editRemark {
    // 单聊备注名：本地私有（NSUserDefaults，未签名装机 Keychain 不可用），仅自己可见，替代显示名。
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置备注名"
        message:@"备注名仅自己可见，将替代对方昵称显示。" preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = self.displayTitle;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; }];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        __strong typeof(ws) self = ws;
        if (!self || v.length == 0) { return; }
        [NSUserDefaults.standardUserDefaults setObject:v forKey:[self remarkKey]];
        self.peerNickname = v;
        [self.avatarView setAvatarURL:[self headerAvatarURL] seed:(self.peerID ?: @"") name:v];
        [self refreshHeaderTexts];
        [self.tableView reloadData];
        [self im_showToast:@"备注已更新"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (NSString *)remarkKey { return [NSString stringWithFormat:@"im_remark_%@_%@", self.userID, self.peerID]; }

- (void)toggleBlock {
    NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
    BOOL toBlock = !self.peerBlocked;
    void (^commit)(void) = ^{
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService friendActionWithToken:token action:(toBlock ? @"block" : @"unblock") peerID:self.peerID
                                                completion:^(NSError *error) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (error) { [self im_showToast:error.localizedDescription ?: @"操作失败"]; return; }
            self.peerBlocked = toBlock;
            [self im_showToast:toBlock ? @"已拉黑" : @"已取消拉黑"];
        }];
    };
    if (toBlock) {
        [self confirmDestructive:[NSString stringWithFormat:@"拉黑「%@」？", self.displayTitle]
                         message:@"拉黑后将不再收到对方消息。" action:@"拉黑" handler:commit];
    } else { commit(); }
}

#pragma mark - 动作：群成员管理（成员页签）

- (void)inviteMembers {
    NSMutableSet<NSString *> *inGroup = [NSMutableSet set];
    for (IMGroupMember *m in self.group.members) { [inGroup addObject:m.userID]; }
    __weak typeof(self) ws = self;
    IMGroupMemberPickerViewController *picker =
        [[IMGroupMemberPickerViewController alloc] initWithHost:self.host userID:self.userID
                                                    excludedIDs:inGroup confirmTitle:@"邀请"
                                                         onDone:^(NSArray<NSString *> *ids) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        [self.navigationController popToViewController:self animated:YES];
        NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
        [IMHTTPService.sharedService inviteToGroupWithToken:token convID:self.convID memberIDs:ids completion:^(NSError *error) {
            if (error) { [self im_showToast:error.localizedDescription]; return; }
            [self loadGroupInfo];
        }];
    }];
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)runGroupRole:(NSString *)convID user:(NSString *)user role:(NSString *)role {
    NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService setGroupRoleWithToken:token convID:convID userID:user role:role completion:^(NSError *error) {
        if (error) { [ws im_showToast:error.localizedDescription]; return; }
        [ws loadGroupInfo];
    }];
}

- (void)confirmTransfer:(IMGroupMember *)member {
    [self confirmDestructive:@"转让群主"
                     message:[NSString stringWithFormat:@"确定把群主转让给 %@？你将变为普通成员。", member.displayName]
                      action:@"转让" handler:^{
        NSString *token = IMHTTPService.sharedService.currentToken; if (token.length == 0) { return; }
        __weak typeof(self) ws = self;
        [IMHTTPService.sharedService transferGroupWithToken:token convID:self.convID userID:member.userID completion:^(NSError *error) {
            if (error) { [ws im_showToast:error.localizedDescription]; return; }
            [ws loadGroupInfo];
        }];
    }];
}

- (BOOL)canManageGroup {
    return self.group && (self.group.myRole == IMGroupRoleOwner || self.group.myRole == IMGroupRoleAdmin);
}

- (void)openGroupManage {
    if (![self canManageGroup]) { return; }
    __weak typeof(self) ws = self;
    IMGroupManageViewController *vc = [[IMGroupManageViewController alloc] initWithHost:self.host userID:self.userID
                                                                                convID:self.convID group:self.group
                                                                             onChanged:^{ [ws loadGroupInfo]; }];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 打开媒体 / 链接 / 返回

- (void)openMediaItem:(IMMediaItem *)item {
    IMMediaViewerViewController *viewer = [IMMediaViewerViewController viewerWithURL:item.url isVideo:item.isVideo
                                                                     preloadedImage:nil onOpenGallery:nil];
    [self presentViewController:viewer animated:YES completion:nil];
}
- (void)openLink:(NSString *)url {
    if (url.length == 0) { return; }
    NSURL *u = [NSURL URLWithString:url];
    if (u) { [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil]; }
}
- (void)headerActionTapped {
    if (self.isGroup) { [self openGroupManage]; }
    else { [self editRemark]; }
}
- (void)liquidNavigationBarDidTapBack:(IMLiquidNavigationBar *)bar {
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)liquidNavigationBarDidTapAction:(IMLiquidNavigationBar *)bar {
    [self headerActionTapped];
}
- (void)liquidNavigationBarDidTapLeft:(IMLiquidNavigationBar *)bar {
    [self liquidNavigationBarDidTapBack:bar];
}
- (void)goBack { [self.navigationController popViewControllerAnimated:YES]; }

@end
