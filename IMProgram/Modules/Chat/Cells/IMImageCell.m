#import "IMImageCell.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMessageModel.h"
#import "IMUploadProgress.h"
#import "IMMediaFormat.h"
#import "UILabel+IMAvatar.h"
#import "IMTheme.h"

/// 气泡最大盒子：宽取 240 与屏宽 62% 的较小者（窄屏也不顶满），高 320（长图不会撑满整屏）。
static const CGFloat kIMMediaMaxWidth = 240;
static const CGFloat kIMMediaMaxHeight = 320;
static const CGFloat kIMMediaMinSide = 80;   // 极端长条的短边下限（保证可点按）
static const CGFloat kIMBadgeInset = 6;      // 角标距缩略图边缘
static const CGFloat kIMBadgeHeight = 18;

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
    UILabel *_avatar;          // 群聊对方头像（连续段末条，贴缩略图底左侧）
    NSLayoutConstraint *_leading;
    NSLayoutConstraint *_trailing;
    NSLayoutConstraint *_thumbWidth;
    NSLayoutConstraint *_thumbHeight;
    NSLayoutConstraint *_thumbTopPlain;      // 无昵称：thumb 贴 cell 顶
    NSLayoutConstraint *_thumbTopUnderName;  // 有昵称：thumb 挂昵称下方
    NSString *_url;
    BOOL _sizeFromMedia;       // YES=尺寸来自协议/预览（权威），加载出图后无需重排
    BOOL _isVideoCell;         // 上传态结束后据此还原中心播放按钮（图片则隐藏）
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

        _progressWrap = [self makeBadgeWrapWithLabel:&_progressLabel];
        _durationWrap = [self makeBadgeWrapWithLabel:&_durationLabel];
        _metaWrap = [self makeBadgeWrapWithLabel:&_metaLabel];

        _senderLabel = [UILabel new];
        _senderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _senderLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _senderLabel.textColor = IMTheme.accent;
        _senderLabel.hidden = YES;
        [self.contentView addSubview:_senderLabel];

        _avatar = [UILabel new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.textColor = UIColor.whiteColor;
        _avatar.textAlignment = NSTextAlignmentCenter;
        _avatar.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _avatar.layer.cornerRadius = 15;
        _avatar.layer.masksToBounds = YES;
        _avatar.hidden = YES;
        [self.contentView addSubview:_avatar];

        // 与 IMAlbumCell 同策略：左右/上下两组约束恒定激活、**靠优先级切换**，杜绝
        // "两条 required 同时生效 → UIKit 打断 width/height" 的自适应行高冲突（真机日志实录）。
        _leading = [_thumb.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_thumb.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        _thumbTopPlain = [_thumb.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3];
        _thumbTopUnderName = [_thumb.topAnchor constraintEqualToAnchor:_senderLabel.bottomAnchor constant:4];
        _thumbWidth = [_thumb.widthAnchor constraintEqualToConstant:kIMMediaFallbackSide];
        _thumbHeight = [_thumb.heightAnchor constraintEqualToConstant:kIMMediaFallbackSide];
        _thumbWidth.priority = UILayoutPriorityRequired - 1;              // 999，让位 Encapsulated-Layout-Width
        _thumbHeight.priority = UILayoutPriorityDefaultHigh + 1;          // 751，让位 Encapsulated-Layout-Height
        [NSLayoutConstraint activateConstraints:@[
            // 恒定边界（required）：无论贴左还是贴右，都不许超出内容区。
            [_thumb.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_thumb.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_thumb.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:3],
            _leading, _trailing, _thumbTopPlain, _thumbTopUnderName,
            [_senderLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_senderLabel.leadingAnchor constraintEqualToAnchor:_thumb.leadingAnchor constant:2],
            [_senderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_avatar.bottomAnchor constraintEqualToAnchor:_thumb.bottomAnchor],
            [_avatar.widthAnchor constraintEqualToConstant:30],
            [_avatar.heightAnchor constraintEqualToConstant:30],
            [_thumb.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
            _thumbWidth, _thumbHeight,
            [_playBadge.centerXAnchor constraintEqualToAnchor:_thumb.centerXAnchor],
            [_playBadge.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
            // 进度与时长共用左上角位置（互斥显示：上传中显进度，传完切回时长）。
            [_progressWrap.leadingAnchor constraintEqualToAnchor:_thumb.leadingAnchor constant:kIMBadgeInset],
            [_progressWrap.topAnchor constraintEqualToAnchor:_thumb.topAnchor constant:kIMBadgeInset],
            [_progressWrap.trailingAnchor constraintLessThanOrEqualToAnchor:_thumb.trailingAnchor constant:-kIMBadgeInset],
            [_durationWrap.leadingAnchor constraintEqualToAnchor:_thumb.leadingAnchor constant:kIMBadgeInset],
            [_durationWrap.topAnchor constraintEqualToAnchor:_thumb.topAnchor constant:kIMBadgeInset],
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
                  senderName:(NSString *)senderName {
    BOOL isVideo = [message.contentType isEqualToString:@"video"];
    _thumb.layer.cornerRadius = IMTheme.radiusBubble;
    _senderLabel.font = [UIFont systemFontOfSize:MAX(12, IMTheme.chatFontSize - 4) weight:UIFontWeightSemibold];
    _url = fullURL;
    BOOL showName = senderName.length > 0;
    _senderLabel.text = senderName;
    _senderLabel.hidden = !showName;
    [self applyAlignmentMine:mine showName:showName];
    _thumb.image = preview; // 本地预览先行（上传中/防闪）；无预览为 nil 占位灰底
    _isVideoCell = isVideo;
    _playBadge.image = IMCenterBadgeImage(@"play.circle.fill"); // 复用期可能残留上传态图标，先还原
    _playBadge.hidden = !isVideo;
    _progressWrap.hidden = YES;

    [self applyDisplaySizeForMessage:message preview:preview posterURL:posterURL fullURL:fullURL isVideo:isVideo];
    [self applyDurationBadge:(isVideo ? message.duration : 0)];
    [self applyMetaBadgeForMessage:message mine:mine peerReadSeq:peerReadSeq];

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
    if (!isVideo) {
        [[IMImageLoader shared] loadImageURL:fullURL completion:apply];
    } else if (posterURL.length > 0) {
        [[IMImageLoader shared] loadImageURL:posterURL completion:apply]; // 封面是普通 JPEG，走图片缓存
    } else {
        // 没有封面（老消息/发送端抓帧失败）才回退抽帧——代价是要拉远端视频的一段数据。
        [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:fullURL completion:apply];
    }
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
    void (^resolved)(void) = self.onMediaSizeResolved;
    if (resolved) { dispatch_async(dispatch_get_main_queue(), resolved); }
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
    NSString *text = [progress displayText];
    if (progress.pausedByUser && !progress.failed) { text = [@"已暂停 · " stringByAppendingString:text]; }
    _progressLabel.text = text;
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

- (void)tapped { if (_onTap) { _onTap(_thumb.image); } }

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
}

@end
