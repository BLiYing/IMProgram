//  IMMediaTileCell.m

#import "IMMediaTileCell.h"
#import "IMMediaFormat.h" // IMFormatMediaDuration
#import "IMDownloadProgress.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaPlaceholder.h" // 磨砂占位统一渲染器（三处共用）
#import "IMMediaExpiryRegistry.h" // 失效登记：据此显 ⊘（只读本地、不联网探测）
#import "IMOriginalVideoCache.h"  // 铁律 A：本机有原件则照显真图、不叠失效

@implementation IMMediaTileCell {
    UIImageView *_thumb; UIImageView *_play; NSString *_url;
    UIView *_dim; CAShapeLayer *_ringBG; CAShapeLayer *_ring; UILabel *_sizeChip; UILabel *_durChip;
    UIImageView *_expiredBadge; // 中心 ⊘（曾可用、被服务端清理）
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

        _ringBG = [IMMediaTileCell ringLayerWithColor:[UIColor colorWithWhite:1 alpha:0.32] rounded:NO];
        _ring = [IMMediaTileCell ringLayerWithColor:UIColor.whiteColor rounded:YES];
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
        _durChip = [UILabel new];
        _durChip.font = [UIFont monospacedDigitSystemFontOfSize:9 weight:UIFontWeightMedium];
        _durChip.textColor = UIColor.whiteColor;
        _durChip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        _durChip.textAlignment = NSTextAlignmentCenter;
        _durChip.layer.cornerRadius = 7; _durChip.clipsToBounds = YES;
        _durChip.hidden = YES;
        [self.contentView addSubview:_durChip]; // 就绪视频格右下角时长角标

        _expiredBadge = [[UIImageView alloc] initWithImage:[IMMediaPlaceholder expiredGlyphImage]];
        _expiredBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _expiredBadge.hidden = YES;
        [self.contentView addSubview:_expiredBadge];
        [NSLayoutConstraint activateConstraints:@[
            [_expiredBadge.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_expiredBadge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
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
    if (!_durChip.hidden) {
        CGSize ds = [_durChip sizeThatFits:CGSizeMake(CGFLOAT_MAX, 14)];
        CGFloat dw = ds.width + 8;
        _durChip.frame = CGRectMake(self.bounds.size.width - dw - 3, self.bounds.size.height - 14 - 3, dw, 14);
    }
    if (_ring.hidden && _ringBG.hidden) { return; }
    CGRect f = CGRectMake((self.bounds.size.width - 34) / 2, (self.bounds.size.height - 34) / 2, 34, 34);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _ringBG.frame = f; _ring.frame = f;
    [CATransaction commit];
}

- (void)configureWithItem:(IMMediaItem *)item download:(IMDownloadProgress *)dp thumb:(NSString *)thumb {
    _url = item.url; _thumb.image = nil;
    __weak typeof(self) ws = self; NSString *want = item.url;
    void (^applyFrost)(NSString *) = ^(NSString *t) {
        if (t.length == 0) { return; }
        __strong typeof(ws) sself = ws;
        if (!sself) { return; }
        UIImage *cached = [IMMediaPlaceholder cachedFrostedForThumb:t];
        if (cached) { sself->_thumb.image = cached; return; }
        [IMMediaPlaceholder frostedForThumb:t completion:^(UIImage *blurred) {
            __strong typeof(ws) s2 = ws;
            if (s2 && blurred && [s2->_url isEqualToString:want]) { s2->_thumb.image = blurred; }
        }];
    };

    // 失效（曾可用、被服务端清理）**且本机无原件**（铁律 A：缓存过的照显真图，不叠 ⊘）→ dim 磨砂 + ⊘，无下载/播放入口。
    BOOL hasLocal = item.isVideo ? [IMOriginalVideoCache hasCacheForFullURL:item.url]
                                 : [[IMImageLoader shared] hasCachedImageForURL:item.url];
    BOOL expired = !hasLocal && [IMMediaExpiryRegistry.shared isExpiredURL:item.url];
    if (expired) {
        [self applyGate:nil isVideo:NO]; // 清掉门控层（环/尺寸/播放键）
        _play.hidden = YES;
        _expiredBadge.hidden = NO;
        _durChip.hidden = YES;
        _thumb.alpha = 0.5;
        applyFrost(thumb);
        return;
    }
    _expiredBadge.hidden = YES;
    _thumb.alpha = 1.0;

    BOOL gated = dp != nil && dp.phase != IMDownloadPhaseDone;
    void (^apply)(UIImage *) = ^(UIImage *img) {
        __strong typeof(ws) self = ws;
        if (self && [self->_url isEqualToString:want]) { self->_thumb.image = img; }
    };
    [self applyGate:gated ? dp : nil isVideo:item.isVideo];
    // 就绪视频格右下角时长角标（有 duration 时；门控/失效态不显）。
    NSString *durText = (item.isVideo && !gated && item.durationMillis > 0) ? IMFormatMediaDuration(item.durationMillis) : nil;
    _durChip.text = durText; _durChip.hidden = durText.length == 0; [self setNeedsLayout];
    if (gated) {
        // 门控格不拉原图/封面（方案 A·纯净门控）：只把内嵌 thumb 过高斯磨砂显示，与聊天气泡同款；无 thumb 留灰底。
        applyFrost(thumb);
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
    _thumb.alpha = 1.0;
    _expiredBadge.hidden = YES;
    [self applyGate:nil isVideo:NO];
}
@end
