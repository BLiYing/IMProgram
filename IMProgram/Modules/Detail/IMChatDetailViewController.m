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
#import "UILabel+IMAvatar.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import <objc/runtime.h>

#pragma mark - 形变头像视图（图片铺满 + 首字母回退，圆角随外部调节；供头部形变用）

/// 形变头像：容器负责圆角/裁剪（随滚动 morph）。**首字母底 + 图片都用 frame-based 子视图，layoutSubviews
/// 显式铺满**——用全局同款 `IMImageLoader` + `avatarColorForSeed`（视觉与列表/成员一致），但不嵌约束到 label
/// （之前把约束图钉在 0×0 起步的 frame-based label 上，约束解析不出尺寸→图停在 0×0，只剩浅色底=空白怪形）。
@interface IMDetailAvatarView : UIView
@property (nonatomic, strong) UILabel *letter;
@property (nonatomic, strong) UIImageView *photo;
- (void)setAvatarURL:(nullable NSString *)url seed:(NSString *)seed name:(nullable NSString *)name;
@end

@implementation IMDetailAvatarView {
    NSUInteger _token;
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
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _letter.frame = self.bounds;
    _photo.frame = self.bounds;                   // 显式铺满，随 morph 每帧更新
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

@interface IMChatDetailViewController () <UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate>
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
@property (nonatomic, strong) UIButton *cameraBadge;  ///< 群主/管理员设群头像入口
@property (nonatomic, strong) UIVisualEffectView *collapsedBar; ///< 折叠态顶栏（blur）
@property (nonatomic, strong) UILabel *collapsedTitle;
@property (nonatomic, strong) UIButton *backButton;
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
        _hasPhoto = peerAvatarURL.length > 0;
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
        _hasPhoto = groupAvatarURL.length > 0;    // 有群头像→进入即方形照片态，避免闪回退圈
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
    [self.navigationController setNavigationBarHidden:YES animated:animated]; // 自绘折叠顶栏 + 返回键
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // 仅当不是往更深页推进时恢复导航栏（返回上一页时）。子页各自在 viewWillAppear 恢复。
    if (self.isMovingFromParentViewController) {
        [self.navigationController setNavigationBarHidden:NO animated:animated];
    }
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
    CGFloat barH = self.topInset + 44;
    self.collapsedBar.frame = CGRectMake(0, 0, W, barH);
    self.collapsedTitle.frame = CGRectMake(60, self.topInset, W - 120, 44);
    // 与系统返回按钮同位：leading ~系统边距、垂直居中于导航区，44 触控区、图标靠左。
    self.backButton.frame = CGRectMake(4, self.topInset, 44, 44);
    self.backButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.backButton.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
    self.stickyBar.frame = CGRectMake(0, barH, W, 44);
    [self layoutSegmented:self.stickySeg inWidth:W];
    [self syncScrollInset];
    [self applyHeaderMorph]; // 尺寸变化后重算
}

/// photo 头部 = 全幅方块（约正方，morph 起点）；无头像 = 圆默认态区。
- (CGFloat)photoRestHeight { return MIN(self.view.bounds.size.width, 320); }
- (CGFloat)absorbOffset { return self.hasPhoto ? 300 : 180; } // 头像完全被"吸走"所需上滑距离
- (CGFloat)headerHeight {
    return self.topInset + (self.hasPhoto ? [self photoRestHeight] : 200);
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
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"plain"];
    [self.tableView registerClass:IMDetailMemberCell.class forCellReuseIdentifier:@"member"];
    [self.tableView registerClass:IMDetailMediaContainerCell.class forCellReuseIdentifier:@"mediagrid"];
    UIView *spacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 300)];
    spacer.backgroundColor = UIColor.clearColor;
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
    NSString *url = self.hasPhoto ? [self headerAvatarURL] : nil;

    self.avatarView = [[IMDetailAvatarView alloc] initWithFrame:CGRectZero];
    [self.avatarView setAvatarURL:url seed:seed name:name];
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

    // 群主/管理员：头像相机角标（设群头像快捷入口）。
    self.cameraBadge = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cameraBadge setImage:[UIImage systemImageNamed:@"camera.fill"] forState:UIControlStateNormal];
    self.cameraBadge.tintColor = UIColor.whiteColor;
    self.cameraBadge.backgroundColor = IMTheme.accent;
    self.cameraBadge.layer.cornerRadius = 15; self.cameraBadge.layer.masksToBounds = YES;
    self.cameraBadge.hidden = YES;
    [self.cameraBadge addTarget:self action:@selector(openGroupManage) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cameraBadge];

    // 折叠态顶栏（blur + 标题），滚动到吸附态淡入。
    self.collapsedBar = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    self.collapsedBar.alpha = 0;
    [self.view addSubview:self.collapsedBar];
    self.collapsedTitle = [self makeNameLabel:16 color:IMTheme.textPrimary shadow:NO];
    self.collapsedTitle.textAlignment = NSTextAlignmentCenter;
    self.collapsedTitle.text = name;
    [self.collapsedBar.contentView addSubview:self.collapsedTitle];

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

    // 返回键（自绘，因导航栏隐藏）——与系统默认返回按钮**同款外观**：裸 chevron.backward、accent 色、无圆底，
    // 加一层淡阴影保证压在照片上也看得清。
    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *chev = [UIImage systemImageNamed:@"chevron.backward"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold]];
    [self.backButton setImage:chev forState:UIControlStateNormal];
    // 全局白色（与首页/群聊列表右上加号一致）；下方 shadow halo 保证压在照片/浅底上也看得清。
    self.backButton.tintColor = UIColor.whiteColor;
    self.backButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.backButton.layer.shadowOpacity = 0.4; self.backButton.layer.shadowRadius = 3; // 白键需更强 halo，压浅底也清晰
    self.backButton.layer.shadowOffset = CGSizeMake(0, 1);
    [self.backButton addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.backButton];
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
    [self updateStickyTabs];
}

- (void)applyHeaderMorph {
    CGFloat W = self.view.bounds.size.width;
    if (W <= 0) { return; }
    CGFloat off = MAX(0, self.tableView.contentOffset.y); // 下拉橡皮筋不参与形变
    CGFloat top = self.topInset;
    CGFloat islandCY = MAX(11, top * 0.5);   // 状态栏/灵动岛竖直中心近似
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    CGFloat absD = 18;                        // 被吸走时的最小直径

    CGFloat w, h, cy, radiusFactor, q;        // q: 吸附(水滴→灵动岛)进度 0..1
    CGFloat p = 1;                            // p: 方→圆进度（无头像恒 1）
    if (self.hasPhoto) {
        CGFloat restH = [self photoRestHeight];
        CGFloat A1 = 150, A2 = [self absorbOffset];   // 0..A1 方→圆；A1..A2 圆→水滴→吸走
        CGFloat circD = 88, circCY = top + 56;
        p = IMSmooth(off / A1);
        q = IMSmooth((off - A1) / (A2 - A1));
        if (q <= 0) {
            w = IMLerp(W, circD, p); h = IMLerp(restH, circD, p);
            cy = IMLerp(restH / 2, circCY, p); radiusFactor = p;   // 方(0)→圆(1)
        } else {
            w = h = IMLerp(circD, absD, q);
            cy = IMLerp(circCY, islandCY, q); radiusFactor = 1;
        }
    } else {
        CGFloat A = [self absorbOffset];       // 无头像：圆默认态直接被吸走
        CGFloat restD = 92, restCY = top + 58;
        q = IMSmooth(off / A);
        w = h = IMLerp(restD, absD, q);
        cy = IMLerp(restCY, islandCY, q); radiusFactor = 1;
    }

    // 水滴拉伸：仅在吸附段，竖向拉长、横向收窄，像一滴水被吸走。
    CGFloat env = reduceMotion ? 0 : sin(M_PI * IMClamp(q, 0, 1));
    CGFloat sx = 1 - 0.18 * env, sy = 1 + 0.55 * env;
    CGFloat drawW = w * sx, drawH = h * sy;
    self.avatarView.frame = CGRectMake(W / 2 - drawW / 2, cy - drawH / 2, drawW, drawH);
    self.avatarView.layer.cornerRadius = MIN(drawW, drawH) / 2 * radiusFactor; // 方→圆 由 radiusFactor 控
    self.avatarView.alpha = q > 0.82 ? IMClamp(1 - (q - 0.82) / 0.16, 0, 1) : 1; // 末段淡出没入岛

    // 名字：图上名（photo 顶部）淡出；圆下名淡入、吸附再淡出。
    self.nameOnImage.alpha = self.hasPhoto ? IMClamp(1 - p * 2, 0, 1) : 0;
    self.subOnImage.alpha = self.nameOnImage.alpha;
    CGFloat belowIn = self.hasPhoto ? IMClamp((p - 0.5) / 0.4, 0, 1) * IMClamp(1 - q * 2.6, 0, 1)
                                    : IMClamp(1 - q * 2.4, 0, 1);
    self.nameBelow.alpha = belowIn; self.subBelow.alpha = belowIn;
    if (self.hasPhoto) {
        CGFloat ny = [self photoRestHeight] - 54;
        self.nameOnImage.frame = CGRectMake(18, ny, W - 36, 28);
        self.subOnImage.frame = CGRectMake(18, ny + 28, W - 36, 18);
    }
    CGFloat belowY = cy + drawH / 2 + 8;
    self.nameBelow.frame = CGRectMake(0, belowY, W, 26);
    self.subBelow.frame = CGRectMake(0, belowY + 26, W, 18);

    // 相机角标（群编辑头像入口；贴头像右下，吸附时淡出）。
    if (self.isGroup && !self.cameraBadge.hidden) {
        CGRect a = self.avatarView.frame;
        CGFloat pad = 16; // 离照片右/下边留白，便于点击也更美观（原先贴边）
        self.cameraBadge.frame = CGRectMake(CGRectGetMaxX(a) - 30 - pad, CGRectGetMaxY(a) - 30 - pad, 30, 30);
        self.cameraBadge.alpha = IMClamp(1 - q * 4, 0, 1);
    }

    self.collapsedBar.alpha = IMClamp((q - 0.6) / 0.4, 0, 1); // 折叠顶栏淡入
    [self fireHapticsForPhase:q hasPhoto:self.hasPhoto phaseP:p];
}

/// 锚点触感：正圆成形（photo p≈1、未进吸附）与吸附完成（q≈1）各一次；反向复位后可再触发。
- (void)fireHapticsForPhase:(CGFloat)q hasPhoto:(BOOL)hasPhoto phaseP:(CGFloat)p {
    if (q >= 0.98 && !self.didHapticAbsorb) {
        self.didHapticAbsorb = YES;
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft] impactOccurred];
        [self bumpIsland];
    }
    if (q < 0.5) { self.didHapticAbsorb = NO; }
    if (hasPhoto && q <= 0 && p >= 0.98 && !self.didHapticCircle) {
        self.didHapticCircle = YES;
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft] impactOccurred];
    }
    if (p < 0.5) { self.didHapticCircle = NO; }
}

/// 灵动岛回应：折叠顶栏做一次轻微横向鼓胀回弹（无真实岛时也是柔和反馈）。
- (void)bumpIsland {
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.x"];
    a.values = @[@1.0, @1.06, @0.99, @1.0]; a.keyTimes = @[@0, @0.35, @0.7, @1.0];
    a.duration = 0.42; a.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.34 :1.56 :0.64 :1];
    [self.collapsedBar.layer addAnimation:a forKey:@"bump"];
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
        BOOL nowHasPhoto = group.avatarURL.length > 0;
        if (nowHasPhoto != self.hasPhoto) { self.hasPhoto = nowHasPhoto; [self.view setNeedsLayout]; }
        [self.avatarView setAvatarURL:[self headerAvatarURL] seed:self.convID name:group.name];
        self.cameraBadge.hidden = !manage;
        [self refreshHeaderTexts];
        [self rebuildTabs];
        [self.tableView reloadData];
        [self.view setNeedsLayout];
    }];
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
    self.nameOnImage.text = name; self.nameBelow.text = name; self.collapsedTitle.text = name;
    self.subOnImage.text = sub; self.subBelow.text = sub;
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
    if (sec == NSNotFound || self.tabs.count == 0) { self.stickyBar.hidden = YES; return; }
    CGRect hr = [self.tableView rectForHeaderInSection:sec];
    CGFloat headerTopInView = hr.origin.y - self.tableView.contentOffset.y;
    BOOL pinned = headerTopInView <= self.topInset + 44 + 0.5;
    self.stickyBar.hidden = !pinned;
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
    [s addObject:@(IMDetailSectionPills)];
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
    return [self sectionKindAt:section] == IMDetailSectionTabs ? 44 : UITableViewAutomaticDimension;
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

#pragma mark - Cells

- (UITableViewCell *)pillsCell:(UITableView *)tv {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"plain"];
    if (!cell) { cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"plain"]; }
    for (UIView *v in cell.contentView.subviews) { [v removeFromSuperview]; }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
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
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.image = [UIImage systemImageNamed:spec[@"s"]];
        cfg.title = spec[@"t"];
        cfg.imagePlacement = NSDirectionalRectEdgeTop; cfg.imagePadding = 4;
        cfg.baseForegroundColor = IMTheme.accent;
        cfg.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *old) {
            NSMutableDictionary *d = [old mutableCopy]; d[NSFontAttributeName] = [UIFont systemFontOfSize:11]; return d;
        };
        b.configuration = cfg;
        b.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        b.layer.cornerRadius = 12; b.layer.masksToBounds = YES;
        b.accessibilityLabel = spec[@"a"];
        // 「更多」用自绘卡片，**保证锚在按钮正下方** + 上→下弹出动画（原生 UIMenu 位置由系统决定，会盖住按钮）。
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

/// 「更多」自绘卡片：锚在按钮**正下方右对齐**，从上→下 spring 弹出。清空记录=普通色；退出/删除群/拉黑=红。
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
    [self.navigationController setNavigationBarHidden:NO animated:YES];
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
    [self.navigationController setNavigationBarHidden:NO animated:YES];
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
- (void)goBack { [self.navigationController popViewControllerAnimated:YES]; }

@end
