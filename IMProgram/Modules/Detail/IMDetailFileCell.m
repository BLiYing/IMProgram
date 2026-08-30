//  IMDetailFileCell.m

#import "IMDetailFileCell.h"
#import "IMMessageModel.h"
#import "IMDownloadProgress.h"
#import "IMMediaUtil.h"       // IMFileTypeIconForName / IMFormatFileSize
#import "IMTheme.h"

@implementation IMDetailFileCell {
    UIImageView *_icon; UIImageView *_glyph; CAShapeLayer *_ringBG; CAShapeLayer *_ring;
    CAShapeLayer *_disc;       // 未下载态：与圆环同心同径的 accent 实心圆底（与聊天页文件气泡同款）
    UILabel *_title; UILabel *_sub; UILabel *_meta; UILabel *_source;
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

        _meta = [UILabel new]; // 静态元信息行：年月日时分（详情页与收藏页同口径）
        _meta.font = [UIFont systemFontOfSize:12];
        _meta.textColor = IMTheme.textTertiary;
        _meta.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_meta];

        // 「来自X」独占一行（accent，与链接分类的来源行同色）——收藏页才有值，详情页恒空。
        // 曾与时间挤在同一行「来自X · 年月日时分」：备注名/群昵称一长就把时间截没（用户反馈）。
        _source = [UILabel new];
        _source.font = [UIFont systemFontOfSize:12];
        _source.textColor = IMTheme.accent;
        _source.lineBreakMode = NSLineBreakByTruncatingTail;
        _source.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_source];

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
            [_meta.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
            [_meta.topAnchor constraintEqualToAnchor:_sub.bottomAnchor constant:2],
            [_meta.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            // 来源行不设底部约束：行高由宿主表按"有无来源"固定给（详情 74 / 收藏 92），
            // 若这里再钉一条 bottom<=，详情页无来源时空 label 的 intrinsic 高度可能把它顶破报约束冲突。
            [_source.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
            [_source.topAnchor constraintEqualToAnchor:_meta.bottomAnchor constant:2],
            [_source.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
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
    _meta.text = m.timestamp > 0 ? IMFormatFileDateTime(m.timestamp) : @"";
    _source.text = self.sourceName.length > 0 ? [@"来自" stringByAppendingString:self.sourceName] : nil;
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
    _meta.text = nil; _source.text = nil; self.sourceName = nil;
}
@end
