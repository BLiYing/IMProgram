#import "IMAlbumCell.h"
#import "IMRejectNoteView.h"
#import "IMMessageModel.h"
#import "IMUploadProgress.h"
#import "IMDownloadProgress.h"
#import "IMPendingMediaStore.h"
#import "IMMediaFormat.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaExpiryRegistry.h" // 被动展示 404 失效登记 + 复验
#import "IMMediaPlaceholder.h" // 共用失效 ⊘ 字形
#import "IMMediaUtil.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"

@interface IMAlbumTileView : UIView
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *playBadge;
@property (nonatomic, strong) UILabel *durationChip; ///< 左上角视频时长角标（上传态隐藏，与覆盖层互斥）
@property (nonatomic, strong) IMMessageModel *member; ///< 本格对应的消息（tap/菜单定位用）
@property (nonatomic, copy)   NSString *loadKey;      ///< 异步加载防串图
@property (nonatomic, assign, readonly) BOOL gated;   ///< YES=未下载门控中（点击=下载，不进查看器）
- (void)setProgress:(nullable IMUploadProgress *)p; ///< nil/已完成=无覆盖；否则环形进度；failed=红「!」
/// 下载门控（M4-7）：nil=就绪（清掉门控外观）；非 nil=显 ↓/环形进度 + 尺寸角标。
- (void)setDownloadState:(nullable IMDownloadProgress *)dp sizeBytes:(int64_t)sizeBytes;
/// 被动展示失效（曾可用图/视频被服务端清理，404）：YES=dim 底 + 中心 ⊘、不重试；NO=清除。格子小，只显 ⊘ 不带文案。
- (void)setExpired:(BOOL)expired;
@end

@implementation IMAlbumTileView {
    UIView       *_dim;      // 上传中压暗
    CAShapeLayer *_ringBG;   // 环底
    CAShapeLayer *_ring;     // 进度环
    UILabel      *_failBadge;
    UIImageView  *_stateBadge; // 环中心小图标：⏸ 可暂停 / ↑ 已暂停(点击续传) / ✕ 排队压缩(点击取消)
    UIImageView  *_expiredBadge; // 中心 ⊘（被动展示 404 失效）
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        self.backgroundColor = UIColor.tertiarySystemFillColor;
        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self addSubview:_imageView];

        _dim = [[UIView alloc] initWithFrame:self.bounds];
        _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        _dim.hidden = YES;
        [self addSubview:_dim];

        _playBadge = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"play.circle.fill"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightRegular]]];
        _playBadge.tintColor = [UIColor colorWithWhite:1 alpha:0.95];
        _playBadge.hidden = YES;
        [self addSubview:_playBadge];

        _expiredBadge = [[UIImageView alloc] initWithImage:[IMMediaPlaceholder expiredGlyphImage]];
        _expiredBadge.hidden = YES;
        [self addSubview:_expiredBadge];

        UIBezierPath *circle = [UIBezierPath bezierPathWithArcCenter:CGPointMake(18, 18) radius:15
                                                          startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
        _ringBG = [CAShapeLayer layer];
        _ringBG.path = circle.CGPath;
        _ringBG.fillColor = UIColor.clearColor.CGColor;
        _ringBG.strokeColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        _ringBG.lineWidth = 3;
        _ringBG.frame = CGRectMake(0, 0, 36, 36);
        _ringBG.hidden = YES;
        [self.layer addSublayer:_ringBG];

        _ring = [CAShapeLayer layer];
        _ring.path = circle.CGPath;
        _ring.fillColor = UIColor.clearColor.CGColor;
        _ring.strokeColor = UIColor.whiteColor.CGColor;
        _ring.lineWidth = 3;
        _ring.lineCap = kCALineCapRound;
        _ring.strokeEnd = 0;
        _ring.frame = CGRectMake(0, 0, 36, 36);
        _ring.hidden = YES;
        [self.layer addSublayer:_ring];

        _failBadge = [UILabel new];
        _failBadge.text = @"!";
        _failBadge.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        _failBadge.textColor = UIColor.whiteColor;
        _failBadge.textAlignment = NSTextAlignmentCenter;
        _failBadge.backgroundColor = UIColor.systemRedColor;
        _failBadge.layer.cornerRadius = 14;
        _failBadge.clipsToBounds = YES;
        _failBadge.hidden = YES;
        [self addSubview:_failBadge];

        _stateBadge = [UIImageView new];
        _stateBadge.tintColor = UIColor.whiteColor;
        _stateBadge.contentMode = UIViewContentModeCenter;
        _stateBadge.hidden = YES;
        [self addSubview:_stateBadge];

        _durationChip = [UILabel new];
        _durationChip.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium];
        _durationChip.textColor = UIColor.whiteColor;
        _durationChip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        _durationChip.textAlignment = NSTextAlignmentCenter;
        _durationChip.layer.cornerRadius = 8;
        _durationChip.clipsToBounds = YES;
        _durationChip.hidden = YES;
        [self addSubview:_durationChip];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGPoint c = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    _playBadge.center = c;
    _failBadge.frame = CGRectMake(0, 0, 28, 28);
    _failBadge.center = c;
    _stateBadge.frame = CGRectMake(0, 0, 30, 30);
    _stateBadge.center = c;
    [_expiredBadge sizeToFit];
    _expiredBadge.center = c;
    CGSize d = [_durationChip sizeThatFits:CGSizeMake(CGFLOAT_MAX, 16)];
    _durationChip.frame = CGRectMake(4, 4, d.width + 10, 16);
    CGRect ringFrame = CGRectMake(c.x - 18, c.y - 18, 36, 36);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ringBG.frame = ringFrame;
    _ring.frame = ringFrame;
    [CATransaction commit];
}
/// 逐格下载门控（收到的媒体，M4-7）：中心 ↓/⏸/↻ + 环形进度 + 左上角尺寸角标；nil 清回就绪外观。
/// 与上传态互斥——门控只对**收到的**消息成立，收到的消息不可能同时在上传。
- (void)setDownloadState:(IMDownloadProgress *)dp sizeBytes:(int64_t)sizeBytes {
    _gated = dp != nil && dp.phase != IMDownloadPhaseDone;
    if (!_gated) {
        _dim.hidden = YES; _ringBG.hidden = YES; _ring.hidden = YES;
        _stateBadge.hidden = YES; _failBadge.hidden = YES;
        _playBadge.hidden = ![self.member.contentType isEqualToString:@"video"];
        self.isAccessibilityElement = NO; self.accessibilityLabel = nil;
        return;
    }
    _playBadge.hidden = YES; _failBadge.hidden = YES;
    _dim.hidden = NO;
    // 中心图标沿用上传宫格的「小一号纯字形」口径（气泡用 .circle.fill 版本，这里去掉圆底）。
    NSString *symbol = @"arrow.down";
    if (dp.phase == IMDownloadPhaseDownloading) { symbol = dp.pausable ? @"pause.fill" : @"xmark"; }
    else if (dp.phase == IMDownloadPhaseFailed) { symbol = dp.expired ? nil : @"arrow.clockwise"; } // 已失效：不给重试
    _stateBadge.image = symbol ? [UIImage systemImageNamed:symbol
                                         withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold]]
                               : nil;
    _stateBadge.hidden = symbol == nil;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = [dp accessibilityText];
    BOOL showRing = dp.phase == IMDownloadPhaseDownloading || dp.phase == IMDownloadPhasePaused;
    _ringBG.hidden = !showRing; _ring.hidden = !showRing;
    if (showRing) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _ring.strokeEnd = MAX(0.02, dp.fraction);
        [CATransaction commit];
    }
    // 左上角角标：未下载显尺寸（"下载前先知道多大"），下载中/暂停显已下/总，失败显文案。
    // 格子只有 ~78pt 宽，容不下「尺寸 · 时长」两项 → 门控期让位给尺寸，时长等就绪后回来。
    NSString *text = dp.phase == IMDownloadPhaseNotStarted
        ? (sizeBytes > 0 ? IMFormatFileSize(sizeBytes) : nil) : [dp displayText];
    _durationChip.text = text;
    _durationChip.hidden = text.length == 0;
    [self setNeedsLayout];
}

- (void)setExpired:(BOOL)expired {
    if (expired) {
        _dim.hidden = NO;                 // 复用上传/门控的压暗层作 dim 底
        _playBadge.hidden = YES; _failBadge.hidden = YES; _stateBadge.hidden = YES;
        _ringBG.hidden = YES; _ring.hidden = YES;
        _durationChip.hidden = YES;
        _expiredBadge.hidden = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitImage;
        self.accessibilityLabel = @"已失效";
        [self setNeedsLayout];
    } else {
        _expiredBadge.hidden = YES;       // dim 由 setDownloadState:/setProgress: 各自决定，这里不强关
    }
}

- (void)setProgress:(IMUploadProgress *)p {
    if (_gated) { return; } // 门控格的外观由 setDownloadState: 全权负责，勿被上传路径复位
    // 时长角标不参与覆盖层互斥：宫格的进度是中心圆环，左上角本就空着——探测出时长（上传前）即显示。
    // （单张气泡不同：其左上角要显「已传/总大小」文字，才需要互斥。）
    if (!p || (!p.failed && p.overallFraction >= 1)) { // 无进度 / 完成
        _dim.hidden = YES; _ringBG.hidden = YES; _ring.hidden = YES; _failBadge.hidden = YES;
        _stateBadge.hidden = YES;
        _playBadge.hidden = ![self.member.contentType isEqualToString:@"video"]; // 恢复播放角标（refresh 路径不走 bind）
        return;
    }
    _playBadge.hidden = YES; // 上传/失败态中心位让给状态图标（传完由重新 bind 恢复）
    if (p.failed) {
        _dim.hidden = NO; _ringBG.hidden = YES; _ring.hidden = YES; _failBadge.hidden = NO;
        _stateBadge.hidden = YES;
        return;
    }
    _dim.hidden = NO; _failBadge.hidden = YES;
    _ringBG.hidden = NO; _ring.hidden = NO;
    // 环中心小图标（与单张气泡同一状态机，小一号）：
    //   排队/压缩 → ✕（点击确认取消）；上传中可暂停 → ⏸；已暂停 → ↑（点击继续上传）。
    NSString *symbol = nil;
    if (p.phase == IMUploadPhaseQueued || p.phase == IMUploadPhaseTranscoding) { symbol = @"xmark"; }
    else if (p.pausable) { symbol = p.pausedByUser ? @"arrow.up" : @"pause.fill"; }
    _stateBadge.image = symbol
        ? [UIImage systemImageNamed:symbol
                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold]]
        : nil;
    _stateBadge.hidden = symbol == nil;
    [CATransaction begin];
    [CATransaction setDisableActions:YES]; // 高频进度回调不做隐式动画（避免滞后）
    // 用融合后的总进度：转码 0→35%、上传 35%→100%，跨阶段连续，不会走到头又跳回 0。
    _ring.strokeEnd = MAX(0.02, p.overallFraction); // 0% 也露一点头，可感知"在动"
    [CATransaction commit];
}
@end

/// 相册宫格 cell：leader 行渲染同组全部成员；行高由块布局决定（同数量恒定高，进度/缩略图更新不动布局）。
static NSArray<NSNumber *> *IMAlbumRowPattern(NSUInteger n) {
    switch (n) {
        case 1:  return @[@1];
        case 2:  return @[@2];
        case 3:  return @[@1, @2];
        case 4:  return @[@2, @2];
        case 5:  return @[@2, @3];
        case 6:  return @[@3, @3];
        case 7:  return @[@1, @3, @3];
        case 8:  return @[@2, @3, @3];
        default: return @[@3, @3, @3]; // 9（selectionLimit=9 封顶）
    }
}

static const CGFloat kIMAlbumWidth = 240;
static const CGFloat kIMAlbumGap = 2;

/// 给定块数的宫格总高（布局确定 → 行高确定，自适应行高稳定）。
static CGFloat IMAlbumHeightForCount(NSUInteger n) {
    if (n == 0) { return 0; }
    CGFloat h = 0;
    for (NSNumber *k in IMAlbumRowPattern(n)) {
        NSUInteger cols = k.unsignedIntegerValue;
        CGFloat tileH = cols == 1 ? 150 : (kIMAlbumWidth - (cols - 1) * kIMAlbumGap) / cols;
        h += tileH + kIMAlbumGap;
    }
    return h - kIMAlbumGap;
}

@interface IMAlbumCell () <UIContextMenuInteractionDelegate>
@end

@implementation IMAlbumCell {
    UIView *_container;                        // 固定宽 240，圆角裁切
    NSMutableArray<IMAlbumTileView *> *_tiles; // 复用池（按需增建）
    UILabel *_metaChip;                        // 右下角 时间+状态 小胶囊
    UILabel *_senderLabel;                     // 群聊对方昵称（宫格上方）
    // _avatar 由 IMMessageCell 基类持有（贴宫格底左侧，约束在本类补）。
    NSLayoutConstraint *_containerHeight;
    NSLayoutConstraint *_leading, *_trailing;
    NSLayoutConstraint *_containerTopPlain;      // 无昵称：宫格贴 cell 顶
    NSLayoutConstraint *_containerTopUnderName;  // 有昵称：宫格挂昵称下方
    // 整组发送失败：宫格左侧红❗（仅自己）。与 IMBubbleCell/IMImageCell 同款——
    // 注意与 IMAlbumTileView 自己的 _failBadge 不是一回事：那个是**逐格**中心的 "!"，
    // 表达"这一格失败了"；这个在宫格外侧，表达"这条消息发失败了"，两者互补。
    UILabel *_failBadge;
    NSLayoutConstraint *_failBadgeTrailing;      // 仅失败时激活，避免恒占位挤压宫格
    IMRejectNoteView *_sysNote;                  // 被拒收系统行（整组共用一条，宫格下方居中）
    NSLayoutConstraint *_containerBottom;        // 无系统行时：宫格贴 cell 底
    NSLayoutConstraint *_noteTop;                // 有系统行时：系统行接宫格底
    NSLayoutConstraint *_noteBottom;             // 有系统行时：系统行贴 cell 底
    NSString *_host;
    // _unreadDivider / _unreadDividerHeight 由 IMMessageCell 基类持有。
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _tiles = [NSMutableArray array];
        _container = [UIView new];
        _container.translatesAutoresizingMaskIntoConstraints = NO;
        _container.layer.cornerRadius = IMTheme.radiusBubble;
        _container.clipsToBounds = YES;
        [self.contentView addSubview:_container];

        _metaChip = [UILabel new];
        _metaChip.font = [UIFont systemFontOfSize:11];
        _metaChip.textColor = UIColor.whiteColor;
        _metaChip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        _metaChip.layer.cornerRadius = 9;
        _metaChip.clipsToBounds = YES;
        _metaChip.textAlignment = NSTextAlignmentCenter;
        [_container addSubview:_metaChip];

        _senderLabel = [UILabel new];
        _senderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _senderLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _senderLabel.textColor = IMTheme.accent;
        _senderLabel.hidden = YES;
        [self.contentView addSubview:_senderLabel];
        [self installSenderRoleBadgeForNameLabel:_senderLabel];  // 群主/管理员徽标（基类统一样式/截断）

        // _avatar 由 IMMessageCell 基类创建（视图 + 点击插桩）；本类只补它的 leading/bottom/size 约束。

        _failBadge = [UILabel new];
        _failBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _failBadge.text = @"!";
        _failBadge.textAlignment = NSTextAlignmentCenter;
        _failBadge.font = [UIFont boldSystemFontOfSize:13];
        _failBadge.textColor = UIColor.whiteColor;
        _failBadge.backgroundColor = UIColor.systemRedColor;
        _failBadge.layer.cornerRadius = 9;
        _failBadge.layer.masksToBounds = YES;
        _failBadge.hidden = YES;
        [self.contentView addSubview:_failBadge];

        _sysNote = [IMRejectNoteView new];
        _sysNote.translatesAutoresizingMaskIntoConstraints = NO;
        _sysNote.hidden = YES;
        __weak typeof(self) wsNote = self;
        _sysNote.onActionTap = ^{ if (wsNote.onNoteActionTap) { wsNote.onNoteActionTap(); } };
        [self.contentView addSubview:_sysNote];

        // _unreadDivider 由 IMMessageCell 基类创建并自锚（顶/左/右 + 高 0）；本类把顶部内容改锚它的 bottom。

        // 左右/上下两组约束**恒定激活，靠优先级切换**，不再用 active 开关。
        // 真机日志里出现过 leading 与 trailing、topPlain 与 topUnderName 同时激活导致
        // "Unable to simultaneously satisfy constraints"，UIKit 的恢复方式是打断 width/height，
        // 于是宫格以错误尺寸布局并反复重算（滚动卡顿的一部分）。优先级方案从结构上就不可能冲突。
        _leading = [_container.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_container.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _containerHeight = [_container.heightAnchor constraintEqualToConstant:100];
        _containerTopPlain = [_container.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:3];
        _containerTopUnderName = [_container.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        // 被拒收系统行：有则「宫格 → 系统行 → cell 底」，无则宫格直接贴底（与 IMBubbleCell 同构）。
        _containerBottom = [_container.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3];
        _noteTop = [_sysNote.topAnchor constraintEqualToAnchor:_container.bottomAnchor constant:4];
        _noteBottom = [_sysNote.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6];
        _failBadgeTrailing = [_failBadge.trailingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:-6];
        // 自适应行高：UIKit 会给 contentView 加 UIView-Encapsulated-Layout-Height（required），
        // 我们的高度必须让位，否则每次行高变化都报冲突。999 保证正常情况下仍精确生效。
        _containerHeight.priority = UILayoutPriorityDefaultHigh + 1; // 751 足够压过内容，且低于 required
        NSLayoutConstraint *widthConstraint = [_container.widthAnchor constraintEqualToConstant:kIMAlbumWidth];
        widthConstraint.priority = UILayoutPriorityRequired - 1;     // 999
        [NSLayoutConstraint activateConstraints:@[
            [_senderLabel.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:4],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_container.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
            _containerBottom,
            // 红❗：钉在宫格左侧、垂直居中（仅自己失败时显示，与文本/单图气泡同款）。
            [_failBadge.widthAnchor constraintEqualToConstant:18],
            [_failBadge.heightAnchor constraintEqualToConstant:18],
            [_failBadge.centerYAnchor constraintEqualToAnchor:_container.centerYAnchor],
            [_sysNote.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24],
            [_sysNote.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24],
            // 恒定的边界约束（required）：无论左右贴哪边，都不许超出内容区。
            [_container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_container.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_container.topAnchor constraintGreaterThanOrEqualToAnchor:_unreadDivider.bottomAnchor constant:3],
            widthConstraint, _containerHeight, _leading, _trailing, _containerTopPlain, _containerTopUnderName,
        ]];
        [self applyAlignmentMine:NO showName:NO];
    }
    return self;
}

/// 靠**优先级**切换左右贴边与顶部锚点（四条约束始终激活，不存在"两条 required 同时生效"）。
/// 生效的一侧 999，让位的一侧 1（最低），求解器自然忽略后者。
- (void)applyAlignmentMine:(BOOL)mine showName:(BOOL)showName {
    const UILayoutPriority on = UILayoutPriorityRequired - 1, off = UILayoutPriorityFittingSizeLevel;
    _leading.priority = mine ? off : on;
    _trailing.priority = mine ? on : off;
    _containerTopPlain.priority = showName ? off : on;
    _containerTopUnderName.priority = showName ? on : off;
}

- (void)configureWithMembers:(NSArray<IMMessageModel *> *)members mine:(BOOL)mine host:(NSString *)host
                    previews:(NSDictionary<NSString *, UIImage *> *)previews
                    progress:(NSDictionary<NSString *, IMUploadProgress *> *)progress
                  senderName:(NSString *)senderName
                  senderRole:(IMGroupRole)senderRole {
    _container.layer.cornerRadius = IMTheme.radiusBubble;
    _senderLabel.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 4) weight:UIFontWeightSemibold];
    _host = host;
    BOOL showName = senderName.length > 0;
    [self applySenderName:senderName role:senderRole toNameLabel:_senderLabel];
    _senderLabel.hidden = !showName;
    [self applyAlignmentMine:mine showName:showName];
    _containerHeight.constant = IMAlbumHeightForCount(members.count);

    // 被拒收系统行：整组共用一条（同一批发送、被同一个原因拒收），取首个带 note 的成员。
    // 同一趟扫出"整组是否有失败成员"，供宫格左侧红❗（与逐格 "!" 互补：那个指哪一格，这个指整条消息）。
    IMMessageModel *noted = nil;
    BOOL anyFailed = NO;
    for (IMMessageModel *m in members) {
        if (m.note.length > 0 && !noted) { noted = m; }
        if (m.status == IMMessageStatusFailed) { anyFailed = YES; }
    }
    BOOL failed = mine && anyFailed;
    _failBadge.hidden = !failed;
    _failBadgeTrailing.active = failed;
    [_sysNote configureWithNote:noted.note code:noted.noteCode];
    BOOL hasNote = _sysNote.hasContent;
    _containerBottom.active = !hasNote;
    _noteTop.active = hasNote;
    _noteBottom.active = hasNote;

    // 按需补足块视图；多余的隐藏。
    while (_tiles.count < members.count) {
        IMAlbumTileView *tile = [[IMAlbumTileView alloc] initWithFrame:CGRectZero];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tileTapped:)];
        [tile addGestureRecognizer:tap];
        [tile addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:(id<UIContextMenuInteractionDelegate>)self]];
        [_container addSubview:tile];
        [_tiles addObject:tile];
    }
    for (NSUInteger i = members.count; i < _tiles.count; i++) { _tiles[i].hidden = YES; }

    // 布局块（frame 手排，宽 240 固定；行模式决定块尺寸）。
    NSArray<NSNumber *> *pattern = IMAlbumRowPattern(members.count);
    NSUInteger idx = 0;
    CGFloat y = 0;
    for (NSNumber *k in pattern) {
        NSUInteger cols = k.unsignedIntegerValue;
        CGFloat tileW = (kIMAlbumWidth - (cols - 1) * kIMAlbumGap) / cols;
        CGFloat tileH = cols == 1 ? 150 : tileW;
        for (NSUInteger c = 0; c < cols && idx < members.count; c++, idx++) {
            IMAlbumTileView *tile = _tiles[idx];
            tile.hidden = NO;
            tile.frame = CGRectMake(c * (tileW + kIMAlbumGap), y, cols == 1 ? kIMAlbumWidth : tileW, tileH);
            [self bindTile:tile toMember:members[idx] previews:previews progress:progress];
        }
        y += tileH + kIMAlbumGap;
    }
    [_container bringSubviewToFront:_metaChip];
    [self updateMetaWithMembers:members mine:mine];
}

/// 单块绑定：本地预览优先（上传中/防闪），否则按 URL 异步加载（复用防串图）。
- (void)bindTile:(IMAlbumTileView *)tile toMember:(IMMessageModel *)m
        previews:(NSDictionary<NSString *, UIImage *> *)previews
        progress:(NSDictionary<NSString *, IMUploadProgress *> *)progress {
    tile.member = m;
    BOOL isVideo = [m.contentType isEqualToString:@"video"];
    tile.playBadge.hidden = !isVideo;
    // 左上角时长角标（与单张气泡一致）；上传态由 setProgress 按覆盖层互斥隐藏/恢复。
    tile.durationChip.text = isVideo ? IMFormatMediaDuration(m.duration) : nil;
    tile.durationChip.hidden = tile.durationChip.text.length == 0;
    [tile setNeedsLayout];
    // 下载门控（M4-7）先于上传态判定：门控成立时 setProgress: 自会让位（收到的消息不会同时在上传）。
    BOOL remote = m.content.length > 0 && ![IMPendingMediaStore isLocalRef:m.content];
    IMDownloadProgress *dl = (remote && self.downloadStateForItem) ? self.downloadStateForItem(m) : nil;
    [tile setDownloadState:dl sizeBytes:m.fileSize];
    [tile setProgress:progress[m.clientMsgID ?: @""]];
    [tile setExpired:NO]; // 复用防残留：先清上一条的失效外观
    if (tile.gated) {
        // 门控格不拉原图/封面：只显 thumb 模糊占位（~200B data URI），没有就留灰底。
        tile.loadKey = nil;
        tile.imageView.image = nil;
        if (m.thumb.length > 0) {
            __weak IMAlbumTileView *wt = tile;
            NSString *thumbKey = m.thumb;
            tile.loadKey = thumbKey;
            [[IMImageLoader shared] loadImageURL:thumbKey completion:^(UIImage *img) {
                __strong IMAlbumTileView *t = wt;
                if (t && img && [t.loadKey isEqualToString:thumbKey]) { t.imageView.image = img; }
            }];
        }
        return;
    }

    UIImage *preview = previews[m.clientMsgID ?: @""];
    if (preview) { tile.imageView.image = preview; tile.loadKey = nil; return; }
    // content 为空=尚未上传；im-pending:// = 本地待发文件（不是网络地址，拿去拼 URL 会发出无效请求）。
    if (m.content.length == 0 || [IMPendingMediaStore isLocalRef:m.content]) {
        tile.imageView.image = nil; tile.loadKey = nil; return; // 占位灰底，缩略图由 previews 提供
    }
    NSString *full = IMMediaFullURL(m.content, _host);
    // 视频优先用封面 JPEG：抽帧要对远端视频发 range 请求拉几 MB，一屏九宫格就是九次。
    NSString *posterFull = (isVideo && m.poster.length > 0) ? IMMediaFullURL(m.poster, _host) : nil;
    NSString *imageURL = posterFull ?: full;
    tile.loadKey = imageURL;
    // 失效**一律以内容 full URL 为 key**（视频用 full 而非 poster），与气泡/查看器/媒体库统一，
    // 否则同一条消息在各面 key 不一致、失效状态互不传播（code-review #1）。
    // 已知失效：直接画 ⊘、不回源（掐 404 风暴）。
    if ([IMMediaExpiryRegistry.shared isExpiredURL:full]) { tile.imageView.image = nil; [tile setExpired:YES]; return; }
    // 同步命中缓存直接出图，不置 nil —— 否则每次滚进可视区都闪一下（与气泡同款问题）。
    UIImage *cached = (isVideo && !posterFull) ? [[IMVideoThumbnailLoader shared] cachedPosterForURL:imageURL]
                                              : [[IMImageLoader shared] cachedImageForURL:imageURL];
    if (cached) { tile.imageView.image = cached; return; }
    tile.imageView.image = nil;
    __weak IMAlbumTileView *wt = tile;
    void (^apply)(UIImage *) = ^(UIImage *img) {
        __strong IMAlbumTileView *t = wt;
        if (!t || ![t.loadKey isEqualToString:imageURL]) { return; }
        if (img) { t.imageView.image = img; return; }
        // 加载失败 → 复验**内容 full URL**（非 poster，与各面统一 key），命中才画失效（区分瞬时/解码）。
        [IMMediaExpiryRegistry.shared verifyExpiredForURL:full completion:^(BOOL expired) {
            __strong IMAlbumTileView *t2 = wt;
            if (t2 && expired && [t2.loadKey isEqualToString:imageURL]) { [t2 setExpired:YES]; }
        }];
    };
    if (isVideo && !posterFull) { [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:full completion:apply]; }
    else { [[IMImageLoader shared] loadImageURL:imageURL completion:apply]; }
}

- (void)refreshWithPreviews:(NSDictionary<NSString *, UIImage *> *)previews
                   progress:(NSDictionary<NSString *, IMUploadProgress *> *)progress {
    BOOL mine = NO;
    NSMutableArray<IMMessageModel *> *members = [NSMutableArray array];
    for (IMAlbumTileView *tile in _tiles) {
        IMMessageModel *m = tile.member;
        if (tile.hidden || !m) { continue; }
        [members addObject:m];
        mine = mine || m.status != IMMessageStatusReceived;
        if (tile.gated) { continue; } // 门控格的角标/图由 setDownloadState: 管，定点刷新别把它复位
        [tile setProgress:progress[m.clientMsgID ?: @""]];
        UIImage *preview = previews[m.clientMsgID ?: @""];
        if (preview && tile.imageView.image == nil) { tile.imageView.image = preview; }
        // 时长在探测完成（上传开始前）才写进模型：定点刷新也要回填，否则要等整行重 configure
        // （滑出屏再滑回）才显示——真机反馈"传完+滑动一下才出现"的根因。
        if ([m.contentType isEqualToString:@"video"]) {
            NSString *text = IMFormatMediaDuration(m.duration);
            if (text.length > 0 && ![text isEqualToString:tile.durationChip.text]) {
                tile.durationChip.text = text;
                [tile setNeedsLayout]; // 重算胶囊宽度
            }
            tile.durationChip.hidden = tile.durationChip.text.length == 0;
        }
    }
    [self updateMetaWithMembers:members mine:mine];
}

/// 右下角小胶囊：末条成员时间 + 自己消息的状态（… 发送中 / ✓ 全部送达 / ! 有失败）。
- (void)updateMetaWithMembers:(NSArray<IMMessageModel *> *)members mine:(BOOL)mine {
    IMMessageModel *last = members.lastObject;
    if (!last) { _metaChip.hidden = YES; return; }
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"HH:mm";
    NSString *time = last.timestamp > 0
        ? [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:last.timestamp / 1000.0]] : @"";
    NSString *suffix = @"";
    if (mine) {
        BOOL anyFailed = NO, allSent = YES;
        for (IMMessageModel *m in members) {
            if (m.status == IMMessageStatusFailed) { anyFailed = YES; }
            if (m.status != IMMessageStatusSent) { allSent = NO; }
        }
        // 失败**不在时间胶囊里标 "!"**：整条消息的失败由宫格左侧红❗表达（被拒收还有下方系统行），
        // 胶囊里再标一个感叹号是重复噪声。胶囊只负责时间 + 已发/发送中。
        suffix = anyFailed ? @"" : (allSent ? @" ✓" : @" …");
    }
    _metaChip.hidden = NO;
    _metaChip.text = [NSString stringWithFormat:@" %@%@ ", time, suffix];
    [_metaChip sizeToFit];
    CGSize s = CGSizeMake(_metaChip.bounds.size.width + 8, 18);
    _metaChip.frame = CGRectMake(kIMAlbumWidth - s.width - 6, _containerHeight.constant - s.height - 6, s.width, s.height);
}

- (void)updateDownloadProgress:(IMDownloadProgress *)dp forMessage:(IMMessageModel *)m {
    for (IMAlbumTileView *tile in _tiles) {
        if (tile.hidden || tile.member != m) { continue; }
        // 复用 setDownloadState:（只改覆盖层/环/角标，不重拉图）——门控态未变，无需重载缩略图。
        [tile setDownloadState:dp sizeBytes:m.fileSize];
        return;
    }
}

- (void)tileTapped:(UITapGestureRecognizer *)gr {
    IMAlbumTileView *tile = (IMAlbumTileView *)gr.view;
    if (![tile isKindOfClass:IMAlbumTileView.class] || !tile.member) { return; }
    // 门控格：点击=下载/暂停/继续/重试（就地，不进查看器）；就绪格才走查看器（铁律②：完成不自动打开）。
    if (tile.gated) { if (_onDownloadItem) { _onDownloadItem(tile.member); } return; }
    if (_onTapItem) { _onTapItem(tile.member); }
}

/// 每块自带长按菜单（定位到该块对应的单条消息 → 单张引用/转发/撤回/收藏等）。
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    IMAlbumTileView *tile = (IMAlbumTileView *)interaction.view;
    if (![tile isKindOfClass:IMAlbumTileView.class] || !tile.member || !_menuForItem) { return nil; }
    IMMessageModel *m = tile.member;
    UIMenu * (^provider)(IMMessageModel *) = _menuForItem;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) { return provider(m); }];
}

// onAvatarTap 的手势、handleAvatarTap、applyUnreadDivider: 均由 IMMessageCell 基类提供。

- (void)applyGroupAvatarURL:(NSString *)url seed:(NSString *)seed name:(NSString *)name
                 showAvatar:(BOOL)showAvatar gutter:(BOOL)gutter {
    _leading.constant = gutter ? 48 : 12;   // 对方群消息留 30 头像列（12 + 30 + 6）
    if (gutter && showAvatar) {
        _avatar.hidden = NO;
        [_avatar im_setAvatarURL:url seed:seed displayName:name];
    } else {
        _avatar.hidden = YES;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    for (IMAlbumTileView *tile in _tiles) {
        [tile setDownloadState:nil sizeBytes:0]; // 先清门控，否则 setProgress: 会被门控守卫挡住
        tile.member = nil; tile.loadKey = nil; tile.imageView.image = nil;
        [tile setProgress:nil];
    }
    _avatar.hidden = YES;
    _leading.constant = 12;
    _onTapItem = nil;
    _menuForItem = nil;
    _downloadStateForItem = nil;
    _onDownloadItem = nil;
    // onAvatarTap / 头像与分割线的复位由 IMMessageCell 基类 prepareForReuse 统一处理。
}
@end
