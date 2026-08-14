//  IMChatDetailViewController.m

#import "IMChatDetailViewController.h"
#import "IMMainTabBarController.h" // im_refreshNavigationBar / kIMLiquidBarHeight
#import "IMChatDetailTabs.h"
#import "IMLiquidSegmentedControl.h" // 页签用的 Liquid Glass 分段控件
#import "IMGroupManageViewController.h"
#import "IMQRCardViewController.h"
#import "IMGroupTextViewController.h"

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
#import "IMMediaPlaceholder.h" // 磨砂占位统一渲染器（三处共用）
#import "IMMediaUtil.h"
#import "IMMediaDownloadCoordinator.h" // 媒体/文件下载编排（与聊天页共用）
#import "IMDownloadProgress.h"
#import <QuickLook/QuickLook.h>
#import <SafariServices/SafariServices.h>
#import "IMPopoverCard.h"
#import "IMGlass.h"
#import "UILabel+IMAvatar.h"
#import "UIViewController+IMToast.h"
#import "IMTheme.h"
#import "IMLog.h"
#import <objc/runtime.h>
#import "IMDropletHeaderMorph.h"
#import "IMProgram-Swift.h"

#pragma mark - 形变头像视图（图片铺满 + 首字母回退，圆角随外部调节；供头部形变用）

/// 形变头像：容器负责圆角/裁剪（随滚动 morph）。**首字母底 + 图片都用 frame-based 子视图，layoutSubviews
/// 显式铺满**——用全局同款 `IMImageLoader` + `avatarColorForSeed`（视觉与列表/成员一致），但不嵌约束到 label
/// （之前把约束图钉在 0×0 起步的 frame-based label 上，约束解析不出尺寸→图停在 0×0，只剩浅色底=空白怪形）。
@interface IMDetailAvatarView : UIView
@property (nonatomic, strong) UILabel *letter;
@property (nonatomic, strong) UIImageView *photo;
- (void)setAvatarURL:(nullable NSString *)url seed:(NSString *)seed name:(nullable NSString *)name;
@end

/// Static coordinate group hosting the moving avatar plus the fixed-Y 171pt droplet
/// mask/effects —对应 Telegram `PeerInfoAvatarListNode.containerNode`。所有子层共享同一
/// mask（灵动岛下方 171pt Lottie），因此头像缩到 50pt 时也不会被自身 bounds 切成矩形。
/// hitTest 只透传给 `interactiveChild`（头像），避免大容器吞掉表格触摸。
@interface IMDetailHeaderContainer : UIView
@property (nonatomic, weak) UIView *interactiveChild;
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

@implementation IMDetailHeaderContainer
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha <= 0.01 || !self.userInteractionEnabled) { return nil; }
    UIView *child = self.interactiveChild;
    if (!child || child.hidden || child.alpha <= 0.01) { return nil; }
    CGPoint p = [self convertPoint:point toView:child];
    if (![child pointInside:p withEvent:event]) { return nil; }
    return [child hitTest:p withEvent:event] ?: child;
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
/// @param download nil=就绪（正常显缩略图/▶）；非 nil=未下载/下载中/暂停/失败 → 显 ↓/环形进度 + 尺寸角标，
///                 且**不拉原图**（只显 thumb 模糊占位）。草图 §04「未下载格显 ↓ + 尺寸角标」。
- (void)configureWithItem:(IMMediaItem *)item download:(nullable IMDownloadProgress *)download thumb:(nullable NSString *)thumb;
@end
@implementation IMDetailMediaGridCell {
    UIImageView *_thumb; UIImageView *_play; NSString *_url;
    UIView *_dim; CAShapeLayer *_ringBG; CAShapeLayer *_ring; UILabel *_sizeChip;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _thumb = [UIImageView new];
        _thumb.contentMode = UIViewContentModeScaleAspectFill; _thumb.clipsToBounds = YES;
        _thumb.backgroundColor = UIColor.tertiarySystemFillColor;
        _thumb.frame = self.contentView.bounds;
        _thumb.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.contentView addSubview:_thumb];
        _dim = [[UIView alloc] initWithFrame:self.contentView.bounds];
        _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32];
        _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _dim.hidden = YES;
        [self.contentView addSubview:_dim];

        _play = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.circle.fill"]];
        _play.tintColor = UIColor.whiteColor; _play.hidden = YES;
        _play.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_play];
        [NSLayoutConstraint activateConstraints:@[
            [_play.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_play.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];

        _ringBG = [IMDetailMediaGridCell ringLayerWithColor:[UIColor colorWithWhite:1 alpha:0.32] rounded:NO];
        _ring = [IMDetailMediaGridCell ringLayerWithColor:UIColor.whiteColor rounded:YES];
        [self.contentView.layer addSublayer:_ringBG];
        [self.contentView.layer addSublayer:_ring];

        _sizeChip = [UILabel new];
        _sizeChip.font = [UIFont monospacedDigitSystemFontOfSize:9 weight:UIFontWeightMedium];
        _sizeChip.textColor = UIColor.whiteColor;
        _sizeChip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        _sizeChip.textAlignment = NSTextAlignmentCenter;
        _sizeChip.layer.cornerRadius = 7; _sizeChip.clipsToBounds = YES;
        _sizeChip.hidden = YES;
        [self.contentView addSubview:_sizeChip];
    }
    return self;
}

+ (CAShapeLayer *)ringLayerWithColor:(UIColor *)color rounded:(BOOL)rounded {
    UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:CGPointMake(17, 17) radius:14
                                                 startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
    CAShapeLayer *l = [CAShapeLayer layer];
    l.path = p.CGPath; l.fillColor = UIColor.clearColor.CGColor; l.strokeColor = color.CGColor;
    l.lineWidth = 2.5; l.frame = CGRectMake(0, 0, 34, 34); l.hidden = YES;
    if (rounded) { l.lineCap = kCALineCapRound; l.strokeEnd = 0; }
    return l;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = [_sizeChip sizeThatFits:CGSizeMake(CGFLOAT_MAX, 14)];
    _sizeChip.frame = CGRectMake(3, 3, s.width + 8, 14);
    if (_ring.hidden && _ringBG.hidden) { return; }
    CGRect f = CGRectMake((self.bounds.size.width - 34) / 2, (self.bounds.size.height - 34) / 2, 34, 34);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _ringBG.frame = f; _ring.frame = f;
    [CATransaction commit];
}

- (void)configureWithItem:(IMMediaItem *)item download:(IMDownloadProgress *)dp thumb:(NSString *)thumb {
    _url = item.url; _thumb.image = nil;
    BOOL gated = dp != nil && dp.phase != IMDownloadPhaseDone;
    __weak typeof(self) ws = self; NSString *want = item.url;
    void (^apply)(UIImage *) = ^(UIImage *img) {
        __strong typeof(ws) self = ws;
        if (self && [self->_url isEqualToString:want]) { self->_thumb.image = img; }
    };
    [self applyGate:gated ? dp : nil isVideo:item.isVideo];
    if (gated) {
        // 门控格不拉原图/封面（方案 A·纯净门控）：只把内嵌 thumb 过高斯磨砂显示，与聊天气泡同款；无 thumb 留灰底。
        if (thumb.length > 0) {
            UIImage *cachedFrost = [IMMediaPlaceholder cachedFrostedForThumb:thumb];
            if (cachedFrost) {
                _thumb.image = cachedFrost;
            } else {
                [IMMediaPlaceholder frostedForThumb:thumb completion:^(UIImage *blurred) {
                    __strong typeof(ws) self = ws;
                    if (self && blurred && [self->_url isEqualToString:want]) { self->_thumb.image = blurred; }
                }];
            }
        }
        return;
    }
    if (item.isVideo) { [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:item.url completion:apply]; }
    else { [[IMImageLoader shared] loadImageURL:item.url completion:apply]; }
}

/// 门控外观：中心 ↓/⏸/↻ + 压暗 + 环形进度 + 左上角尺寸角标；dp=nil 清回就绪（缩略图 / ▶）。
- (void)applyGate:(IMDownloadProgress *)dp isVideo:(BOOL)isVideo {
    if (!dp) {
        _dim.hidden = YES; _ring.hidden = YES; _ringBG.hidden = YES; _sizeChip.hidden = YES;
        _play.image = [UIImage systemImageNamed:@"play.circle.fill"];
        _play.hidden = !isVideo;
        self.isAccessibilityElement = NO; self.accessibilityLabel = nil;
        return;
    }
    _dim.hidden = NO;
    NSString *sym = IMDownloadCenterSymbolName(dp);   // nil 只可能是「已失效」→ 不给按钮，无从重试
    _play.image = sym ? [UIImage systemImageNamed:sym] : nil;
    _play.hidden = sym == nil;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = [dp accessibilityText];
    BOOL ring = dp.phase == IMDownloadPhaseDownloading || dp.phase == IMDownloadPhasePaused;
    _ring.hidden = !ring; _ringBG.hidden = !ring;
    if (ring) {
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        _ring.strokeEnd = MAX(0.02, dp.fraction);
        [CATransaction commit];
    }
    NSString *text = [dp displayText];
    _sizeChip.text = text;
    _sizeChip.hidden = text.length == 0;
    [self setNeedsLayout];
}

/// 进度就地更新：只重画门控外观（环/中心图标/尺寸角标），不动缩略图。
/// 只在下载中/暂停/失败态被调用（完成走 onStateChanged reload），dp 非空时 applyGate: 不读 isVideo。
- (void)updateDownload:(IMDownloadProgress *)dp {
    if (!dp || dp.phase == IMDownloadPhaseDone) { return; }
    [self applyGate:dp isVideo:NO];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _thumb.image = nil;
    [self applyGate:nil isVideo:NO];
}
@end

@interface IMDetailMediaContainerCell : UITableViewCell <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy, nullable) void (^onPick)(IMMediaItem *item);
/// 逐格门控（M4-7）：返回 nil=该格就绪；非 nil=未下载/下载中/暂停/失败，点击走 onDownloadItem。
@property (nonatomic, copy, nullable) IMDownloadProgress *_Nullable (^stateForItemIndex)(NSInteger index);
/// 该格的极小模糊预览（thumb data URI），门控时用作占位。
@property (nonatomic, copy, nullable) NSString *_Nullable (^thumbForItemIndex)(NSInteger index);
/// 门控格点击（开始/暂停/继续/重试）。
@property (nonatomic, copy, nullable) void (^onDownloadItemIndex)(NSInteger index);
/// 内容宽确定/变化时回调（供外部按真实宽度重算行高，消除卡片底部白边）。
@property (nonatomic, copy, nullable) void (^onContentWidthChanged)(CGFloat width);
/// 逐格长按菜单（任务2：转发/定位到聊天/[取消下载]/删除两档，与文件行一致）——由 VC 提供，返回 nil=不显示。
@property (nonatomic, copy, nullable) UIContextMenuConfiguration *_Nullable (^contextMenuForItemIndex)(NSInteger index);
- (void)setItems:(NSArray<IMMediaItem *> *)items;
/// 重配一格（用于「下载完成/解除门控」——需要重新拉原图）。
- (void)refreshItemAtIndex:(NSInteger)index;
/// 进度**就地更新**一格（高频回调用）：只改该格的环/图标/角标，不 reloadItems（reloadItems 每次都重拉图 + 卡顿）。
- (void)updateItemAtIndex:(NSInteger)index download:(nullable IMDownloadProgress *)dp;
+ (CGFloat)heightForCount:(NSInteger)count width:(CGFloat)width;
@end
@implementation IMDetailMediaContainerCell {
    UICollectionView *_cv; NSArray<IMMediaItem *> *_items;
    CGFloat _lastReportedWidth; // 已上报给外部的内容宽（去抖，避免每次布局都回调）
}

/// 内容宽首次确定/变化时上报（旋转、iPad 分屏）。
/// 存在的理由：行高由外部按「假设的 InsetGrouped 内缩」估算，而格子按 cell 真实宽度排布；
/// 两者一旦不一致，行高就会比宫格内容高出几 pt，卡片底部露出白边。以真实宽度为准即可消除。
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    if (w > 0 && ABS(w - _lastReportedWidth) > 0.5) {
        _lastReportedWidth = w;
        if (self.onContentWidthChanged) { self.onContentWidthChanged(w); }
    }
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
- (void)refreshItemAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_items.count) { return; }
    [_cv reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:index inSection:0]]];
}
- (void)updateItemAtIndex:(NSInteger)index download:(IMDownloadProgress *)dp {
    if (index < 0 || index >= (NSInteger)_items.count) { return; }
    IMDetailMediaGridCell *c = (IMDetailMediaGridCell *)[_cv cellForItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];
    if ([c isKindOfClass:IMDetailMediaGridCell.class]) { [c updateDownload:dp]; }
}
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return _items.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    IMDetailMediaGridCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"g" forIndexPath:ip];
    IMDownloadProgress *dp = self.stateForItemIndex ? self.stateForItemIndex(ip.item) : nil;
    NSString *thumb = (dp && self.thumbForItemIndex) ? self.thumbForItemIndex(ip.item) : nil;
    [c configureWithItem:_items[ip.item] download:dp thumb:thumb];
    return c;
}
- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat t = [IMDetailMediaContainerCell tileForWidth:cv.bounds.size.width];
    return CGSizeMake(t, t);
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    // 门控格：点击=就地下载（铁律①不跳页），**不**进查看器；就绪格才打开（铁律②完成即止）。
    IMDownloadProgress *dp = self.stateForItemIndex ? self.stateForItemIndex(ip.item) : nil;
    if (dp && dp.phase != IMDownloadPhaseDone) {
        if (self.onDownloadItemIndex) { self.onDownloadItemIndex(ip.item); }
        return;
    }
    if (self.onPick) { self.onPick(_items[ip.item]); }
}
/// 逐格长按菜单（任务2）：转发/定位/取消下载/删除——与文件行同一套，由 VC 按该格消息构造。
- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv
    contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    return self.contextMenuForItemIndex ? self.contextMenuForItemIndex(ip.item) : nil;
}
@end

#pragma mark - 文件行 Cell（三态：未下载 / 下载中 / 已下载，草图 §04）

/// 左图标位即状态位：已下载=文件类型图标；未下载=灰底 ↓；下载中=环形进度 + ⏸；暂停=↓（副行带 ⏸ 前缀）；失败=红 ↻。
/// **无右侧配件**：点行=下载/暂停/继续/打开；取消下载走长按菜单（仅进行中的文件才有该项）。
@interface IMDetailFileCell : UITableViewCell
- (void)configureWithMessage:(IMMessageModel *)m download:(nullable IMDownloadProgress *)dp;
/// 进度**就地更新**（不 reload）：只改图标位环/字形 + 副行文案；文件名不变。
- (void)updateDownload:(nullable IMDownloadProgress *)dp;
@end

@implementation IMDetailFileCell {
    UIImageView *_icon; UIImageView *_glyph; CAShapeLayer *_ringBG; CAShapeLayer *_ring;
    CAShapeLayer *_disc;       // 未下载态：与圆环同心同径的 accent 实心圆底（与聊天页文件气泡同款）
    UILabel *_title; UILabel *_sub;
    NSString *_fileName;       // configure 时记住，进度就地更新复用（免重传 message）
    int64_t _fileSizeBytes;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        _icon = [UIImageView new];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        _icon.layer.cornerRadius = 8; _icon.clipsToBounds = YES;
        [self.contentView addSubview:_icon];

        _glyph = [UIImageView new];       // 图标位中心的状态字形（↓ / ⏸ / ↻）
        _glyph.contentMode = UIViewContentModeCenter;
        _glyph.tintColor = UIColor.whiteColor;
        _glyph.translatesAutoresizingMaskIntoConstraints = NO;
        _glyph.hidden = YES;
        [self.contentView addSubview:_glyph];

        _ringBG = [IMDetailFileCell ringLayerWithColor:[IMTheme.textSecondary colorWithAlphaComponent:0.25] rounded:NO];
        _ring = [IMDetailFileCell ringLayerWithColor:IMTheme.accent rounded:YES];
        _disc = [CAShapeLayer layer];   // 实心圆底 r15，与圆环同心（18,18）；填充留到 render 时置 accent
        _disc.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(18, 18) radius:15
                                                startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES].CGPath;
        _disc.fillColor = UIColor.clearColor.CGColor;
        _disc.frame = CGRectMake(0, 0, 36, 36);
        _disc.hidden = YES;
        // 圆底/圆环挂在 _icon.layer 上，随 _icon 固定的 36×36 frame 自动定位，无需在 layoutSubviews
        // 手动同步坐标。旧写法把它们挂在 contentView.layer、每次布局再 `frame = _icon.frame`：
        // iOS 26 上 cell 的 layoutSubviews 读到的 _icon.frame 尚未由约束解算，圆圈整体错位到左侧。
        // _glyph 仍是 contentView 的子视图、恒在 _icon 之上，↓/⏸ 字形照旧压在圆底之上。
        [_icon.layer addSublayer:_disc];    // 实心圆底（最底）
        [_icon.layer addSublayer:_ringBG];  // 灰轨
        [_icon.layer addSublayer:_ring];    // 进度环

        _title = [UILabel new];
        _title.font = [UIFont systemFontOfSize:16];
        _title.lineBreakMode = NSLineBreakByTruncatingMiddle; // 文件名尾部是扩展名，中间截断更可读
        _title.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_title];

        _sub = [UILabel new];
        _sub.font = [UIFont systemFontOfSize:12];
        _sub.textColor = IMTheme.textSecondary;
        _sub.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_sub];

        // 无右侧配件：文件名/副行直接贴内容区右缘（留 16 边距）。
        [NSLayoutConstraint activateConstraints:@[
            [_icon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:36],
            [_icon.heightAnchor constraintEqualToConstant:36],
            [_glyph.centerXAnchor constraintEqualToAnchor:_icon.centerXAnchor],
            [_glyph.centerYAnchor constraintEqualToAnchor:_icon.centerYAnchor],
            [_title.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:12],
            [_title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:9],
            [_title.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_sub.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
            [_sub.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:2],
            [_sub.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_sub.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-9],
        ]];
    }
    return self;
}
+ (CAShapeLayer *)ringLayerWithColor:(UIColor *)color rounded:(BOOL)rounded {
    UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:CGPointMake(18, 18) radius:15
                                                 startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
    CAShapeLayer *l = [CAShapeLayer layer];
    l.path = p.CGPath; l.fillColor = UIColor.clearColor.CGColor; l.strokeColor = color.CGColor;
    l.lineWidth = 2.5; l.frame = CGRectMake(0, 0, 36, 36); l.hidden = YES;
    if (rounded) { l.lineCap = kCALineCapRound; l.strokeEnd = 0; }
    return l;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // 圆底/圆环已作为 _icon.layer 的子层、frame 恒为 (0,0,36,36)，随 _icon 自动定位，
    // 这里不再需要手动把它们同步到 _icon.frame（那正是 iOS 26 下错位的来源）。
    // 兜底：_icon 尺寸恒定 36×36，若 bounds 异常则纠回，防端上极端布局把子层拉变形。
    if (!CGRectEqualToRect(_disc.frame, _icon.bounds) && !CGRectIsEmpty(_icon.bounds)) {
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        _ringBG.frame = _ring.frame = _disc.frame = _icon.bounds;
        [CATransaction commit];
    }
}
- (void)configureWithMessage:(IMMessageModel *)m download:(IMDownloadProgress *)dp {
    _fileName = m.fileName.length > 0 ? m.fileName : @"文件";
    _fileSizeBytes = m.fileSize;
    _title.text = _fileName;
    [self renderDownload:dp];
}

/// 依 dp + 记住的文件名/大小渲染（configure 与进度就地更新共用）。
- (void)renderDownload:(IMDownloadProgress *)dp {
    NSString *size = IMFormatFileSize(_fileSizeBytes);
    BOOL gated = dp != nil && dp.phase != IMDownloadPhaseDone;
    BOOL ring = dp.phase == IMDownloadPhaseDownloading || dp.phase == IMDownloadPhasePaused;
    // ⚠️ 必须带 `dp != nil`：IMDownloadPhaseNotStarted == 0，给 nil 发 phase 也返回 0，
    // 已下载但无活跃状态的文件（dp==nil，重进页面/从 DB 重建即是）会被误判为「未下载」，
    // 于是一边走 !gated 分支画文件图标、一边把绿色实心圆底(_disc)显示出来，圆盖在图标上。
    BOOL notStarted = dp != nil && dp.phase == IMDownloadPhaseNotStarted;
    BOOL failed = dp.phase == IMDownloadPhaseFailed;
    _ringBG.hidden = _ring.hidden = !ring;
    _disc.hidden = !notStarted;
    if (!gated) { // 已下载：文件类型图标 + 「1.3 MB · 已下载」（无配件、无 glyph）。
        // 明确清空所有下载态覆盖层：不依赖上面各布尔的推导，杜绝任何误判把圆底/圆环漏进已下载态。
        _disc.hidden = _ring.hidden = _ringBG.hidden = YES;
        _icon.image = IMFileTypeIconForName(_fileName, 36);
        _icon.backgroundColor = UIColor.clearColor;
        _glyph.hidden = YES;
        _sub.attributedText = nil;
        _sub.textColor = IMTheme.textSecondary;
        _sub.text = size.length > 0 ? [NSString stringWithFormat:@"%@ · 已下载", size] : @"已下载";
        self.accessibilityLabel = [NSString stringWithFormat:@"%@，已下载", _fileName ?: @"文件"];
        [self setNeedsLayout];
        return;
    }
    // 门控态与聊天页文件气泡同款：不再刷彩色圆角方块底。未下载=accent 实心圆底+白↓；
    // 下载中/暂停=灰轨+accent 进度环+accent 线性字形；失败=danger 字形（无底无环）。
    _icon.image = nil;
    _icon.backgroundColor = UIColor.clearColor;
    UIColor *tint = failed ? IMTheme.danger : IMTheme.accent;
    if (notStarted) { _disc.fillColor = IMTheme.accent.CGColor; }
    if (ring) {
        _ringBG.strokeColor = [IMTheme.textSecondary colorWithAlphaComponent:0.25].CGColor;
        _ring.strokeColor = tint.CGColor;
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        _ring.strokeEnd = MAX(0.02, dp.fraction);
        [CATransaction commit];
    }
    NSString *glyph = notStarted ? @"arrow.down"
        : (dp.phase == IMDownloadPhaseDownloading) ? (dp.pausable ? @"pause.fill" : nil)
        : failed ? (dp.expired ? @"xmark.octagon" : @"arrow.clockwise") // 已失效：不给重试
        : @"arrow.down"; // 暂停
    UIColor *glyphColor = notStarted ? UIColor.whiteColor : tint; // 白↓落在实心圆底；其余=accent/danger 线性字形
    if (glyph.length > 0) {
        _glyph.image = [[UIImage systemImageNamed:glyph
                                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold]]
                        imageWithTintColor:glyphColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        _glyph.hidden = NO;
    } else {
        _glyph.image = nil; _glyph.hidden = YES; // 下载中不可暂停：仅进度环、无字形（与聊天页一致）
    }
    // 副行：未下载=「240 KB · 未下载」；下载中=「18 MB / 42 MB」；暂停=行首 ⏸ + 「已下/总」（与文件气泡一致）；失败=文案。
    UIColor *subColor = failed ? IMTheme.danger : IMTheme.textSecondary;
    _sub.textColor = subColor;
    if (dp.phase == IMDownloadPhasePaused) {
        _sub.attributedText = [IMDetailFileCell pausedSubtitle:[dp fileLineText] color:subColor font:_sub.font];
    } else {
        _sub.attributedText = nil;
        _sub.text = (dp.phase == IMDownloadPhaseNotStarted)
            ? (size.length > 0 ? [NSString stringWithFormat:@"%@ · 未下载", size] : @"未下载")
            : [dp fileLineText];
    }
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", _fileName ?: @"文件", [dp accessibilityText]];
    [self setNeedsLayout];
}

/// 暂停态副行：行首嵌一个小 ⏸ 图标 + 已下/总（与 IMBubbleCell 暂停态同款，图标零成本示意"已暂停"）。
+ (NSAttributedString *)pausedSubtitle:(NSString *)text color:(UIColor *)color font:(UIFont *)font {
    UIImage *icon = [[UIImage systemImageNamed:@"pause.fill"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:9 weight:UIImageSymbolWeightBold]]
                     imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
    NSTextAttachment *att = [NSTextAttachment new];
    att.image = icon;
    att.bounds = CGRectMake(0, (font.capHeight - 9) / 2.0, 9, 9);
    NSMutableAttributedString *s = [[NSAttributedString attributedStringWithAttachment:att] mutableCopy];
    [s appendAttributedString:[[NSAttributedString alloc]
        initWithString:[@" " stringByAppendingString:(text ?: @"")]
            attributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: color }]];
    return s;
}

- (void)updateDownload:(IMDownloadProgress *)dp {
    [self renderDownload:dp];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _ring.hidden = YES; _ringBG.hidden = YES; _disc.hidden = YES; _ring.strokeEnd = 0;
    _glyph.hidden = YES; _icon.image = nil; _icon.backgroundColor = UIColor.clearColor;
    _sub.attributedText = nil;
}
@end

#pragma mark - 详情页

/// 页面分区（动态组装到 _sections）。
typedef NS_ENUM(NSInteger, IMDetailSection) {
    IMDetailSectionPills = 0,  ///< 操作排（静音/搜索/更多）
    IMDetailSectionInfo,       ///< 单聊：备注名 / 用户名
    IMDetailSectionAbout,      ///< 群公告 / 群简介（群聊·全员只读·非空才显，G1 修·决策 17）
    IMDetailSectionSettings,   ///< 置顶 / 免打扰（+群主管理员：群管理）
    IMDetailSectionTabs,       ///< 分类页签内容（header=分段控件）
};

static CGFloat const kPillsRowH = 78;
static CGFloat const kTabBarH   = 52;   ///< 页签栏高度（含分段控件上下留白）；分段控件本体 = kTabBarH-12
static CGFloat const kTabSegH   = 40;   ///< 分段控件本体高度（点击面积）

/// 标题栏「变实」上限：头部收拢完成（名字/成员已进标题栏）时的不透明程度。
/// 1.0=完全不透明（内容绝不透出）；调小可保留一点通透感。仅影响本页，其他页面不受影响。
static CGFloat const kNavOpaqueOnCollapse = 0.8;

@interface IMChatDetailViewController () <UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate, IMLiquidNavigationBarDelegate, QLPreviewControllerDataSource>
// 身份
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *convID;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, strong) IMDatabaseAccountContext *databaseContext;
// 单聊对端
@property (nonatomic, copy, nullable) NSString *peerID;
@property (nonatomic, copy, nullable) NSString *peerNickname;
@property (nonatomic, copy, nullable) NSString *peerAvatarURL;
@property (nonatomic, assign) BOOL peerBlocked;
// 好友准入（微信式，任务一 P0）：非好友不显示「消息/呼叫/视频」，改显「加好友」。
// 乐观默认 YES（多数单聊入口=已有好友），loadPeerBlockState 拉到关系后校正并重建操作排。
@property (nonatomic, assign) BOOL peerIsFriend;
// 群成员长按菜单用：我的 accepted 好友 uid 集合（决定成员菜单显「发送消息」还是「添加好友」）。
@property (nonatomic, strong, nullable) NSSet<NSString *> *friendUIDs;
// showsMessagePill 已提升为公开属性（见 .h）：单聊从群成员/通讯录等外部进入时显示「消息」入口。
// 群
@property (nonatomic, copy, nullable) NSString *groupName;
@property (nonatomic, strong, nullable) IMGroupInfo *group;
// 会话设置
@property (nonatomic, assign) int64_t pinnedAt;
@property (nonatomic, assign) BOOL muted;
// UI
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) IMDetailHeaderContainer *headerContainer; ///< 静态坐标容器：承载头像 + 灵动岛遮罩/覆盖层
@property (nonatomic, strong) IMDetailAvatarView *avatarView;
@property (nonatomic, strong) UIView *dropletBottomCover;                  ///< 灵动岛下方黑底（Telegram bottomCoverNode）
@property (nonatomic, strong) IMTelegramAvatarEffectsView *dropletTopCover;///< 顶部 blur+gradient+fade（topCoverNode）
@property (nonatomic, strong) IMTelegramAvatarMaskView *dropletMask;       ///< 171pt Lottie（UserAvatarMask）
@property (nonatomic, strong) UILabel *nameOnImage;   ///< 图上名（photo 模式顶部）
@property (nonatomic, strong) UILabel *subOnImage;
@property (nonatomic, strong) UILabel *nameBelow;     ///< 圆头像下居中名
@property (nonatomic, strong) UILabel *subBelow;
@property (nonatomic, strong) IMLiquidNavigationBar *liquidNavigationBar;
@property (nonatomic, strong) IMDropletHeaderMorph *headerMorph; ///< 共享 Zone① 头部形变驱动（与「我」页同一套）
@property (nonatomic, strong) UIView *pillsView;            ///< 搜索/更多独立按钮，放在 tableHeader 中避开 grouped 卡片背景
// 页签
@property (nonatomic, strong) IMLiquidSegmentedControl *segmented;
@property (nonatomic, strong) UIView *stickyBar;               ///< 页签滚到顶时的悬浮吸顶条（透明，仅托分段控件）
@property (nonatomic, strong) IMLiquidSegmentedControl *stickySeg;   ///< 吸顶条内镜像分段控件
@property (nonatomic, strong) NSArray<IMChatDetailTab *> *tabs;
@property (nonatomic, assign) NSInteger selectedTab;
@property (nonatomic, strong) NSArray<IMMediaItem *> *tabMedia;    ///< 当前媒体项（媒体页签）
@property (nonatomic, strong) NSArray<IMMessageModel *> *tabMediaMessages; ///< 与 tabMedia **逐位对齐**的消息模型（下载态/thumb 取自它）
@property (nonatomic, strong) NSArray<IMMessageModel *> *tabRows;  ///< 当前文件/语音/链接消息
/// 媒体/文件 Tab 的下载编排（M4-7）：与聊天页共用 IMMediaDownloadCoordinator，同一份文件天然共享一个下载态。
@property (nonatomic, strong) IMMediaDownloadCoordinator *downloads;
@property (nonatomic, weak, nullable) IMDetailMediaContainerCell *mediaContainerCell; ///< 只刷单格用（避免整行重建）
@property (nonatomic, assign) CGFloat mediaGridWidth;   ///< 宫格 cell 的真实内容宽（0=未知，由 cell 上报）
@property (nonatomic, strong, nullable) NSURL *quickLookURL;  ///< QuickLook 当前预览的本地文件
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
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        if (![context.ownerUserID isEqualToString:userID]) {
            IMLogDatabase(@"单聊详情页账号与当前数据库上下文不一致 page_uid=%@ db_uid=%@",
                          userID, context.ownerUserID ?: @"(none)");
        }
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        _isGroup = NO;
        _peerIsFriend = YES; // 乐观默认，loadPeerBlockState 校正
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
        IMDatabaseAccountContext *context = IMDatabase.sharedDatabase.currentAccountContext;
        if (![context.ownerUserID isEqualToString:userID]) {
            IMLogDatabase(@"群详情页账号与当前数据库上下文不一致 page_uid=%@ db_uid=%@",
                          userID, context.ownerUserID ?: @"(none)");
        }
        _databaseContext = [context.ownerUserID isEqualToString:userID] ? context : nil;
        _groupName = [groupName copy]; _isGroup = YES;
        _peerAvatarURL = [groupAvatarURL copy];   // 复用字段承载群头像，供 headerAvatarURL 立即取用
        _hasPhoto = NO;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (BOOL)performDatabaseOperation:(void (^)(IMDatabase *database))operation {
    return [IMDatabase.sharedDatabase performWithAccountContext:self.databaseContext block:operation];
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
        [self loadFriendUIDs]; // 群成员长按菜单据此显「发送消息」(好友) / 「添加好友」(非好友)
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onGroupEvent:)
                                                   name:IMSocketDidReceiveGroupEventNotification object:nil];
    } else {
        [self loadPeerBlockState];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onConvUpdate:)
                                               name:IMSocketDidUpdateConversationNotification object:nil];
    // 任务2：消息被物理移除（为所有人删除 / 仅为我删除）→ 重建页签内容（文件列表随之更新）。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onMessageRemoved:)
                                               name:IMSocketDidRemoveMessageNotification object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Telegram 风格详情页：保留 UINavigationController 堆栈和侧滑返回，但隐藏系统导航栏。
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    // 回前台抢回下载回调（同聊天页）：文件列表 + 媒体宫格里仍在跑的任务，防返回后进度条冻结。
    if (_downloads) {
        NSMutableArray<IMMessageModel *> *ms = [NSMutableArray array];
        if (self.tabRows.count) { [ms addObjectsFromArray:self.tabRows]; }
        if (self.tabMediaMessages.count) { [ms addObjectsFromArray:self.tabMediaMessages]; }
        [_downloads reattachActiveTasksForMessages:ms];
    }
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
    self.stickyBar.frame = CGRectMake(0, [self tabPinTop], W, kTabBarH);
    [self layoutSegmented:self.stickySeg inWidth:W];
    [self syncScrollInset];
    [self applyHeaderMorph]; // 尺寸变化后重算
    [self updatePillsVisibility];
}

/// 所有详情页统一使用圆形头像头部；URL 仅替换头像内容。
- (CGFloat)headerHeight {
    return self.topInset + 200 + 8 + kPillsRowH;
}

/// 底部 inset + 橡皮筋策略：
/// - **始终**补足到「能滚到头部收拢(H) + 页签贴顶(pin)」→ 任何内容长度都能上滑贴顶、点 tab 也能贴顶。
/// - 内容够长（贴顶后列表仍填满屏幕）→ 允许橡皮筋、可继续自然滚动（走 Zone② detent）。
/// - 内容不足（贴顶后下方是空白）→ `bounces=NO`：能滚到 pin 但**贴顶后禁止再越界上滑**（2(2)a，硬停不回弹）。
- (void)syncScrollInset {
    CGFloat viewH = self.tableView.bounds.size.height;
    if (viewH <= 0) { return; }
    CGFloat pin = [self pinOffset];
    CGFloat wantMax = MAX([self headerCollapseOffset], pin);        // 至少能滚到收拢 + 贴顶
    CGFloat naturalMax = self.tableView.contentSize.height - viewH; // 不含 inset 的最大 offset
    CGFloat bottom = MAX(0, wantMax - naturalMax);
    if (ABS(self.tableView.contentInset.bottom - bottom) > 0.5) {
        self.tableView.contentInset = UIEdgeInsetsMake(0, 0, bottom, 0);
    }
    // 贴顶后是否还有内容可滚：有→允许橡皮筋自然滚动；没有→硬停（贴顶即到顶，禁止越界上滑）。
    BOOL longEnough = naturalMax >= pin - 0.5;
    self.tableView.bounces = longEnough;
    self.tableView.alwaysBounceVertical = longEnough;
}

#pragma mark - 构建 UI

- (void)buildTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.sectionHeaderTopPadding = 0;
    // 关闭高度估算：所有行/页眉走精确 heightFor…，reloadData 后 contentSize / rectForHeaderInSection 立即准确，
    // 切 tab 时 pinOffset 才不会因估算落偏（#4 维持贴顶的前提）。
    self.tableView.estimatedRowHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    self.tableView.estimatedSectionFooterHeight = 0;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"plain"];
    [self.tableView registerClass:IMDetailMemberCell.class forCellReuseIdentifier:@"member"];
    [self.tableView registerClass:IMDetailMediaContainerCell.class forCellReuseIdentifier:@"mediagrid"];
    [self.tableView registerClass:IMDetailFileCell.class forCellReuseIdentifier:@"detailfile"];
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

/// 操作排按钮规格（header 悬浮 pills 与 actions cell 共用，保证一致）。
/// 微信式好友准入（任务一 P0）：单聊非好友只显「加好友 + 更多」，不显「消息/呼叫/视频」——
/// 非好友发消息会被服务端 200103 拒收，故不给发消息入口，主入口是加好友。
- (NSArray<NSDictionary *> *)actionPillSpecs {
    NSMutableArray *specs = [NSMutableArray array];
    if (!self.isGroup) {
        if (!self.peerIsFriend) {
            [specs addObject:@{@"t": @"加好友", @"s": @"person.badge.plus", @"a": @"addfriend"}];
        } else {
            if (self.showsMessagePill) {
                [specs addObject:@{@"t": @"消息", @"s": @"bubble.right.fill", @"a": @"message"}];
            }
            [specs addObject:@{@"t": @"呼叫", @"s": @"phone.fill", @"a": @"call"}];
            [specs addObject:@{@"t": @"视频", @"s": @"video.fill", @"a": @"video"}];
        }
    }
    // 搜索：群聊与**单聊好友**都显示（对齐 im-web；功能待开发，点击走占位 toast）。
    // 非好友不显示——尚无聊天记录可搜，与隐藏备注名/设置/页签三张卡同一判据。
    if (self.isGroup || self.peerIsFriend) {
        [specs addObject:@{@"t": @"搜索", @"s": @"magnifyingglass", @"a": @"search"}];
    }
    [specs addObject:@{@"t": @"更多", @"s": @"ellipsis", @"a": @"more"}];
    return specs;
}

/// 操作排单个按钮（header 悬浮 pills 与 actions cell 共用，保证外观一致）。
/// iOS 26 的 glassButtonConfiguration 前景走单色化（≈label 色，浅色下即黑），会吞掉 baseForegroundColor 的 accent，
/// 于是「搜索/更多/呼叫/视频」恒为黑（iOS 18 的 grayButtonConfiguration 尊重 baseForegroundColor，故无此问题）。
/// 解决：把 accent 直接烘进图标（AlwaysOriginal）与标题（显式前景色），绕开玻璃单色化——两系统都稳定显 accent。
- (UIButton *)actionPillButtonForSpec:(NSDictionary *)spec {
    UIColor *tint = IMTheme.accent;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = IMGlassButtonConfiguration();
    cfg.image = [[UIImage systemImageNamed:spec[@"s"]] imageWithTintColor:tint renderingMode:UIImageRenderingModeAlwaysOriginal];
    cfg.title = spec[@"t"];
    cfg.imagePlacement = NSDirectionalRectEdgeTop;
    cfg.imagePadding = 4;
    cfg.baseForegroundColor = tint;   // iOS 18 生效；iOS 26 由下面的显式前景色兜底
    cfg.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *old) {
        NSMutableDictionary *attrs = [old mutableCopy];
        attrs[NSFontAttributeName] = [UIFont systemFontOfSize:11];
        attrs[NSForegroundColorAttributeName] = tint;
        return attrs;
    };
    cfg.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    button.configuration = cfg;
    button.tintColor = tint;
    button.accessibilityLabel = spec[@"a"];
    [button addTarget:self action:([spec[@"a"] isEqualToString:@"more"] ? @selector(moreTapped:) : @selector(pillTapped:))
     forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/// 好友态变化后原地重建 header 悬浮操作排（frame 由 viewDidLayoutSubviews 复位）。
- (void)rebuildPillsView {
    UIView *spacer = self.pillsView.superview;
    if (!spacer) { return; }
    [self.pillsView removeFromSuperview];
    self.pillsView = [self buildPillsView];
    [spacer addSubview:self.pillsView];
    [self.view setNeedsLayout];
}

- (UIView *)buildPillsView {
    UIView *host = [UIView new];
    host.backgroundColor = UIColor.clearColor;
    NSArray<NSDictionary *> *specs = [self actionPillSpecs];

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
        [stack addArrangedSubview:[self actionPillButtonForSpec:spec]];
    }
    return host;
}

/// 给分段控件挂"点击即贴顶"的 tap（与其自身选择手势并存），支持单 tab / 重复点当前 tab 也贴顶。
- (void)addTabPinTapTo:(IMLiquidSegmentedControl *)seg {
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

    // 静态头部容器：完整覆盖遮罩带（灵动岛下 171pt）+ 头像 rest 位置。
    // 头像/黑底/effects/mask 全部挂在这里，mask 作用于容器本身而非小尺寸头像，
    // 避免 171pt 遮罩被 50pt 头像 bounds 裁成矩形。
    self.headerContainer = [[IMDetailHeaderContainer alloc] initWithFrame:CGRectZero];
    self.headerContainer.backgroundColor = UIColor.clearColor;
    self.headerContainer.userInteractionEnabled = YES;
    self.headerContainer.clipsToBounds = NO;
    [self.view addSubview:self.headerContainer];

    // 灵动岛遮罩底层黑底：对应 Telegram `bottomCoverNode`，alpha 随 maskValue 线性增长。
    self.dropletBottomCover = [[UIView alloc] initWithFrame:CGRectZero];
    self.dropletBottomCover.userInteractionEnabled = NO;
    self.dropletBottomCover.hidden = YES;
    self.dropletBottomCover.backgroundColor = [UIColor colorWithWhite:0 alpha:0];
    [self.headerContainer addSubview:self.dropletBottomCover];

    self.avatarView = [[IMDetailAvatarView alloc] initWithFrame:CGRectZero];
    [self.avatarView setAvatarURL:url seed:seed name:name];
    self.avatarView.userInteractionEnabled = YES;
    [self.avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped)]];
    [self.headerContainer addSubview:self.avatarView];
    self.headerContainer.interactiveChild = self.avatarView;

    // 顶部 blur+径向渐变+黑色淡入：对应 Telegram `topCoverNode` (DynamicIslandBlurNode)。
    self.dropletTopCover = [[IMTelegramAvatarEffectsView alloc] initWithFrame:CGRectZero];
    self.dropletTopCover.userInteractionEnabled = NO;
    self.dropletTopCover.hidden = YES;
    [self.headerContainer addSubview:self.dropletTopCover];

    // Lottie 遮罩本体：只在 progress>0.03 时挂到 headerContainer.maskView。
    self.dropletMask = [[IMTelegramAvatarMaskView alloc] initWithFrame:CGRectZero];
    self.dropletMask.userInteractionEnabled = NO;

    self.nameOnImage = [self makeNameLabel:22 color:UIColor.whiteColor shadow:YES];
    self.nameOnImage.textAlignment = NSTextAlignmentLeft;
    self.subOnImage = [self makeNameLabel:13 color:[UIColor.whiteColor colorWithAlphaComponent:0.85] shadow:YES];
    self.subOnImage.textAlignment = NSTextAlignmentLeft;
    // 起点比导航栏 title (17pt) 略大，滑动过程会 CGAffineTransformScale 到 ≈17pt，视觉即"移动+缩小到标题栏"。
    // 对齐 Telegram PeerInfoHeaderNode.titleFont ≈ 28pt / titleMinScale=0.6 → 端点 16.8pt。
    self.nameBelow = [self makeNameLabel:26 color:IMTheme.textPrimary shadow:NO];
    self.subBelow = [self makeNameLabel:15 color:IMTheme.textSecondary shadow:NO];
    for (UILabel *l in @[self.nameOnImage, self.subOnImage, self.nameBelow, self.subBelow]) { [self.view addSubview:l]; }
    self.nameOnImage.text = name; self.nameBelow.text = name;
    self.subOnImage.text = self.displaySubtitle; self.subBelow.text = self.displaySubtitle;

    self.liquidNavigationBar = [[IMLiquidNavigationBar alloc] initWithTitle:name
                                                                     subtitle:self.displaySubtitle
                                                                  actionTitle:(self.isGroup ? @"编辑" : nil)];
    self.liquidNavigationBar.delegate = self;
    self.liquidNavigationBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.liquidNavigationBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.liquidNavigationBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.liquidNavigationBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.liquidNavigationBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.liquidNavigationBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:kIMLiquidBarHeight],
    ]];
    // 吸顶条：页签滚到折叠顶栏下方时出现，只托镜像分段控件——**本身保持透明**。
    // ⚠️ 它的 z 序在导航栏【之上】（否则分段药丸顶部会被栏盖掉），所以绝不能给它不透明底：
    // 那会把返回按钮下缘 2pt 一起涂掉（按钮 topInset+6…+50，本条从 topInset+48 起），
    // 表现为"返回按钮被切、左侧出现分割感"（踩过一次）。
    // 内容透出问题改由标题栏自身随头部收拢变实解决，见 applyHeaderMorph。
    self.stickyBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.stickyBar.backgroundColor = UIColor.clearColor;
    self.stickyBar.hidden = YES;
    [self.view addSubview:self.stickyBar];
    self.stickySeg = [[IMLiquidSegmentedControl alloc] initWithFrame:CGRectZero];
    [self.stickySeg addTarget:self action:@selector(stickySegChanged:) forControlEvents:UIControlEventValueChanged];
    [self addTabPinTapTo:self.stickySeg];
    [self.stickyBar addSubview:self.stickySeg];

    // 名字/副标题上移锁定后要充当导航栏 title，必须渲染在液态导航栏与吸顶条【之上】
    //（否则被磨砂背景盖住变虚）。居中文字标签 userInteractionEnabled 默认 NO，不挡两侧按钮点击。
    [self.view bringSubviewToFront:self.nameBelow];
    [self.view bringSubviewToFront:self.subBelow];

    // 共享 Zone① 头部形变驱动：与「我」页 IMSettingsViewController 同一套；改一处两页同步。
    self.headerMorph = [IMDropletHeaderMorph new];
    self.headerMorph.container = self.headerContainer;
    self.headerMorph.avatar = self.avatarView;
    self.headerMorph.bottomCover = self.dropletBottomCover;
    self.headerMorph.topCover = self.dropletTopCover;
    self.headerMorph.mask = self.dropletMask;
    self.headerMorph.name = self.nameBelow;
    self.headerMorph.meta = self.subBelow;
    self.headerMorph.bar = self.liquidNavigationBar;
    self.headerMorph.nameRestFont = 26;
    self.headerMorph.metaRestFont = 15;
    self.headerMorph.collapseOffset = [self headerCollapseOffset];
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
    if (self.isGroup) {
        NSString *remark = [self currentConvRemark]; // 群备注（仅本人可见，G1）优先
        if (remark.length) { return remark; }
        return self.group.name.length ? self.group.name : (self.groupName.length ? self.groupName : @"群聊");
    }
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

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self applyHeaderMorph];
    [self updatePillsVisibility];
    [self updateStickyTabs];
}

/// tab 贴顶时顶边。贴到标题栏底(topInset+56)之上一点，让分段控件紧贴标题栏、上方内容被磨砂栏遮住不外露。
/// stickyBar / pinOffset / updateStickyTabs 统一取此值。
- (CGFloat)tabPinTop { return self.topInset + 48; }
/// 运行时实时的页签栏高度（tab 高度改了这里自动跟随），用于 Zone② detent 的半-tab 临界。
- (CGFloat)tabBarHeight {
    NSInteger sec = [self indexOfSection:IMDetailSectionTabs];
    if (sec == NSNotFound) { return kTabBarH; }
    CGFloat h = [self.tableView rectForHeaderInSection:sec].size.height;
    return h > 0 ? h : kTabBarH;
}

/// 松手临界吸附：Zone①(头部收拢) + Zone②(tab 贴顶后列表起步 detent)。
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity
                    targetContentOffset:(inout CGPoint *)targetContentOffset {
    CGFloat off = scrollView.contentOffset.y;
    CGFloat H = [self headerCollapseOffset];
    // Zone①：仅当【惯性落点】也落在 (0,H) 收拢带内才吸附（否则快速甩动的动量应穿过 H 直达列表，不被卡住）。
    if (off < H && targetContentOffset->y < H) {
        CGFloat snap = [IMDropletHeaderMorph snapTargetForOffset:off velocity:velocity.y collapseOffset:H];
        if (snap >= 0) { targetContentOffset->y = snap; return; }
    }
    // Zone②：tab 贴顶后，列表在 tab 正下方(off=pin)起步上滑。落点在 (pin, pin+半tab) 内 → 回弹到 pin
    //（撤销这段滑动，tab 仍贴顶）；≥ 半tab → 放行自然滚动。
    CGFloat pin = [self pinOffset];
    if (pin <= 0) { return; }
    CGFloat half = [self tabBarHeight] / 2;
    CGFloat t = targetContentOffset->y;
    if (t > pin && t < pin + half) { targetContentOffset->y = pin; }
}

/// 头部完全收拢（态H）所需上滑距离：此时 name/成员进标题栏、pills 恰好停到标题栏下方。
/// 由 pills 几何推导：pills rest 顶 = topInset+208，停靠目标顶 = topInset+64 → H = 144（保持两者同步）。
- (CGFloat)headerCollapseOffset { return 144; }

- (void)applyHeaderMorph {
    CGFloat W = self.view.bounds.size.width;
    if (W <= 0) { return; }
    CGFloat off = MAX(0, self.tableView.contentOffset.y); // 下拉橡皮筋不参与形变
    // Zone① 全部形变（头像吸附 + 遮罩/覆盖 + name/成员迁移进标题栏）交给共享驱动，与「我」页同一套。
    self.headerMorph.topInset = self.topInset;
    self.headerMorph.collapseOffset = [self headerCollapseOffset];
    [self.headerMorph applyForOffset:off width:W];
    // 标题栏随头部收拢同步「变实」：收拢到位＝群名/成员数已迁入标题栏，此时其下正开始穿过
    // 「消息免打扰」等卡片内容；通透磨砂挡不住会透出，故此刻让底色推到不透明。
    // 与 name/成员的迁移用**同一个进度**，观感天然同步；且只作用于本页这条自持栏，不影响其他页面。
    CGFloat collapse = IMClamp(off / MAX(1, [self headerCollapseOffset]), 0, 1);
    self.liquidNavigationBar.opaqueProgress = collapse * kNavOpaqueOnCollapse;
    // 图上名（photo 模式）本页不用，恒隐。
    self.nameOnImage.alpha = 0;
    self.subOnImage.alpha = 0;
    CGFloat q = IMClamp(off / 120.0, 0, 1);
    [self fireHapticsForPhase:q hasPhoto:NO phaseP:1];
}

/// 操作排（搜索/更多）：不再淡出。随内容上滑停靠到标题栏正下方并【始终可见】(态H)；
/// 继续上滑(Zone②)时它自然滚到磨砂标题栏之后被遮挡（= 滚走），无需 alpha 淡出。
- (void)updatePillsVisibility {
    if (!self.pillsView.superview) { return; }
    CGRect frameInView = [self.pillsView.superview convertRect:self.pillsView.frame toView:self.view];
    CGFloat topInView = CGRectGetMinY(frameInView);
    self.pillsView.alpha = 1;
    // 进入标题栏区(被磨砂栏遮挡)后停用点击，避免隔着导航栏误触搜索/更多。
    self.pillsView.userInteractionEnabled = topInView > self.topInset + kIMLiquidBarHeight;
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
        BOOL wasFriend = self.peerIsFriend;
        BOOL isFriend = NO;
        for (IMUserCard *c in friends) {
            if ([c.userID isEqualToString:self.peerID]) {
                self.peerBlocked = c.blocked;
                isFriend = (c.status == IMFriendStatusAccepted); // 拉黑的好友 status 仍 accepted，故仍算好友
                break;
            }
        }
        self.peerIsFriend = isFriend;
        [self.tableView reloadData]; // 刷新「更多」菜单的 拉黑/取消拉黑 文案 + actions cell 操作排
        if (wasFriend != isFriend) { [self rebuildPillsView]; } // 好友态变化 → 重建 header 悬浮操作排
    }];
}

/// 群模式：拉取我的 accepted 好友 uid 集合，供成员长按菜单区分「发送消息」/「添加好友」。
- (void)loadFriendUIDs {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService friendsWithToken:token status:nil completion:^(NSArray<IMUserCard *> *friends, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error) { return; }
        NSMutableSet<NSString *> *uids = [NSMutableSet set];
        for (IMUserCard *c in friends) {
            if (c.status == IMFriendStatusAccepted && c.userID.length) { [uids addObject:c.userID]; }
        }
        self.friendUIDs = uids;
        // 无需 reloadData：菜单在长按时惰性构建，届时读取最新 friendUIDs 即可。
    }];
}

/// 我是否已是该 uid 的好友（friendUIDs 尚未加载完成时返回 NO，长按菜单默认给「添加好友」入口）。
- (BOOL)isFriendUID:(NSString *)uid {
    return uid.length > 0 && [self.friendUIDs containsObject:uid];
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

/// 任务2：某条消息被物理移除（为所有人删除 / 仅为我删除）→ 本会话则重建页签（文件列表去掉该行）。
- (void)onMessageRemoved:(NSNotification *)note {
    if (![note.userInfo[kIMConvIDKey] isEqualToString:self.convID]) { return; }
    [self rebuildTabs];
    [self.tableView reloadData];
}

#pragma mark - 页签

- (void)rebuildTabs {
    __block NSArray<IMMessageModel *> *msgs = @[];
    [self performDatabaseOperation:^(IMDatabase *database) {
        msgs = [database messagesForConv:self.convID];
    }];
    self.tabs = [IMChatDetailTabs tabsForMessages:msgs isGroup:self.isGroup];
    if (self.selectedTab >= (NSInteger)self.tabs.count) { self.selectedTab = 0; }
    // 分段控件
    if (!self.segmented) {
        self.segmented = [[IMLiquidSegmentedControl alloc] initWithFrame:CGRectZero];
        [self.segmented addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        [self addTabPinTapTo:self.segmented]; // 单 tab / 重复点当前 tab 也能贴顶
    }
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:self.tabs.count];
    for (IMChatDetailTab *t in self.tabs) { [titles addObject:t.title ?: @""]; }
    self.segmented.titles = titles;
    self.stickySeg.titles = titles;
    if (self.tabs.count > 0) {
        self.segmented.selectedIndex = self.selectedTab;
        self.stickySeg.selectedIndex = self.selectedTab;
    }
    [self recomputeTabContent];
}

- (void)segmentChanged:(IMLiquidSegmentedControl *)seg { [self switchToTab:seg.selectedIndex scrollToPin:YES]; }
- (void)stickySegChanged:(IMLiquidSegmentedControl *)seg { [self switchToTab:seg.selectedIndex scrollToPin:YES]; }

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
    return MAX(0, hr.origin.y - [self tabPinTop]);
}
- (BOOL)tabsArePinned { return self.tableView.contentOffset.y >= [self pinOffset] - 1; }

/// 切换页签：**内容瞬时替换、零动画**。已贴顶→保持贴顶（**绝不回露头部再滑回**，这是之前"先滑到顶再滑回"的根因）；
/// 未贴顶且需要贴顶→平滑滚过去。
- (void)switchToTab:(NSInteger)index scrollToPin:(BOOL)scrollToPin {
    if (index < 0 || index >= (NSInteger)self.tabs.count) { return; }
    if (index == self.selectedTab) { if (scrollToPin && ![self tabsArePinned]) { [self scrollTabsToPinAnimated:YES]; } return; }
    BOOL wasPinned = [self tabsArePinned];
    self.selectedTab = index;
    [self.segmented setSelectedIndex:index animated:YES];
    [self.stickySeg setSelectedIndex:index animated:YES];
    [self recomputeTabContent];
    if ([self indexOfSection:IMDetailSectionTabs] == NSNotFound) { return; }
    [UIView performWithoutAnimation:^{
        [self.tableView reloadData];       // 整表零动画重建：内容瞬时替换，无逐行高度动画
        [self.tableView layoutIfNeeded];
        [self syncScrollInset];            // 始终补足 inset → pin 可达（估算已关，pinOffset 立即准确）
        if (wasPinned) {                   // #4 已贴顶：直接钉在贴顶位（不露头部、不回进入态）
            self.tableView.contentOffset = CGPointMake(0, [self pinOffset]);
        }
    }];
    if (wasPinned) {
        // 安全网：reloadData 后布局在下一帧可能再次结算，届时强制断言一次贴顶位，抵消偶发落偏。
        __weak typeof(self) ws = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self || [self indexOfSection:IMDetailSectionTabs] == NSNotFound) { return; }
            [self syncScrollInset];
            self.tableView.contentOffset = CGPointMake(0, [self pinOffset]);
        });
    } else if (scrollToPin) {              // 之前在头部区、点了 tab：平滑滚到贴顶（#2(2) 点 tab 即贴顶）
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
    BOOL pinned = headerTopInView <= [self tabPinTop] + 0.5;
    self.stickyBar.hidden = !pinned;
    // 贴顶后隐藏表内真分段——吸顶条透明，真 header 上移时会从其后透出，与镜像分段并存（两个 tab 栏）。
    self.segmented.hidden = pinned;
    if (pinned && self.stickySeg.selectedIndex != self.selectedTab) {
        self.stickySeg.selectedIndex = self.selectedTab;
    }
}

/// 依当前选中页签，预备内容数组（媒体项 / 文件·语音·链接消息）。
- (void)recomputeTabContent {
    self.tabMedia = @[]; self.tabMediaMessages = @[]; self.tabRows = @[];
    if (self.tabs.count == 0) { return; }
    IMChatDetailTab *t = self.tabs[self.selectedTab];
    if (t.kind == IMDetailTabKindMembers) { return; }
    __block NSArray<IMMessageModel *> *msgs = @[];
    [self performDatabaseOperation:^(IMDatabase *database) {
        msgs = [database messagesForConv:self.convID];
    }];
    if (t.kind == IMDetailTabKindMedia) {
        NSMutableArray<IMMessageModel *> *media = [NSMutableArray array];
        for (IMMessageModel *m in msgs) {
            if ([IMChatDetailTabs message:m matchesKind:IMDetailTabKindMedia]) { [media addObject:m]; }
        }
        // 新→旧。**先排消息再派生 item**，保证 tabMedia 与 tabMediaMessages 逐位对齐
        //（宫格要按 index 反查消息取下载态/thumb）。
        NSArray<IMMessageModel *> *sorted = [media sortedArrayUsingComparator:^NSComparisonResult(IMMessageModel *a, IMMessageModel *b) {
            return a.timestamp > b.timestamp ? NSOrderedAscending : (a.timestamp < b.timestamp ? NSOrderedDescending : NSOrderedSame);
        }];
        NSMutableArray<IMMediaItem *> *items = [NSMutableArray arrayWithCapacity:sorted.count];
        for (IMMessageModel *m in sorted) {
            [items addObject:[IMMediaItem itemWithURL:IMMediaFullURL(m.content, self.host)
                                              isVideo:[m.contentType isEqualToString:@"video"]
                                            timestamp:m.timestamp
                                                thumb:m.thumb]];
        }
        self.tabMediaMessages = sorted;
        self.tabMedia = items;
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
    // 非好友（单聊）：只保留头像 + 操作排（加好友/更多），隐藏备注名·设置·页签三张卡——
    // 尚未建立关系时这些设置无意义。仅隐藏，数据加载逻辑不动（加为好友后 reloadData 即恢复）。
    if (!self.isGroup && !self.peerIsFriend) { return s; }
    if (!self.isGroup) { [s addObject:@(IMDetailSectionInfo)]; } // 单聊：备注名/用户名
    if (self.isGroup && [self aboutRowKinds].count > 0) { [s addObject:@(IMDetailSectionAbout)]; } // 公告/简介卡（Pills 下）
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
        case IMDetailSectionAbout:    return (NSInteger)[self aboutRowKinds].count;
        case IMDetailSectionSettings: return (NSInteger)[self settingsRowKinds].count;
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
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, kTabBarH)];
    [self layoutSegmented:self.segmented inWidth:tableView.bounds.size.width];
    [wrap addSubview:self.segmented];
    return wrap;
}

/// 分段控件按内容宽居中（贴顶条与表内一致，单/多 tab 段宽固定）。段高 kTabSegH、下限加宽 → 点击面积更大。
- (void)layoutSegmented:(IMLiquidSegmentedControl *)seg inWidth:(CGFloat)width {
    CGFloat w = [seg sizeThatFits:CGSizeMake(width - 32, kTabSegH)].width;
    // 多 tab 下限 200（大点击面积）；**单 tab 收窄到 1/3（~67）**——单个页签无需铺那么宽，居中更紧凑。
    CGFloat minW = self.tabs.count <= 1 ? 200.0 / 3.0 : 200;
    w = IMClamp(w, minW, width - 32);
    seg.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    seg.frame = CGRectMake((width - w) / 2, (kTabBarH - kTabSegH) / 2, w, kTabSegH);
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    IMDetailSection kind = [self sectionKindAt:section];
    if (kind == IMDetailSectionTabs) { return kTabBarH; }
    if (kind == IMDetailSectionPills) { return 8; }
    return 12;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMDetailSection kind = [self sectionKindAt:indexPath.section];
    if (kind == IMDetailSectionPills) { return kPillsRowH; }
    if (kind == IMDetailSectionAbout) { return 64; } // 标题 + 一行预览（subtitle 样式）
    if (kind == IMDetailSectionTabs && self.tabs.count > 0) {
        IMChatDetailTab *t = self.tabs[self.selectedTab];
        if (t.kind == IMDetailTabKindMembers) { return 60; }
        if (t.kind == IMDetailTabKindMedia) {
            // 宽度必须与宫格排布用的**真实** cell 内容宽一致，否则行高多出几 pt → 卡片底部白边。
            // 真实宽由 cell 首次布局回调上报（见 mediaGridWidth）；未知时先用估算值兜底。
            CGFloat w = self.mediaGridWidth > 0 ? self.mediaGridWidth : tableView.bounds.size.width - 32;
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
        case IMDetailSectionAbout:    return [self aboutCell:tableView row:indexPath.row];
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
    // 操作排按入口定制（去「静音」——下面有免打扰开关，重复）：与 header 悬浮 pills 共用规格。
    NSArray<NSDictionary *> *specs = [self actionPillSpecs];
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectInset(cell.contentView.bounds, 0, 6)];
    stack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    stack.axis = UILayoutConstraintAxisHorizontal; stack.distribution = UIStackViewDistributionFillEqually; stack.spacing = 9;
    for (NSDictionary *spec in specs) {
        // 与 header 悬浮 pills 共用同一构造（含 iOS 26 玻璃前景单色化的 accent 兜底）。
        // 「更多」在 helper 内部即挂到 moreTapped:，交给 IMPopoverCard 的 UIKit sheet/popover（iOS 26 自动 Liquid Glass）。
        [stack addArrangedSubview:[self actionPillButtonForSpec:spec]];
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

#pragma mark - 公告 / 简介卡（全员只读，G1 修）

/// 群公告/简介卡的行类型（顺序即展示顺序）。
typedef NS_ENUM(NSInteger, IMDetailAboutRow) {
    IMDetailAboutRowAnnouncement = 0, ///< 群公告（非空才显）
    IMDetailAboutRowIntro,            ///< 群简介（非空才显）
};

/// 组装公告/简介卡当前应显示的行——公告/简介**非空才显**，都空则整卡不显（sectionLayout 里据 count 决定）。
- (NSArray<NSNumber *> *)aboutRowKinds {
    NSMutableArray<NSNumber *> *rows = [NSMutableArray array];
    if (!self.isGroup) { return rows; }
    if (self.group.announcement.length > 0) { [rows addObject:@(IMDetailAboutRowAnnouncement)]; }
    if (self.group.intro.length > 0) { [rows addObject:@(IMDetailAboutRowIntro)]; }
    return rows;
}

/// 折行/连续空白压成单行预览（详情页卡与横幅一致）。
- (NSString *)aboutSingleLinePreview:(NSString *)text {
    NSArray<NSString *> *parts = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *part in parts) { if (part.length > 0) { [kept addObject:part]; } }
    return [kept componentsJoinedByString:@" "];
}

- (UITableViewCell *)aboutCell:(UITableView *)tv row:(NSInteger)row {
    NSArray<NSNumber *> *kinds = [self aboutRowKinds];
    IMDetailAboutRow kind = (row < (NSInteger)kinds.count) ? (IMDetailAboutRow)kinds[row].integerValue : IMDetailAboutRowAnnouncement;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.textColor = IMTheme.textPrimary;
    cell.detailTextLabel.textColor = IMTheme.textSecondary;
    cell.detailTextLabel.numberOfLines = 1;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.imageView.tintColor = IMTheme.accent;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (kind == IMDetailAboutRowAnnouncement) {
        cell.imageView.image = [UIImage systemImageNamed:@"megaphone"];
        cell.textLabel.text = @"群公告";
        cell.detailTextLabel.text = [self aboutSingleLinePreview:self.group.announcement];
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"info.circle"];
        cell.textLabel.text = @"群简介";
        cell.detailTextLabel.text = [self aboutSingleLinePreview:self.group.intro];
    }
    return cell;
}

/// 设置区行类型（顺序即展示顺序）。群聊比单聊多「我在本群的昵称/群备注」，管理员再多「群管理」。
typedef NS_ENUM(NSInteger, IMDetailSettingsRow) {
    IMDetailSettingsRowPin = 0,     ///< 置顶聊天
    IMDetailSettingsRowMute,        ///< 消息免打扰
    IMDetailSettingsRowMyNickname,  ///< 我在本群的昵称（群聊，任意成员，G1）
    IMDetailSettingsRowRemark,      ///< 群备注（群聊，仅本人可见，G1）
    IMDetailSettingsRowGroupQR,     ///< 群二维码（群聊，任意成员，QRCODE P0）
    IMDetailSettingsRowManage,      ///< 群管理（群主/管理员）
};

/// 组装设置区当前应显示的行（避免硬编码 0/1/2 造成群/单聊分叉 bug）。
- (NSArray<NSNumber *> *)settingsRowKinds {
    NSMutableArray<NSNumber *> *rows = [NSMutableArray arrayWithObjects:@(IMDetailSettingsRowPin), @(IMDetailSettingsRowMute), nil];
    if (self.isGroup) {
        [rows addObject:@(IMDetailSettingsRowMyNickname)]; // 任意成员可改自己的群昵称
        [rows addObject:@(IMDetailSettingsRowRemark)];     // 群备注（仅本人可见）
        [rows addObject:@(IMDetailSettingsRowGroupQR)];    // 群二维码（任意成员可出示；perm_invite=1 时服务端拦普通成员）
        if ([self canManageGroup]) { [rows addObject:@(IMDetailSettingsRowManage)]; }
    }
    return rows;
}

- (UITableViewCell *)settingsCell:(UITableView *)tv row:(NSInteger)row {
    NSArray<NSNumber *> *kinds = [self settingsRowKinds];
    IMDetailSettingsRow kind = (row < (NSInteger)kinds.count) ? (IMDetailSettingsRow)kinds[row].integerValue : IMDetailSettingsRowPin;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.textColor = IMTheme.textPrimary;
    cell.detailTextLabel.textColor = IMTheme.textSecondary;
    switch (kind) {
        case IMDetailSettingsRowPin: {
            cell.textLabel.text = @"置顶聊天";
            UISwitch *sw = [UISwitch new]; sw.on = self.pinnedAt > 0; sw.tag = 1;
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            break;
        }
        case IMDetailSettingsRowMute: {
            cell.textLabel.text = @"消息免打扰";
            UISwitch *sw = [UISwitch new]; sw.on = self.muted; sw.tag = 2;
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            break;
        }
        case IMDetailSettingsRowMyNickname:
            cell.textLabel.text = @"我在本群的昵称";
            cell.detailTextLabel.text = self.group.myNickname.length ? self.group.myNickname : @"未设置";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case IMDetailSettingsRowRemark:
            cell.textLabel.text = @"群备注";
            cell.detailTextLabel.text = [self currentConvRemark].length ? [self currentConvRemark] : @"未设置";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case IMDetailSettingsRowGroupQR:
            cell.textLabel.text = @"群二维码";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case IMDetailSettingsRowManage:
            cell.textLabel.text = @"群管理";
            // 有待审入群申请时把红点带到「群管理」行（不必进管理页才发现，G3 修）。
            if (self.group.pendingCount > 0) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 待审", (long)self.group.pendingCount];
                cell.detailTextLabel.textColor = IMTheme.danger;
            } else {
                cell.detailTextLabel.text = @"仅群主/管理员";
            }
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
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
        // 逐格门控（M4-7）：必须在 setItems: 前挂好——reloadData 会立刻回调查询每格状态。
        cell.stateForItemIndex = ^IMDownloadProgress *(NSInteger i) {
            IMMessageModel *mm = [ws mediaMessageAtIndex:i];
            return mm ? [ws.downloads stateForMessage:mm] : nil;
        };
        cell.thumbForItemIndex = ^NSString *(NSInteger i) { return [ws mediaMessageAtIndex:i].thumb; };
        cell.onDownloadItemIndex = ^(NSInteger i) {
            IMMessageModel *mm = [ws mediaMessageAtIndex:i];
            if (mm) { [ws.downloads handleTapForMessage:mm]; }
        };
        // 任务2：媒体宫格逐格长按菜单（转发/定位/取消下载/删除两档）——与文件行同一套。
        cell.contextMenuForItemIndex = ^UIContextMenuConfiguration *(NSInteger i) {
            IMMessageModel *mm = [ws mediaMessageAtIndex:i];
            return mm ? [ws contentMenuConfigForMessage:mm] : nil;
        };
        // 真实内容宽上报：与估算值不符时记下并只重算行高（beginUpdates/endUpdates 不重建 cell，无闪烁）。
        // 宽度只在首次布局/旋转时变一次，收敛后不再触发，无循环。
        cell.onContentWidthChanged = ^(CGFloat width) {
            __strong typeof(ws) self = ws;
            if (!self || ABS(self.mediaGridWidth - width) < 0.5) { return; }
            self.mediaGridWidth = width;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView beginUpdates];
                [self.tableView endUpdates];
            });
        };
        self.mediaContainerCell = cell;
        [cell setItems:self.tabMedia];
        return cell;
    }
    // 文件/语音/链接
    if (self.tabRows.count == 0) {
        NSString *empty = t.kind == IMDetailTabKindFiles ? @"暂无文件" : (t.kind == IMDetailTabKindVoice ? @"暂无语音" : @"暂无链接");
        return [self emptyCell:tv text:empty];
    }
    IMMessageModel *m = self.tabRows[row];
    // 文件行：三态专用 cell（未下载 ↓ / 下载中 环形+⏸ / 已下载 类型图标）。无右侧配件——
    // 点行=下载/暂停/继续/打开；取消下载走长按菜单（仅进行中文件才有该项）。草图 §04。
    if (t.kind == IMDetailTabKindFiles) {
        IMDetailFileCell *fc = [tv dequeueReusableCellWithIdentifier:@"detailfile"];
        [fc configureWithMessage:m download:[self.downloads stateForMessage:m]];
        return fc;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.detailTextLabel.textColor = IMTheme.textSecondary;
    if (t.kind == IMDetailTabKindVoice) {
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
    if (kind == IMDetailSectionAbout) {
        NSArray<NSNumber *> *kinds = [self aboutRowKinds];
        if (indexPath.row >= (NSInteger)kinds.count) { return; }
        if ((IMDetailAboutRow)kinds[indexPath.row].integerValue == IMDetailAboutRowAnnouncement) {
            [IMGroupTextViewController presentFrom:self title:@"群公告"
                                          subtitle:[IMGroupTextViewController announceSubtitleForMillis:self.group.announcementAt]
                                              body:self.group.announcement];
        } else {
            [IMGroupTextViewController presentFrom:self title:@"群简介" subtitle:nil body:self.group.intro];
        }
        return;
    }
    if (kind == IMDetailSectionSettings) {
        NSArray<NSNumber *> *kinds = [self settingsRowKinds];
        if (indexPath.row >= (NSInteger)kinds.count) { return; }
        switch ((IMDetailSettingsRow)kinds[indexPath.row].integerValue) {
            case IMDetailSettingsRowMyNickname: [self editMyGroupNickname]; break;
            case IMDetailSettingsRowRemark:     [self editGroupRemark]; break;
            case IMDetailSettingsRowGroupQR:    [self openGroupQR]; break;
            case IMDetailSettingsRowManage:     [self openGroupManage]; break;
            default: break; // 置顶/免打扰走开关，不响应行点击
        }
        return;
    }
    if (kind == IMDetailSectionTabs && self.tabs.count > 0) {
        IMChatDetailTab *t = self.tabs[self.selectedTab];
        if (t.kind == IMDetailTabKindMembers) {
            if (indexPath.row == 0) { [self inviteMembers]; }
            else { [self openPeerDetail:self.group.members[indexPath.row - 1]]; } // tap→对方资料页
        } else if (t.kind == IMDetailTabKindFiles) {
            if (indexPath.row >= (NSInteger)self.tabRows.count) { return; }
            IMMessageModel *m = self.tabRows[indexPath.row];
            // 自己发的文件：原件从不进下载缓存（isOutOfScope），stateForMessage 恒为 nil，
            // 若走 openCachedFile 会因本地无缓存静默无反应（.mov 等一律打不开）。与聊天页一致，改走远端 URL 打开。
            if ([m.from isEqualToString:self.userID]) {
                [self openLink:IMMediaFullURL(m.content, self.host)];
                return;
            }
            IMDownloadProgress *dp = [self.downloads stateForMessage:m];
            // 未下载/失败 → 就地下载（不跳页）；下载中 ↔ 暂停/继续；已下载 → 本地 QuickLook 打开（用户主动点）。
            if (dp) { [self.downloads handleTapForMessage:m]; }
            else { [self openCachedFileForMessage:m]; }
        } else if (t.kind == IMDetailTabKindLinks) {
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
    // 内容行长按（任务2）：文件/语音/链接三类逐行页签统一走同一套菜单（转发/定位/[取消下载]/删除）。
    // 媒体宫格逐格菜单在容器 cell 的 collectionView contextMenu 委托里；成员行走下方成员菜单。
    IMMessageModel *rowMsg = [self contentRowMessageAtIndexPath:indexPath];
    if (rowMsg) { return [self contentMenuConfigForMessage:rowMsg]; }
    IMGroupMember *m = [self memberAtIndexPath:indexPath];
    if (!m || [m.userID isEqualToString:self.userID]) { return nil; }
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *sug) {
        NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
        // 好友准入（微信式，任务一 P0）：好友 → 「发送消息」；非好友 → 「添加好友」（非好友发消息会被 200103 拒收）。
        if ([ws isFriendUID:m.userID]) {
            [items addObject:[UIAction actionWithTitle:@"发送消息" image:[UIImage systemImageNamed:@"bubble.right"]
                                            identifier:nil handler:^(UIAction *a) { [ws openChatWithMember:m]; }]];
        } else {
            [items addObject:[UIAction actionWithTitle:@"添加好友" image:[UIImage systemImageNamed:@"person.badge.plus"]
                                            identifier:nil handler:^(UIAction *a) { [ws requestAddFriendUID:m.userID]; }]];
        }
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
    else if ([a isEqualToString:@"addfriend"]) { [self requestAddPeerFriend]; }
}

/// 单聊「加好友」：向对端发好友申请（微信式，任务一 P0）。
- (void)requestAddPeerFriend { [self requestAddFriendUID:self.peerID]; }

/// 向指定 uid 发好友申请（单聊 pill 与群成员菜单共用）。
/// 两种结果分别对待：
///  - **已直接成为好友**（对方仍视我为好友，典型于我曾单向删除对方后加回）：**不吐司**——
///    说「已发送好友申请」会让用户误以为还要等对方通过；直接刷新界面（操作排/卡片立即恢复）即可。
///  - 已发出申请（待对方同意）：吐司告知，界面暂不变（仍是 requested 非 accepted）。
- (void)requestAddFriendUID:(NSString *)uid {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0 || uid.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService requestFriendWithToken:token peerID:uid
                                             completion:^(BOOL becameFriend, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) { [self im_showToast:error.localizedDescription ?: @"好友申请发送失败"]; return; }
        // 重拉关系：单聊校正 peerIsFriend 并重建操作排/卡片；群聊刷新成员菜单依据。
        // 两种结果都要刷——即使只是发出申请，我侧也已从「无关系」变 requested。
        if (self.isGroup) { [self loadFriendUIDs]; } else { [self loadPeerBlockState]; }
        if (!becameFriend) { [self im_showToast:@"已发送好友申请"]; }
    }];
}

/// 与某人开始/回到单聊（操作排「消息」）。
- (void)openChatWithPeerID:(NSString *)peerID nickname:(NSString *)nickname avatarURL:(NSString *)avatarURL {
    if (peerID.length == 0 || [peerID isEqualToString:self.userID]) { return; }
    IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:self.host userID:self.userID
                                                                    peerID:peerID readSeq:0 unread:0 peerReadSeq:0];
    chat.peerNickname = nickname; chat.peerAvatarURL = avatarURL;
    [self.navigationController pushViewController:chat animated:YES];
}

/// 「更多」Telegram 式锚点菜单：清空记录=普通色；退出/删除群/拉黑=红。
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
        if (![self performDatabaseOperation:^(IMDatabase *database) {
            [database clearMessagesForConv:self.convID];
        }]) { return; }
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

#pragma mark - 群昵称 / 群备注（G1）

/// 群备注本地键（仅本人可见；沿用单聊备注的本地存储范式，keyed by convID）。
/// 说明：后端已有会话级 remark 字段（随 conv_update 多端同步），iOS 现用本地存储，多端同步为后续项。
- (NSString *)groupRemarkKey { return [NSString stringWithFormat:@"im_grpremark_%@_%@", self.userID, self.convID]; }
- (NSString *)currentConvRemark {
    return [NSUserDefaults.standardUserDefaults stringForKey:[self groupRemarkKey]] ?: @"";
}

/// 我在本群的昵称（G1，任意成员）：走后端 → 成功后刷新群资料（气泡回退名随之更新）。
- (void)editMyGroupNickname {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"我在本群的昵称"
        message:@"群内所有人可见，最多 20 字；留空恢复默认昵称。" preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = self.group.myNickname ?: @"";
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; }];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = [alert.textFields.firstObject.text
                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if ([v isEqualToString:current]) { return; }
        NSString *token = IMHTTPService.sharedService.currentToken;
        if (token.length == 0) { [ws im_showToast:@"未登录"]; return; }
        [IMHTTPService.sharedService setGroupMyNicknameWithToken:token convID:ws.convID nickname:v
                                                     completion:^(NSError *error) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (error) { [self im_showToast:error.localizedDescription ?: @"保存失败"]; return; }
            self.group.myNickname = v.length ? v : nil;
            [self loadGroupInfo]; // 成员表 group_nickname 变了，重拉刷新
            [self im_showToast:@"已更新"];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 群备注（G1，仅本人可见）：改我看到的群名，本地存储。
- (void)editGroupRemark {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"群备注"
        message:@"仅自己可见，将替代群名显示。" preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = [self currentConvRemark];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; tf.placeholder = self.group.name; }];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = [alert.textFields.firstObject.text
                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (v.length) { [NSUserDefaults.standardUserDefaults setObject:v forKey:[self groupRemarkKey]]; }
        else { [NSUserDefaults.standardUserDefaults removeObjectForKey:[self groupRemarkKey]]; }
        [self refreshHeaderTexts];
        [self.tableView reloadData];
        [self im_showToast:@"备注已更新"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

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
            if (error) {
                // 300207 = 被邀请者已被移出/冷却期：用邀请场景第三人称文案（区别于自加群映射的第二人称）。
                if (error.code == 300207) { [self im_showToast:@"该成员已被移出本群，暂时无法再次邀请"]; }
                else { [self im_showToast:error.localizedDescription]; }
                return;
            }
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

/// 群二维码（QRCODE P0，任意成员可出示；perm_invite=1 时仅群主/管理员可出码——码即邀请链接）。
/// 无权限时不进入卡片页，直接中文吐司（对齐 Web：Web 亦不打开模态、只吐司）。
- (void)openGroupQR {
    if (self.group.permInvite && ![self canManageGroup]) {
        [self im_showToast:@"群主已开启「仅管理员可邀请」，你无法出示群二维码"];
        return;
    }
    IMQRCardViewController *vc = [[IMQRCardViewController alloc] initGroupCardWithHost:self.host userID:self.userID
                                                                              convID:self.convID groupName:self.group.name
                                                                           avatarURL:self.group.avatarURL
                                                                         memberCount:self.group.memberCount
                                                                            canReset:[self canManageGroup]];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 打开媒体 / 链接 / 返回

#pragma mark - 媒体 / 文件 Tab 的下载（M4-7，草图 §04）

/// 与聊天页共用同一套编排：同一份文件在两处**共享一个下载态与进度**（key 都是 content）。
- (IMMediaDownloadCoordinator *)downloads {
    if (!_downloads) {
        _downloads = [[IMMediaDownloadCoordinator alloc] initWithHost:self.host
                                                             myUserID:self.userID
                                                              isGroup:self.isGroup];
        _downloads.autoPrefetchEnabled = NO; // 浏览历史媒体不该顺手把几十条视频拉下来；这里只反映状态
        __weak typeof(self) ws = self;
        // 高频进度 → 就地更新（宫格只刷那一格 cell、文件行只改 cell）；绝不 reload（否则内嵌 CollectionView 卡死）。
        _downloads.onProgress = ^(IMMessageModel *m, IMDownloadProgress *state) { [ws updateDownloadCellForMessage:m state:state]; };
        // 低频（下载完成）→ reload 让 cell 重配（媒体格重拉清晰图 / 文件行回类型图标 + ⋯）。
        _downloads.onStateChanged = ^(IMMessageModel *m) { [ws refreshDownloadRowForMessage:m]; };
    }
    return _downloads;
}

- (nullable IMMessageModel *)mediaMessageAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabMediaMessages.count) { return nil; }
    return self.tabMediaMessages[index];
}

/// 进度**就地更新**（不 reload）：媒体页刷那一格、文件页刷那一行的可见 cell。
- (void)updateDownloadCellForMessage:(IMMessageModel *)m state:(IMDownloadProgress *)state {
    if (self.tabs.count == 0) { return; }
    IMChatDetailTab *t = self.tabs[self.selectedTab];
    if (t.kind == IMDetailTabKindMedia) {
        NSUInteger i = [self.tabMediaMessages indexOfObjectIdenticalTo:m];
        if (i != NSNotFound) { [self.mediaContainerCell updateItemAtIndex:(NSInteger)i download:state]; }
        return;
    }
    if (t.kind != IMDetailTabKindFiles) { return; }
    NSInteger section = [self indexOfSection:IMDetailSectionTabs];
    if (section == NSNotFound) { return; }
    NSUInteger row = [self.tabRows indexOfObjectIdenticalTo:m];
    if (row == NSNotFound || (NSInteger)row >= [self.tableView numberOfRowsInSection:section]) { return; }
    IMDetailFileCell *cell = (IMDetailFileCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:section]];
    if ([cell isKindOfClass:IMDetailFileCell.class]) { [cell updateDownload:state]; }
}

/// 定点刷新：媒体页只刷那一格（内嵌 CollectionView 整行重建代价高），文件页刷那一行。
- (void)refreshDownloadRowForMessage:(IMMessageModel *)m {
    if (self.tabs.count == 0) { return; }
    IMChatDetailTab *t = self.tabs[self.selectedTab];
    NSInteger section = [self indexOfSection:IMDetailSectionTabs];
    if (section == NSNotFound) { return; }
    if (t.kind == IMDetailTabKindMedia) {
        NSUInteger i = [self.tabMediaMessages indexOfObjectIdenticalTo:m];
        if (i != NSNotFound) { [self.mediaContainerCell refreshItemAtIndex:(NSInteger)i]; }
        return;
    }
    if (t.kind != IMDetailTabKindFiles) { return; }
    NSUInteger row = [self.tabRows indexOfObjectIdenticalTo:m];
    if (row == NSNotFound || (NSInteger)row >= [self.tableView numberOfRowsInSection:section]) { return; }
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)row inSection:section]]
                          withRowAnimation:UITableViewRowAnimationNone];
}

/// 已下载的文件 → 本地 QuickLook 预览（与聊天页一致，绝不自动打开，由用户点触发）。
- (void)openCachedFileForMessage:(IMMessageModel *)m {
    NSURL *local = [self.downloads localFileForMessage:m];
    if (!local) { return; }
    self.quickLookURL = local;
    QLPreviewController *ql = [QLPreviewController new];
    ql.dataSource = self;
    [self presentViewController:ql animated:YES completion:nil];
}

#pragma mark - 文件行长按菜单：转发 / 删除 / 定位到聊天

/// 逐行内容页签（文件/语音/链接，均 tabRows 逐行）某行对应的消息（越界/媒体·成员页返回 nil）。
/// 任务2：这三类页签的长按菜单与文件行一致；媒体走宫格逐格菜单、成员走成员菜单，各不在此。
- (nullable IMMessageModel *)contentRowMessageAtIndexPath:(NSIndexPath *)ip {
    if ([self sectionKindAt:ip.section] != IMDetailSectionTabs || self.tabs.count == 0) { return nil; }
    IMDetailTabKind kind = self.tabs[self.selectedTab].kind;
    if (kind != IMDetailTabKindFiles && kind != IMDetailTabKindVoice && kind != IMDetailTabKindLinks) { return nil; }
    if (ip.row < 0 || ip.row >= (NSInteger)self.tabRows.count) { return nil; }
    return self.tabRows[ip.row];
}

/// 详情内容长按菜单（任务2）：转发 / 定位到聊天 / [取消下载·仅进行中] / 删除（两档 sheet）。
/// **文件·语音·链接行 + 媒体宫格逐格共用**（成员页除外）。仅对真实消息（convSeq>0）给菜单。
- (nullable UIContextMenuConfiguration *)contentMenuConfigForMessage:(IMMessageModel *)m {
    if (!m || m.convSeq <= 0) { return nil; }
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *sug) {
        NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
        [items addObject:[UIAction actionWithTitle:@"转发" image:[UIImage systemImageNamed:@"arrowshape.turn.up.right"]
                                        identifier:nil handler:^(UIAction *a) { [ws forwardFileMessage:m]; }]];
        [items addObject:[UIAction actionWithTitle:@"定位到聊天" image:[UIImage systemImageNamed:@"bubble.left.and.text.bubble.right"]
                                        identifier:nil handler:^(UIAction *a) { [ws locateFileMessageInChat:m]; }]];
        IMDownloadProgress *dp = [ws.downloads stateForMessage:m];
        if (dp.phase == IMDownloadPhaseDownloading || dp.phase == IMDownloadPhasePaused) {
            [items addObject:[UIAction actionWithTitle:@"取消下载" image:[UIImage systemImageNamed:@"xmark.circle"]
                                            identifier:nil handler:^(UIAction *a) { [ws.downloads cancelDownloadForMessage:m]; }]];
        }
        // 删除（任务2，两档，对齐聊天页）：可为所有人删 → 原生子菜单【为所有人删除】+【仅删除自己】（点开有 push 过渡）；
        // 否则「删除」= 仅删除自己。不再用居中 actionSheet。
        if ([ws canDeleteForEveryone:m]) {
            UIAction *selfOnly = [UIAction actionWithTitle:@"仅删除自己" image:[UIImage systemImageNamed:@"trash"]
                                               identifier:nil handler:^(UIAction *a) { [ws hideMessageForSelf:m]; }];
            selfOnly.attributes = UIMenuElementAttributesDestructive;
            UIAction *everyone = [UIAction actionWithTitle:@"为所有人删除" image:[UIImage systemImageNamed:@"trash"]
                                               identifier:nil handler:^(UIAction *a) { [ws deleteMessageForEveryone:m]; }];
            everyone.attributes = UIMenuElementAttributesDestructive;
            // 破坏性重的「为所有人删除」放最后（destructive-last，与本仓菜单约定一致）。
            [items addObject:[UIMenu menuWithTitle:@"删除" image:[UIImage systemImageNamed:@"trash"]
                                        identifier:nil options:0 children:@[selfOnly, everyone]]];
        } else {
            UIAction *del = [UIAction actionWithTitle:@"删除" image:[UIImage systemImageNamed:@"trash"]
                                           identifier:nil handler:^(UIAction *a) { [ws hideMessageForSelf:m]; }];
            del.attributes = UIMenuElementAttributesDestructive;
            [items addObject:del];
        }
        return [UIMenu menuWithTitle:@"" children:items];
    }];
}

/// 导航栈里承载本会话的聊天页（详情页通常从它 push 而来）。转发/定位复用它的现成逻辑。
- (nullable IMChatViewController *)originChatInStack {
    for (UIViewController *vc in self.navigationController.viewControllers) {
        if ([vc isKindOfClass:IMChatViewController.class]
            && [[(IMChatViewController *)vc convID] isEqualToString:self.convID]) {
            return (IMChatViewController *)vc;
        }
    }
    return nil;
}

/// 转发：复用聊天页 IMChatViewController 的转发选择+回声逻辑（present 由本页发起，呈现上下文正确）。
- (void)forwardFileMessage:(IMMessageModel *)m {
    IMChatViewController *chat = [self originChatInStack];
    if (chat) { [chat presentForwardPickerForMessage:m fromViewController:self]; }
    else { [self im_showToast:@"请回到聊天页转发"]; } // 详情页非从聊天进入（如通讯录），无聊天上下文
}

/// 定位到聊天：pop 回本会话聊天页并滚到该消息高亮一闪。
- (void)locateFileMessageInChat:(IMMessageModel *)m {
    IMChatViewController *chat = [self originChatInStack];
    if (!chat) { [self im_showToast:@"请回到聊天页查看"]; return; }
    if (m.convSeq <= 0) { [self im_showToast:@"该消息无法定位"]; return; }
    int64_t seq = m.convSeq;
    [self.navigationController popToViewController:chat animated:YES];
    // pop 动画进行中滚动会被转场吞掉/落错位（dispatch_async 只是下一轮 runloop，仍在动画中）。
    // 挂在转场协调器的完成回调上，等 pop 真正落定再跳；无协调器（罕见）回落下一轮 runloop。
    id<UIViewControllerTransitionCoordinator> tc = self.navigationController.transitionCoordinator;
    if (tc) {
        [tc animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
            [chat jumpToConvSeq:seq];
        }];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ [chat jumpToConvSeq:seq]; });
    }
}

/// 删除文件（任务2，两档，参照 Telegram/主流 IM）：
/// 我发的 / 群主·管理员 → 【为所有人删除】(WS msg_op delete，对端也消失) +【仅删除自己】；
/// 他人发的普通成员 → 仅【删除】(=仅删除自己，REST 隐藏 + 多设备同步)。
/// 交互（任务2 优化）：长按菜单里「删除」——可为所有人删时展开**原生子菜单**（为所有人删除/仅删除自己），
/// 否则「删除」=仅删除自己；不再用居中 actionSheet。菜单构造见 contentMenuConfigForMessage:。

/// 我能否为该消息「为所有人删除」：我发的，或群主/管理员。
- (BOOL)canDeleteForEveryone:(IMMessageModel *)m {
    if (m.from.length > 0 && [m.from isEqualToString:self.userID]) { return YES; }
    return self.isGroup && (self.group.myRole == IMGroupRoleOwner || self.group.myRole == IMGroupRoleAdmin);
}

/// 为所有人删除（任务2）：WS msg_op op=delete；服务端广播回经 IMSocketDidRemoveMessageNotification 移除本地。被拒走 reject 通知。
- (void)deleteMessageForEveryone:(IMMessageModel *)m {
    if (m.convSeq <= 0) { return; }
    [[IMSocketManager sharedManager] deleteMessageForEveryoneInConv:(m.convID ?: self.convID) targetConvSeq:m.convSeq];
}

/// 仅删除自己（任务2）：编排（REST hide + 本端移除）收敛在 IMSocketManager，VC 只负责失败 toast。
- (void)hideMessageForSelf:(IMMessageModel *)m {
    if (m.convSeq <= 0) { return; }
    __weak typeof(self) ws = self;
    [[IMSocketManager sharedManager] hideMessageInConv:(m.convID ?: self.convID) targetConvSeq:m.convSeq
                                            completion:^(NSError *error) {
        if (error) { [ws im_showToast:error.localizedDescription ?: @"删除失败"]; }
    }];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return self.quickLookURL ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return self.quickLookURL;
}

- (void)openMediaItem:(IMMediaItem *)item {
    IMMediaViewerViewController *viewer = [IMMediaViewerViewController viewerWithURL:item.url isVideo:item.isVideo
                                                                     preloadedImage:nil onOpenGallery:nil];
    [self presentViewController:viewer animated:YES completion:nil];
}
/// 应用内浏览器打开链接（SFSafariViewController，仅接受 http/https；与聊天页 openLink: 一致）。
- (void)openLink:(NSString *)url {
    NSURL *u = [NSURL URLWithString:url ?: @""];
    if (!u || !([u.scheme isEqualToString:@"http"] || [u.scheme isEqualToString:@"https"])) { return; }
    SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:u];
    [self presentViewController:safari animated:YES completion:nil];
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
