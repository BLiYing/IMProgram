#import "IMImageCell.h"
#import "IMBubbleCell.h" // +attributedContent:base:mentionColor:mentions:（图说 caption @高亮复用）
#import "IMRejectNoteView.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMessageModel.h"
#import "IMUploadProgress.h"
#import "IMDownloadProgress.h"
#import "IMMediaFormat.h"
#import "IMMediaUtil.h" // IMFormatFileSize
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"
#import "IMLog.h" // 门控占位渲染点位日志（media_gated_render / media_gated_thumb_dropped）
#import "IMMediaPlaceholder.h" // 磨砂占位统一渲染器（三处共用）
#import "IMMediaExpiryRegistry.h" // 被动展示 404 失效登记 + 复验（曾可用媒体被清理）

/// 气泡最大盒子：宽取 240 与屏宽 62% 的较小者（窄屏也不顶满），高 320（长图不会撑满整屏）。
static const CGFloat kIMMediaMaxWidth = 240;
static const CGFloat kIMMediaMaxHeight = 320;
static const CGFloat kIMMediaMinSide = 80;   // 极端长条的短边下限（保证可点按）
static const CGFloat kIMBadgeInset = 6;      // 角标距缩略图边缘
static const CGFloat kIMBadgeHeight = 18;
static const CGFloat kIMDownloadRingSide = 56; // 下载进度环外接方形边长（绕 44pt 中心圆钮一圈）

static UIImage *IMCenterBadgeImage(NSString *symbolName); // 中心按钮图标（播放/暂停/继续/重试/取消）

@implementation IMImageCell {
    UIImageView *_thumb;
    UIImageView *_playBadge;   // 视频封面上的播放角标
    UIView  *_progressWrap;    // 左上角进度胶囊（上传中；与时长角标互斥）
    UILabel *_progressLabel;
    UIView  *_durationWrap;    // 左上角时长胶囊（视频，非上传中）
    UILabel *_durationLabel;
    UIView  *_metaWrap;        // 右下角时间 + 已读态胶囊
    UILabel *_metaLabel;
    UILabel *_senderLabel;     // 群聊对方昵称（缩略图上方）
    // _avatar 由 IMMessageCell 基类持有（贴缩略图底左侧，约束在本类补）。
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    NSLayoutConstraint *_thumbWidth;
    NSLayoutConstraint *_thumbHeight;
    NSLayoutConstraint *_thumbTopPlain;      // 无昵称：thumb 贴 cell 顶
    NSLayoutConstraint *_thumbTopUnderName;  // 有昵称：thumb 挂昵称下方
    UILabel *_failBadge;                     // 发送失败：缩略图左侧红❗（仅自己；与 IMBubbleCell 同款）
    NSLayoutConstraint *_failBadgeTrailing;   // 仅失败时激活，避免恒占位挤压缩略图
    IMRejectNoteView *_sysNote;              // 被拒收系统行（缩略图下方居中，可恢复时带「发送好友申请」）
    NSLayoutConstraint *_thumbBottom;        // 无系统行/无 caption 时：thumb 贴 cell 底
    NSLayoutConstraint *_noteTop;            // 有系统行时：系统行接 thumb 底
    NSLayoutConstraint *_noteBottom;         // 有系统行时：系统行贴 cell 底
    UILabel *_captionLabel;                  // 图说 caption（图文/视频文下方随附文本，Telegram 模型，iOS 只显示）
    NSLayoutConstraint *_captionTop;         // 有 caption：caption 接 thumb 底
    NSLayoutConstraint *_captionBottom;      // 有 caption 无系统行：caption 贴 cell 底
    NSLayoutConstraint *_noteTopUnderCaption;// caption + 系统行：系统行接 caption 底
    UIView *_captionBG;                      // ④ 图说整体化：有 caption 时套一层气泡底（媒体圆上角 + caption 落此底 + 圆下角，成一整块）
    NSArray<NSLayoutConstraint *> *_captionBGConstraints; // 仅有 caption 时激活：气泡底裹住 thumb 顶→caption 底
    CAShapeLayer *_ringBG;     // 下载进度环底（仅门控·下载中显示）
    CAShapeLayer *_ring;       // 下载进度环
    UIView *_ringWrap;         // 进度环容器：固定 kIMDownloadRingSide 见方、Auto Layout 居中锚 _thumb（免手动摆位错位）
    NSString *_url;
    BOOL _sizeFromMedia;       // YES=尺寸来自协议/预览（权威），加载出图后无需重排
    BOOL _isVideoCell;         // 上传态结束后据此还原中心播放按钮（图片则隐藏）
    NSString *_timeText;       // 右下角时间文案（暂停时替换「发送中…」用）
    int64_t _gatedSizeBytes;   // 门控态左上角"未下载尺寸"用（供进度就地更新复用，免重传 message）
    NSString *_gatedDurationText; // 门控态左上角时长（视频）
    UIView *_expiredOverlay;   // 失效占位覆盖层（被动展示 404：曾可用媒体被服务端清理）；复用时移除
    // _unreadDivider / _unreadDividerHeight 由 IMMessageCell 基类持有。
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _thumb = [UIImageView new];
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.layer.cornerRadius = IMTheme.radiusBubble;
        _thumb.backgroundColor = UIColor.tertiarySystemFillColor;
        _thumb.userInteractionEnabled = YES;
        [_thumb addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
        [self.contentView addSubview:_thumb];

        _playBadge = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"play.circle.fill"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightRegular]]];
        _playBadge.tintColor = [UIColor colorWithWhite:1 alpha:0.95];
        _playBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _playBadge.hidden = YES;
        [self.contentView addSubview:_playBadge];

        // 下载进度环：绕中心圆钮一圈（与相册宫格 IMAlbumTileView、草图 §02「环形进度 + ⏸」同款）。
        // 环层挂在固定尺寸、Auto Layout 居中锚 _thumb 的 _ringWrap 上（对齐 IMBubbleCell 的 _fileIconWrap），
        // 不再随 layoutSubviews 手动按 _thumb.frame 摆位——多选/编辑态/reload 的几何抖动下也不会脱位。
        _ringWrap = [UIView new];
        _ringWrap.translatesAutoresizingMaskIntoConstraints = NO;
        _ringWrap.userInteractionEnabled = NO; // 让点击穿透到 _thumb
        [self.contentView addSubview:_ringWrap];
        _ringBG = [self makeRingLayerWithColor:[UIColor colorWithWhite:1 alpha:0.32] rounded:NO];
        _ring = [self makeRingLayerWithColor:UIColor.whiteColor rounded:YES];

        _progressWrap = [self makeBadgeWrapWithLabel:&_progressLabel];
        _durationWrap = [self makeBadgeWrapWithLabel:&_durationLabel];
        _metaWrap = [self makeBadgeWrapWithLabel:&_metaLabel];

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

        // ④ 图说整体化：有 caption 时在 thumb+caption 背后垫一层气泡底，媒体只圆上角、贴进 caption 区，成 Telegram 式一整块。
        _captionBG = [UIView new];
        _captionBG.translatesAutoresizingMaskIntoConstraints = NO;
        _captionBG.layer.cornerRadius = IMTheme.radiusBubble;
        _captionBG.hidden = YES;
        [self.contentView insertSubview:_captionBG belowSubview:_thumb]; // 在 thumb 之下（caption label 之后加=在 bg 之上，可读）

        // 图说 caption（Telegram 模型）：缩略图下方随附文本，落在 _captionBG 气泡底上（对齐媒体左右、留内边距）；
        // 多行自适应，行高由 Auto Layout 自撑（self-sizing cell）。
        _captionLabel = [UILabel new];
        _captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _captionLabel.numberOfLines = 0;
        _captionLabel.font = [UIFont systemFontOfSize:IMTheme.chatFontSize];
        _captionLabel.textColor = IMTheme.bubbleMeText;
        _captionLabel.hidden = YES;
        [self.contentView addSubview:_captionLabel];

        // _unreadDivider 由 IMMessageCell 基类创建并自锚（顶/左/右 + 高 0）；本类把顶部内容改锚它的 bottom。

        // 与 IMAlbumCell 同策略：左右/上下两组约束恒定激活、**靠优先级切换**，杜绝
        // "两条 required 同时生效 → UIKit 打断 width/height" 的自适应行高冲突（真机日志实录）。
        _leading = [_thumb.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_thumb.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _thumbTopPlain = [_thumb.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:3];
        _thumbTopUnderName = [_thumb.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        _thumbWidth = [_thumb.widthAnchor constraintEqualToConstant:kIMMediaFallbackSide];
        _thumbHeight = [_thumb.heightAnchor constraintEqualToConstant:kIMMediaFallbackSide];
        _thumbWidth.priority = UILayoutPriorityRequired - 1;              // 999，让位 Encapsulated-Layout-Width
        _thumbHeight.priority = UILayoutPriorityDefaultHigh + 1;          // 751，让位 Encapsulated-Layout-Height
        // 被拒收系统行：有则「thumb → 系统行 → cell 底」，无则 thumb 直接贴底（与 IMBubbleCell 同构）。
        _thumbBottom = [_thumb.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3];
        _noteTop = [_sysNote.topAnchor constraintEqualToAnchor:_thumb.bottomAnchor constant:4];
        _noteBottom = [_sysNote.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6];
        // 图说 caption 底部链（按 hasCaption × hasNote 在 configure 里切换，杜绝两条 required 同底冲突）。
        _captionTop = [_captionLabel.topAnchor constraintEqualToAnchor:_thumb.bottomAnchor constant:6];
        _captionBottom = [_captionLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10];
        // 14 = 气泡底向下延伸 10（_captionBGConstraints 尾项）+ 4 间距：系统行必须落在气泡底**之外**，
        // 用 4 会被不透明的 _captionBG 盖住顶部 6pt（code-review 2026-08-19）。
        _noteTopUnderCaption = [_sysNote.topAnchor constraintEqualToAnchor:_captionLabel.bottomAnchor constant:14];
        // ④ 气泡底裹住 thumb 顶 → caption 底（仅有 caption 时激活）。
        _captionBGConstraints = @[
            [_captionBG.topAnchor constraintEqualToAnchor:_thumb.topAnchor],
            [_captionBG.leadingAnchor constraintEqualToAnchor:_thumb.leadingAnchor],
            [_captionBG.trailingAnchor constraintEqualToAnchor:_thumb.trailingAnchor],
            [_captionBG.bottomAnchor constraintEqualToAnchor:_captionLabel.bottomAnchor constant:10],
        ];
        _failBadgeTrailing = [_failBadge.trailingAnchor constraintEqualToAnchor:_thumb.leadingAnchor constant:-6];
        [NSLayoutConstraint activateConstraints:@[
            // 恒定边界（required）：无论贴左还是贴右，都不许超出内容区。
            [_thumb.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_thumb.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_thumb.topAnchor constraintGreaterThanOrEqualToAnchor:_unreadDivider.bottomAnchor constant:3],
            _leading, _trailing, _thumbTopPlain, _thumbTopUnderName,
            [_senderLabel.topAnchor constraintEqualToAnchor:_unreadDivider.bottomAnchor constant:4],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_thumb.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_thumb.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
            _thumbBottom, _thumbWidth, _thumbHeight,
            // 红❗：钉在缩略图左侧、垂直居中（仅自己失败时显示，与 IMBubbleCell 同款）。
            [_failBadge.widthAnchor constraintEqualToConstant:18],
            [_failBadge.heightAnchor constraintEqualToConstant:18],
            [_failBadge.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
            [_sysNote.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24],
            [_sysNote.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24],
            // caption 恒定左右边（对齐缩略图边、内缩 10 作气泡内边距）；顶/底链在 configure 里按需激活。
            [_captionLabel.leadingAnchor constraintEqualToAnchor:_thumb.leadingAnchor constant:10],
            [_captionLabel.trailingAnchor constraintEqualToAnchor:_thumb.trailingAnchor constant:-10],
            [_playBadge.centerXAnchor constraintEqualToAnchor:_thumb.centerXAnchor],
            [_playBadge.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
            // 进度环容器：与中心按钮同心锚 _thumb、定宽定高（环 path 在其局部坐标内居中，无需再算 frame）。
            [_ringWrap.centerXAnchor constraintEqualToAnchor:_thumb.centerXAnchor],
            [_ringWrap.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
            [_ringWrap.widthAnchor constraintEqualToConstant:kIMDownloadRingSide],
            [_ringWrap.heightAnchor constraintEqualToConstant:kIMDownloadRingSide],
            // 进度与时长共用左上角位置（互斥显示：上传中显进度，传完切回时长）。
            [_progressWrap.leadingAnchor constraintEqualToAnchor:_thumb.leadingAnchor constant:kIMBadgeInset],
            [_progressWrap.topAnchor constraintEqualToAnchor:_thumb.topAnchor constant:kIMBadgeInset],
            [_progressWrap.trailingAnchor constraintLessThanOrEqualToAnchor:_thumb.trailingAnchor constant:-kIMBadgeInset],
            [_durationWrap.leadingAnchor constraintEqualToAnchor:_thumb.leadingAnchor constant:kIMBadgeInset],
            [_durationWrap.topAnchor constraintEqualToAnchor:_thumb.topAnchor constant:kIMBadgeInset],
            [_durationWrap.trailingAnchor constraintLessThanOrEqualToAnchor:_thumb.trailingAnchor constant:-kIMBadgeInset],
            [_metaWrap.trailingAnchor constraintEqualToAnchor:_thumb.trailingAnchor constant:-kIMBadgeInset],
            [_metaWrap.bottomAnchor constraintEqualToAnchor:_thumb.bottomAnchor constant:-kIMBadgeInset],
            [_metaWrap.leadingAnchor constraintGreaterThanOrEqualToAnchor:_thumb.leadingAnchor constant:kIMBadgeInset],
        ]];
        [self applyAlignmentMine:NO showName:NO];
    }
    return self;
}

/// 靠**优先级**切换左右贴边与顶部锚点（四条约束始终激活）。生效侧 999，让位侧最低优先级。
- (void)applyAlignmentMine:(BOOL)mine showName:(BOOL)showName {
    const UILayoutPriority on = UILayoutPriorityRequired - 1, off = UILayoutPriorityFittingSizeLevel;
    _leading.priority = mine ? off : on;
    _trailing.priority = mine ? on : off;
    _thumbTopPlain.priority = showName ? off : on;
    _thumbTopUnderName.priority = showName ? on : off;
}

/// 进度环的一层（底环/进度环）：路径固定在 kIMDownloadRingSide 见方的局部坐标里，随 _ringWrap 居中锚 _thumb（无需手动摆位）。
- (CAShapeLayer *)makeRingLayerWithColor:(UIColor *)color rounded:(BOOL)rounded {
    CGFloat r = kIMDownloadRingSide / 2 - 3;
    UIBezierPath *circle = [UIBezierPath bezierPathWithArcCenter:CGPointMake(kIMDownloadRingSide / 2, kIMDownloadRingSide / 2)
                                                          radius:r startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.path = circle.CGPath;
    layer.fillColor = UIColor.clearColor.CGColor;
    layer.strokeColor = color.CGColor;
    layer.lineWidth = 3;
    if (rounded) { layer.lineCap = kCALineCapRound; layer.strokeEnd = 0; }
    layer.frame = CGRectMake(0, 0, kIMDownloadRingSide, kIMDownloadRingSide);
    layer.hidden = YES;
    [_ringWrap.layer addSublayer:layer];
    return layer;
}

/// 造一个「半透明黑底 + 白字」的悬浮角标胶囊（浅色图上也读得清，不靠文字阴影）。
- (UIView *)makeBadgeWrapWithLabel:(UILabel *__strong *)outLabel {
    UIView *wrap = [UIView new];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    wrap.backgroundColor = IMTheme.mediaBadgeBackground;
    wrap.layer.cornerRadius = kIMBadgeHeight / 2;
    wrap.layer.cornerCurve = kCACornerCurveContinuous;
    wrap.hidden = YES;
    wrap.userInteractionEnabled = NO;
    [self.contentView addSubview:wrap];

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    label.textColor = IMTheme.mediaBadgeText;
    label.lineBreakMode = NSLineBreakByTruncatingTail; // 极端宽高比：裁剪而非溢出气泡
    [wrap addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [wrap.heightAnchor constraintEqualToConstant:kIMBadgeHeight],
        [label.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:6],
        [label.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-6],
        [label.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor],
    ]];
    *outLabel = label;
    return wrap;
}

#pragma mark - 配置

- (void)configureWithMessage:(IMMessageModel *)message
                     fullURL:(NSString *)fullURL
                   posterURL:(NSString *)posterURL
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                previewImage:(UIImage *)preview
                  senderName:(NSString *)senderName
                  senderRole:(IMGroupRole)senderRole {
    BOOL isVideo = [message.contentType isEqualToString:@"video"];
    _thumb.layer.cornerRadius = IMTheme.radiusBubble;
    _senderLabel.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 4) weight:UIFontWeightSemibold];
    _url = fullURL;
    BOOL showName = senderName.length > 0;
    [self applySenderName:senderName role:senderRole toNameLabel:_senderLabel];
    _senderLabel.hidden = !showName;
    [self applyAlignmentMine:mine showName:showName];
    _thumb.image = preview; // 本地预览先行（上传中/防闪）；无预览为 nil 占位灰底
    _isVideoCell = isVideo;
    _playBadge.image = IMCenterBadgeImage(@"play.circle.fill"); // 复用期可能残留上传态图标，先还原
    _playBadge.hidden = !isVideo;
    _progressWrap.hidden = YES;
    _progressWrap.backgroundColor = IMTheme.mediaBadgeBackground;
    _ringBG.hidden = YES; _ring.hidden = YES; // 非门控态无进度环（复用残留清掉）
    _thumb.isAccessibilityElement = NO; _thumb.accessibilityLabel = nil;

    [self applyDisplaySizeForMessage:message preview:preview posterURL:posterURL fullURL:fullURL isVideo:isVideo];
    [self applyDurationBadge:(isVideo ? message.duration : 0)];
    [self applyMetaBadgeForMessage:message mine:mine peerReadSeq:peerReadSeq];
    // 发送失败：缩略图左侧红❗（仅自己）。与文本气泡一致——此前媒体消息完全没有这个标记。
    BOOL failed = mine && message.status == IMMessageStatusFailed;
    _failBadge.hidden = !failed;
    _failBadgeTrailing.active = failed;
    // 被拒收系统行（如非好友 200103）：媒体消息此前无处承载 note，被拒后既无文案也无恢复入口。
    [_sysNote configureWithNote:message.note code:message.noteCode];
    BOOL hasNote = _sysNote.hasContent;
    // 图说 caption（Telegram 模型）：图文/视频文的随附文本，缩略图下方。iOS 只显示（不发送）。
    NSString *caption = message.caption.length > 0 ? message.caption : nil;
    BOOL hasCaption = caption != nil;
    // ④ 图说整体化：有 caption 时套气泡底（我方绿 / 对方白），媒体只圆上角、caption 落此底成一整块；
    // caption 字色随气泡（可读）——须先定字色再烘 attributedText，否则 @高亮那段会用到旧色。
    UIColor *capColor = mine ? IMTheme.bubbleMeText : UIColor.labelColor;
    if (hasCaption) {
        // 配文 @高亮（Telegram 模型，仅群聊）：复用文本气泡的 attributedContent，命中的 @昵称/@所有人 上强调色。
        _captionLabel.textColor = capColor;
        NSDictionary *capBase = @{ NSFontAttributeName: _captionLabel.font, NSForegroundColorAttributeName: capColor };
        _captionLabel.attributedText = [IMBubbleCell attributed:[IMBubbleCell attributedContent:caption base:capBase mentionColor:IMTheme.accent mentions:self.captionMentionMap]
                                                   highlighting:self.searchHighlightKeyword];
    } else {
        _captionLabel.attributedText = nil;
        _captionLabel.text = nil;
    }
    _captionLabel.hidden = !hasCaption;
    _captionBG.hidden = !hasCaption;
    if (hasCaption) {
        _captionBG.backgroundColor = mine ? IMTheme.bubbleMe : IMTheme.bubbleThem;
        _thumb.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner; // 只圆上两角，下边贴进 caption 区
        [NSLayoutConstraint activateConstraints:_captionBGConstraints];
    } else {
        _thumb.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner; // 四角圆（纯媒体）
        [NSLayoutConstraint deactivateConstraints:_captionBGConstraints];
    }
    // 底部链按 (hasCaption × hasNote) 组合切换：thumb →[caption]→[note]→ cell 底，且恒有唯一一条“贴底”。
    _thumbBottom.active = !hasCaption && !hasNote;
    _captionTop.active = hasCaption;
    _captionBottom.active = hasCaption && !hasNote;
    _noteTop.active = hasNote && !hasCaption;
    _noteTopUnderCaption.active = hasNote && hasCaption;
    _noteBottom.active = hasNote;

    [self hideExpiredOverlay]; // 复用防残留：先清掉上一条的失效层
    if (fullURL.length == 0) { return; } // 尚未上传完成：只显本地预览，不发起网络加载
    __weak typeof(self) ws = self;
    NSString *want = fullURL;
    void (^apply)(UIImage *) = ^(UIImage *image) {
        __strong typeof(ws) self = ws;
        if (!self || !image || ![self->_url isEqualToString:want]) { return; } // 复用安全
        self->_thumb.image = image;
        // 尺寸原先未知（老消息/无预览）→ 用真实图重排一次，避免长图被塞进方框。
        if (!self->_sizeFromMedia) { [self resizeToImageSize:image.size]; }
    };
    // 被动展示失效（草图 §03）：加载成功 → apply；失败 → 复验 404，命中则画失效占位（非透明）。
    // 视频虽加载的是 posterURL，但**复验/登记一律用内容 full URL（want）**——与相册/媒体库/查看器统一 key
    // （code-review #1/#3）。故 poster 单删而视频还在时不判失效（内容可取），仅缺缩略图；ops 通常整条 uploads
    // 一起删，poster 与视频同亡 → full 404 → 正常判失效。
    void (^applyOrVerify)(UIImage *) = ^(UIImage *image) {
        __strong typeof(ws) self = ws;
        if (!self || ![self->_url isEqualToString:want]) { return; }
        if (image) { apply(image); return; }
        [IMMediaExpiryRegistry.shared verifyExpiredForURL:want completion:^(BOOL expired) {
            __strong typeof(ws) self2 = ws;
            if (!self2 || !expired || ![self2->_url isEqualToString:want]) { return; }
            [self2 showExpiredForVideo:isVideo message:message];
        }];
    };
    // 门控（M4-7）：收到的媒体按策略"未下载"——中心 ↓（下载中为环形 + ⏸）+ 尺寸角标，点击触发下载。
    // 占位图源：**一律优先显示随消息内嵌的极小模糊缩略 thumb**（~1KB、免额外下载、天然"糊"符合未下载占位语义），
    // 图片、视频一视同仁。此前视频走 `isVideo && poster` 优先取服务器封面，使内嵌 thumb 对**带封面的视频**
    // 成了死代码 —— 视频必现不显示模糊占位（本次修复的根因）。现改为 thumb 优先，仅当无 thumb（老消息）才回退封面。
    if (self.gated) {
        [self applyGatedBadgesForMessage:message isVideo:isVideo];
        BOOL hasThumb = message.thumb.length > 0;
        IMLogDebugWithTag(IMLogTagMedia, @"media_gated_render conv=%@ seq=%lld is_video=%d has_thumb=%d source=%@",
                          message.convID ?: @"", message.convSeq, isVideo, hasThumb, hasThumb ? @"thumb" : @"none");
        if (hasThumb) {
            UIImage *cachedFrost = [IMMediaPlaceholder cachedFrostedForThumb:message.thumb];
            if (cachedFrost) {
                _thumb.image = cachedFrost; // 命中缓存：同步上磨砂图，无闪烁、不据它重排尺寸
            } else {
                [IMMediaPlaceholder frostedForThumb:message.thumb completion:^(UIImage *blurred) {
                    __strong typeof(ws) self = ws;
                    if (!self || !blurred || ![self->_url isEqualToString:want]) {
                        IMLogWarnWithTag(IMLogTagMedia, @"media_gated_thumb_dropped seq=%lld reason=%@",
                                         message.convSeq, (blurred == nil ? @"decode_fail" : @"cell_reused"));
                        return;
                    }
                    self->_thumb.image = blurred; // 磨砂占位（~20px 放大 + 高斯），不据它重排尺寸
                }];
            }
        }
        // 无 thumb（极老消息）：留 init 的中性灰底（方案 A·纯净门控——绝不为占位联网拉封面/原图）。
        return;
    }
    // 已知失效：直接画失效占位、不再回源（掐 404 风暴）。
    if ([IMMediaExpiryRegistry.shared isExpiredURL:fullURL]) {
        [self showExpiredForVideo:isVideo message:message];
        return;
    }
    if (!isVideo) {
        [[IMImageLoader shared] loadImageURL:fullURL completion:applyOrVerify];
    } else if (posterURL.length > 0) {
        [[IMImageLoader shared] loadImageURL:posterURL completion:applyOrVerify]; // 封面是普通 JPEG，走图片缓存
    } else {
        // 没有封面（老消息/发送端抓帧失败）才回退抽帧——代价是要拉远端视频的一段数据。
        [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:fullURL completion:applyOrVerify];
    }
}

/// 失效占位（被动展示 404）：保留磨砂 thumb 作 dim 底（有则显，无则中性灰底）、去中心播放/进度键、叠加 ⊘+文案层。
- (void)showExpiredForVideo:(BOOL)isVideo message:(IMMessageModel *)message {
    _playBadge.hidden = YES;
    _progressWrap.hidden = YES; _ringBG.hidden = YES; _ring.hidden = YES;
    if (message.thumb.length > 0) {
        UIImage *cached = [IMMediaPlaceholder cachedFrostedForThumb:message.thumb];
        if (cached) {
            _thumb.image = cached;
        } else {
            __weak typeof(self) ws = self;
            NSString *want = _url;
            [IMMediaPlaceholder frostedForThumb:message.thumb completion:^(UIImage *blurred) {
                __strong typeof(ws) self = ws;
                if (self && blurred && [self->_url isEqualToString:want]) { self->_thumb.image = blurred; }
            }];
        }
    }
    [self showExpiredOverlayWithCaption:(isVideo ? @"视频已失效" : @"图片已失效")];
}

- (void)showExpiredOverlayWithCaption:(NSString *)caption {
    [_expiredOverlay removeFromSuperview];
    _expiredOverlay = [IMMediaPlaceholder expiredOverlayWithCaption:caption];
    _expiredOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    _expiredOverlay.layer.cornerRadius = IMTheme.radiusBubble;
    _expiredOverlay.clipsToBounds = YES;
    [self.contentView addSubview:_expiredOverlay];
    [NSLayoutConstraint activateConstraints:@[
        [_expiredOverlay.leadingAnchor constraintEqualToAnchor:_thumb.leadingAnchor],
        [_expiredOverlay.trailingAnchor constraintEqualToAnchor:_thumb.trailingAnchor],
        [_expiredOverlay.topAnchor constraintEqualToAnchor:_thumb.topAnchor],
        [_expiredOverlay.bottomAnchor constraintEqualToAnchor:_thumb.bottomAnchor],
    ]];
}

- (void)hideExpiredOverlay {
    [_expiredOverlay removeFromSuperview];
    _expiredOverlay = nil;
}

/// 门控态的中心圆钮 + 左上角角标 + 进度环（草图 §02/§03 的五态）。configure 时记住尺寸/时长，
/// 之后进度就地更新（`updateDownloadProgress:`）复用同一份渲染，无需重传 message、无需 reload。
- (void)applyGatedBadgesForMessage:(IMMessageModel *)message isVideo:(BOOL)isVideo {
    _gatedSizeBytes = message.fileSize;
    _gatedDurationText = isVideo ? IMFormatMediaDuration(message.duration) : nil;
    [self renderGatedDownloadUI];
}

/// 只依据 `self.downloadProgress` + 记住的尺寸/时长渲染门控 UI。**进度高频回调就走这条**（不碰布局约束、不 reload）。
- (void)renderGatedDownloadUI {
    IMDownloadProgress *dp = self.downloadProgress;
    NSString *symbol = dp ? IMDownloadCenterSymbolName(dp) : @"arrow.down.circle.fill";
    // symbol 为 nil 只可能是「失败·文件已失效」（服务端已清理）→ 不给按钮，无从重试（草图 §02-B）。
    _playBadge.image = symbol ? IMCenterBadgeImage(symbol) : nil;
    _playBadge.hidden = symbol == nil;
    if (!_playBadge.hidden) { [self.contentView bringSubviewToFront:_playBadge]; }
    // VoiceOver：门控卡片整体读作可点的下载按钮（草图 §08-09）。
    _thumb.isAccessibilityElement = YES;
    _thumb.accessibilityTraits = UIAccessibilityTraitButton;
    _thumb.accessibilityLabel = dp ? [dp accessibilityText]
        : (_gatedSizeBytes > 0 ? [NSString stringWithFormat:@"下载，%@", IMFormatFileSize(_gatedSizeBytes)] : @"下载");

    // 左上角单块角标（防溢出：进度与时长不再各占一块）：
    //   未下载 = 「时长 · 大小」（时长在前）；下载中/暂停 = 只显进度（**藏时长**，腾出空间）；失败 = 失败文案。
    NSString *sizeText = _gatedSizeBytes > 0 ? IMFormatFileSize(_gatedSizeBytes) : nil;
    BOOL active = dp && dp.phase != IMDownloadPhaseNotStarted; // 下载中/暂停/失败
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (active) {
        NSString *st = [dp displayText];
        if (st.length > 0) { [parts addObject:st]; } // 下载中/暂停/失败：只状态，不并时长
    } else {
        if (_gatedDurationText.length > 0) { [parts addObject:_gatedDurationText]; } // 未下载：时长在前
        if (sizeText.length > 0) { [parts addObject:sizeText]; }
    }
    _progressLabel.text = [parts componentsJoinedByString:@" · "];
    _progressWrap.hidden = parts.count == 0;
    _progressWrap.backgroundColor = (dp.phase == IMDownloadPhaseFailed) ? IMTheme.danger : IMTheme.mediaBadgeBackground;
    _durationWrap.hidden = YES; // 与左上角胶囊互斥（时长已并入其中）
    if (!_progressWrap.hidden) { [self.contentView bringSubviewToFront:_progressWrap]; }

    BOOL showRing = dp.phase == IMDownloadPhaseDownloading || dp.phase == IMDownloadPhasePaused;
    _ringBG.hidden = !showRing;
    _ring.hidden = !showRing;
    if (showRing) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES]; // 高频进度回调不做隐式动画
        _ring.strokeEnd = MAX(0.02, dp.fraction); // 0% 也露一点头，可感知"在动"
        [CATransaction commit];
    }
}

/// 进度**就地更新**（M4-7）：宿主在 onProgress 高频回调里调用——只改中心图标/角标/环，
/// 不重配 cell、不 reloadRows（避免主线程卡死 + 自适应高度图片行跳变）。仅门控态有意义。
- (void)updateDownloadProgress:(IMDownloadProgress *)dp {
    if (!self.gated) { return; }
    self.downloadProgress = dp;
    [self renderGatedDownloadUI];
}

/// 缩略图显示尺寸：协议下发的 media_w/h 最权威 → 本地预览图 → 已缓存的图/封面 → 未知回退方块。
- (void)applyDisplaySizeForMessage:(IMMessageModel *)message preview:(UIImage *)preview
                         posterURL:(NSString *)posterURL fullURL:(NSString *)fullURL isVideo:(BOOL)isVideo {
    CGSize pixels = CGSizeMake(message.mediaW, message.mediaH);
    if (pixels.width <= 0 || pixels.height <= 0) {
        UIImage *known = preview ?: [self cachedImageForURL:(isVideo && posterURL.length > 0 ? posterURL : fullURL)
                                                    isVideo:(isVideo && posterURL.length == 0)];
        pixels = known ? CGSizeMake(known.size.width * known.scale, known.size.height * known.scale) : CGSizeZero;
    }
    _sizeFromMedia = pixels.width > 0 && pixels.height > 0;
    CGSize box = [IMImageCell maxBox];
    CGSize shown = IMMediaDisplaySize(pixels.width, pixels.height, box, kIMMediaMinSide);
    _thumbWidth.constant = shown.width;
    _thumbHeight.constant = shown.height;
}

/// 异步出图后按真实尺寸重排（仅在尺寸原本未知时走这条；已有 media_w/h 不会跳版）。
- (void)resizeToImageSize:(CGSize)size {
    CGSize shown = IMMediaDisplaySize(size.width, size.height, [IMImageCell maxBox], kIMMediaMinSide);
    if (fabs(shown.width - _thumbWidth.constant) < 1 && fabs(shown.height - _thumbHeight.constant) < 1) { return; }
    _thumbWidth.constant = shown.width;
    _thumbHeight.constant = shown.height;
    _sizeFromMedia = YES;
    // 必须延到下一轮 runloop：IMVideoThumbnailLoader 命中缓存时是**同步**回调，本方法可能正跑在
    // cellForRowAtIndexPath 内部，此时回调聊天页会重入 tableView 的 beginUpdates/endUpdates。
    void (^resolved)(CGSize) = self.onMediaSizeResolved;
    if (resolved) { dispatch_async(dispatch_get_main_queue(), ^{ resolved(size); }); }
}

+ (CGSize)maxBox {
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    return CGSizeMake(MIN(kIMMediaMaxWidth, screenW * 0.62), kIMMediaMaxHeight);
}

- (UIImage *)cachedImageForURL:(NSString *)fullURL isVideo:(BOOL)isVideo {
    if (fullURL.length == 0) { return nil; }
    return isVideo ? [[IMVideoThumbnailLoader shared] cachedPosterForURL:fullURL]
                   : [[IMImageLoader shared] cachedImageForURL:fullURL];
}

- (void)applyDurationBadge:(int64_t)durationMillis {
    NSString *text = IMFormatMediaDuration(durationMillis);
    _durationLabel.text = text;
    _durationWrap.hidden = text.length == 0;
    if (!_durationWrap.hidden) { [self.contentView bringSubviewToFront:_durationWrap]; }
}

/// 右下角：时间 +（自己消息）✓ 已送达 / ✓✓ 已读。发送中/失败沿用气泡的文案口径。
- (void)applyMetaBadgeForMessage:(IMMessageModel *)message mine:(BOOL)mine peerReadSeq:(int64_t)peerReadSeq {
    NSString *time = [IMTheme timeStringFromMillis:message.timestamp] ?: @"";
    _timeText = time;
    UIColor *base = IMTheme.mediaBadgeText;
    if (!mine) {
        [self setMetaText:time checks:nil checkColor:base];
        return;
    }
    if (message.status == IMMessageStatusSending) {
        [self setMetaText:@"发送中…" checks:nil checkColor:base];
        return;
    }
    if (message.status == IMMessageStatusFailed) {
        [self setMetaText:(message.note.length > 0 ? time : @"未发送 ✗") checks:nil checkColor:base];
        return;
    }
    if (message.convSeq > 0) { // 拿到 conv_seq 即已送达，再按对端已读位点决定单勾/双勾
        BOOL read = message.convSeq <= peerReadSeq;
        [self setMetaText:time checks:(read ? @"✓✓" : @"✓")
               checkColor:(read ? IMTheme.mediaBadgeCheckRead : base)];
        return;
    }
    [self setMetaText:time checks:nil checkColor:base];
}

- (void)setMetaText:(NSString *)text checks:(NSString *)checks checkColor:(UIColor *)checkColor {
    NSString *plain = checks.length == 0 ? text
                    : (text.length > 0 ? [NSString stringWithFormat:@"%@ %@", text, checks] : checks);
    NSDictionary *attrs = @{ NSFontAttributeName: _metaLabel.font, NSForegroundColorAttributeName: IMTheme.mediaBadgeText };
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:plain attributes:attrs];
    if (checks.length > 0) {
        NSRange r = [plain rangeOfString:checks options:NSBackwardsSearch];
        if (r.location != NSNotFound) { [s addAttribute:NSForegroundColorAttributeName value:checkColor range:r]; }
    }
    _metaLabel.attributedText = s;
    _metaWrap.hidden = plain.length == 0;
    if (!_metaWrap.hidden) { [self.contentView bringSubviewToFront:_metaWrap]; }
}

#pragma mark - 上传进度

/// 上传状态机的中心按钮图标（占播放按钮的位置，上传完成前视频本来也不能播）：
///   排队/压缩 → ✕（取消发送）；上传中(可暂停) → ⏸；已暂停 → ↑（点击继续**上**传，与将来下载的 ↓ 呼应）；
///   失败 → ↻（点击重试）；一次性小上传 → 不显按钮（几秒传完，无暂停价值）。
static NSString *IMUploadCenterSymbol(IMUploadProgress *p) {
    if (p.failed) { return @"arrow.clockwise.circle.fill"; }
    if (p.phase == IMUploadPhaseQueued || p.phase == IMUploadPhaseTranscoding) { return @"xmark.circle.fill"; }
    if (!p.pausable) { return nil; }
    return p.pausedByUser ? @"arrow.up.circle.fill" : @"pause.circle.fill";
}

static UIImage *IMCenterBadgeImage(NSString *symbolName) {
    return [UIImage systemImageNamed:symbolName
                   withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightRegular]];
}

- (void)setUploadProgress:(IMUploadProgress *)progress {
    if (self.gated) { return; } // 门控态（收到的未下载图）：中心 ↓ + 尺寸角标由 configure 布好，勿被上传态复位覆盖
    if (progress == nil) {                       // 不在上传中：恢复时长角标与（视频的）播放按钮
        _progressWrap.hidden = YES;
        _progressWrap.backgroundColor = IMTheme.mediaBadgeBackground;
        _durationWrap.hidden = _durationLabel.text.length == 0;
        _playBadge.image = IMCenterBadgeImage(@"play.circle.fill");
        _playBadge.hidden = !_isVideoCell;
        return;
    }
    _durationWrap.hidden = YES;                  // 与时长角标互斥（同占左上角）
    _progressWrap.hidden = NO;
    _progressWrap.backgroundColor = progress.failed ? IMTheme.danger : IMTheme.mediaBadgeBackground;
    BOOL paused = progress.pausedByUser && !progress.failed;
    if (paused) {
        // 暂停态：小 ⏸ 图标 + 字节数——不用「已暂停」文本（国际化后文案长度不可控，图标零成本）。
        UIImage *icon = [[UIImage systemImageNamed:@"pause.fill"
                                 withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:9 weight:UIImageSymbolWeightBold]]
                         imageWithTintColor:IMTheme.mediaBadgeText renderingMode:UIImageRenderingModeAlwaysOriginal];
        NSTextAttachment *att = [NSTextAttachment new];
        att.image = icon;
        att.bounds = CGRectMake(0, (_progressLabel.font.capHeight - 9) / 2.0, 9, 9);
        NSMutableAttributedString *s = [[NSAttributedString attributedStringWithAttachment:att] mutableCopy];
        [s appendAttributedString:[[NSAttributedString alloc]
            initWithString:[@" " stringByAppendingString:[progress displayText]]
                attributes:@{ NSFontAttributeName: _progressLabel.font,
                              NSForegroundColorAttributeName: IMTheme.mediaBadgeText }]];
        _progressLabel.attributedText = s;
    } else {
        _progressLabel.text = [progress displayText];
    }
    // 右下角只在**真正传输**时显「发送中…」；暂停时回落为时间（configure 按 status=sending 写死了发送中）。
    if (!progress.failed) {
        [self setMetaText:(paused ? (_timeText ?: @"") : @"发送中…") checks:nil checkColor:IMTheme.mediaBadgeText];
    }
    [self.contentView bringSubviewToFront:_progressWrap];
    NSString *symbol = IMUploadCenterSymbol(progress);
    if (symbol) {
        _playBadge.image = IMCenterBadgeImage(symbol);
        _playBadge.hidden = NO;
        [self.contentView bringSubviewToFront:_playBadge];
    } else {
        _playBadge.hidden = YES;
    }
}

#pragma mark -

- (void)tapped {
    if (self.gated) { if (self.onDownloadTap) { self.onDownloadTap(); } return; } // 门控态点击=下载
    if (_onTap) { _onTap(_thumb.image); }
}

/// 表级点击命中判断（IMBubbleHitTesting）：缩略图本体 + 图说气泡（有 caption 时整卡都算气泡，
/// 否则点 caption 文字区被当"气泡外"直接吞掉，引用跳转等表级交互失效——code-review 2026-08-19）。
- (BOOL)pointInsideBubble:(CGPoint)pointInCell {
    if (_thumb && !_thumb.hidden && CGRectContainsPoint([_thumb convertRect:_thumb.bounds toView:self], pointInCell)) { return YES; }
    return _captionBG && !_captionBG.hidden && CGRectContainsPoint([_captionBG convertRect:_captionBG.bounds toView:self], pointInCell);
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
    _thumb.image = nil; _playBadge.hidden = YES;
    _progressWrap.hidden = YES; _progressWrap.backgroundColor = IMTheme.mediaBadgeBackground;
    _durationWrap.hidden = YES; _durationLabel.text = nil;
    _metaWrap.hidden = YES; _metaLabel.attributedText = nil;
    _senderLabel.hidden = YES; _senderLabel.text = nil;
    [self applyAlignmentMine:NO showName:NO];
    _thumbWidth.constant = kIMMediaFallbackSide; _thumbHeight.constant = kIMMediaFallbackSide;
    _sizeFromMedia = NO;
    _avatar.hidden = YES; _leading.constant = 12;
    _onTap = nil; _onMediaSizeResolved = nil;
    // onAvatarTap / 头像与分割线的复位由 IMMessageCell 基类 prepareForReuse 统一处理。
    _ringBG.hidden = YES; _ring.hidden = YES; _ring.strokeEnd = 0;
    _gatedSizeBytes = 0; _gatedDurationText = nil;
    [self hideExpiredOverlay];
    self.gated = NO; self.downloadProgress = nil; self.onDownloadTap = nil;
}

- (UIView *)previewTargetView { return _thumb; }

/// 图说整体化：caption 区（气泡底）也要能长按弹菜单——缩略图区由 previewTargetView(_thumb) 承载，
/// 文字区由这层 _captionBG 承载（无 caption 时它 hidden，不接触摸、不弹菜单）。
- (UIView *)secondaryMenuTargetView { return _captionBG; }

/// 长按预览统一到整卡：有 caption（_captionBG 可见）→ 预览整张卡片；否则预览缩略图本体。
- (UIView *)menuPreviewTargetView { return (_captionBG && !_captionBG.hidden) ? _captionBG : _thumb; }

/// 图说 caption 的 @昵称 点击命中（cell 坐标系）：复用 IMBubbleCell 的 TextKit 反查。命中返回 uid。
- (NSString *)mentionUIDAtPoint:(CGPoint)pointInCell {
    return [IMBubbleCell mentionUIDInLabel:_captionLabel atPoint:[self convertPoint:pointInCell toView:_captionLabel]];
}

+ (CGFloat)displayHeightForPixelWidth:(CGFloat)pixelW pixelHeight:(CGFloat)pixelH {
    if (pixelW <= 0 || pixelH <= 0) { return kIMMediaFallbackSide; }
    return IMMediaDisplaySize(pixelW, pixelH, [IMImageCell maxBox], kIMMediaMinSide).height;
}

@end
