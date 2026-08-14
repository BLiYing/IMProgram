//  IMMediaTileCell.m

#import "IMMediaTileCell.h"
#import "IMDownloadProgress.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaPlaceholder.h" // 磨砂占位统一渲染器（三处共用）

@implementation IMMediaTileCell {
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
