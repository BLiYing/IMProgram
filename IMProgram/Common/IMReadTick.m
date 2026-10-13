//
//  IMReadTick.m
//

#import "IMReadTick.h"

const CGFloat kIMReadTickGap = 3;

static const CGFloat kViewH = 10;       // viewBox 高
static const CGFloat kSingleW = 13;     // 单勾 viewBox 宽
static const CGFloat kDoubleW = 18;     // 双勾 viewBox 宽
static const CGFloat kStroke = 1.5;
static const CGFloat kDoubleShift = 5;  // 双勾第二笔右移
static const CGFloat kHeightRatio = 0.95; // 图高 = 字号 × 0.95

@implementation IMReadTick

/// 设计稿路径：M1 5.2 L4.4 8.6 L12 1（第二笔整体右移 5），单位 = viewBox。
static UIBezierPath *IMTickPath(BOOL isDouble) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    for (int i = 0; i < (isDouble ? 2 : 1); i++) {
        CGFloat dx = i * kDoubleShift;
        [p moveToPoint:CGPointMake(1 + dx, 5.2)];
        [p addLineToPoint:CGPointMake(4.4 + dx, 8.6)];
        [p addLineToPoint:CGPointMake(12 + dx, 1)];
    }
    p.lineWidth = kStroke;
    p.lineCapStyle = kCGLineCapRound;
    p.lineJoinStyle = kCGLineJoinRound;
    return p;
}

+ (UIImage *)imageDouble:(BOOL)isDouble height:(CGFloat)height {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    CGFloat scale = UIScreen.mainScreen.scale;
    NSString *key = [NSString stringWithFormat:@"%d|%.2f|%.0f", isDouble, height, scale];
    UIImage *hit = [cache objectForKey:key];
    if (hit) { return hit; }

    CGFloat k = height / kViewH;
    CGSize size = CGSizeMake((isDouble ? kDoubleW : kSingleW) * k, height);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = scale;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.blackColor setStroke];
        UIBezierPath *p = IMTickPath(isDouble);
        [p applyTransform:CGAffineTransformMakeScale(k, k)];
        p.lineWidth = kStroke * k;
        [p stroke];
    }];
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [cache setObject:img forKey:key];
    return img;
}

+ (NSAttributedString *)tickAttributedStringRead:(BOOL)read font:(UIFont *)font color:(UIColor *)color {
    CGFloat h = font.pointSize * kHeightRatio;
    UIImage *img = [self imageDouble:read height:h];
    NSTextAttachment *att = [NSTextAttachment new];
    att.image = img;
    att.bounds = CGRectMake(0, 0, ceil(img.size.width), img.size.height); // 宽取整：小数宽会让 UILabel 量出的宽度略窄而截断成「…」 // 底边 = 基线
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithAttributedString:
        [NSAttributedString attributedStringWithAttachment:att]];
    [s addAttributes:@{ NSForegroundColorAttributeName: color, NSFontAttributeName: font }
               range:NSMakeRange(0, s.length)];
    return s;
}

+ (NSAttributedString *)metaWithTime:(NSString *)time read:(BOOL)read font:(UIFont *)font
                           timeColor:(UIColor *)timeColor tickColor:(UIColor *)tickColor {
    NSMutableAttributedString *s = [NSMutableAttributedString new];
    if (time.length > 0) {
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:time attributes:@{
            NSFontAttributeName: font, NSForegroundColorAttributeName: timeColor }]];
        // 末字符后加 kern = 与勾的间距
        [s addAttribute:NSKernAttributeName value:@(kIMReadTickGap) range:NSMakeRange(s.length - 1, 1)];
    }
    [s appendAttributedString:[self tickAttributedStringRead:read font:font color:tickColor]];
    return s;
}

@end

@implementation IMTickMetaView {
    UILabel *_label;
    UIImageView *_tick;
    NSLayoutConstraint *_labelTrailingPlain;
    NSLayoutConstraint *_labelTrailingTick;
    NSLayoutConstraint *_tickWidth;
    NSLayoutConstraint *_tickHeight;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.lineBreakMode = NSLineBreakByClipping; // 宽度差一丝时默认尾部截断会把整段替成「…」
        [_label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self addSubview:_label];
        _tick = [UIImageView new];
        _tick.translatesAutoresizingMaskIntoConstraints = NO;
        _tick.hidden = YES;
        [self addSubview:_tick];

        _labelTrailingPlain = [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor];
        _labelTrailingTick = [_label.trailingAnchor constraintEqualToAnchor:_tick.leadingAnchor constant:-kIMReadTickGap];
        _labelTrailingTick.active = NO;
        _tickWidth = [_tick.widthAnchor constraintEqualToConstant:0];
        _tickHeight = [_tick.heightAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_label.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            _labelTrailingPlain,
            [_tick.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_tick.bottomAnchor constraintEqualToAnchor:_label.lastBaselineAnchor], // 勾底边 = 文字基线
            _tickWidth, _tickHeight,
        ]];
    }
    return self;
}

/// 对外的基线 = 时间文字的基线：外部用 lastBaselineAnchor / firstBaselineAnchor 对齐本视图时（通话记录气泡等）按文字对，
/// 否则 UIView 默认把下边缘当基线，会比旁边的 label 偏低一点。
- (UIView *)viewForFirstBaselineLayout { return _label; }
- (UIView *)viewForLastBaselineLayout { return _label; }

- (NSAttributedString *)attributedText { return _label.attributedText; }
- (void)setAttributedText:(NSAttributedString *)text { [self setAttributedText:text tick:IMReadTickKindNone tickColor:nil]; }

- (void)setAttributedText:(NSAttributedString *)text tick:(IMReadTickKind)kind tickColor:(UIColor *)tickColor {
    _label.attributedText = text;
    BOOL shows = kind != IMReadTickKindNone;
    _tick.hidden = !shows;
    _labelTrailingTick.active = shows;
    _labelTrailingPlain.active = !shows;
    if (shows) {
        UIImage *img = [IMReadTick imageDouble:(kind == IMReadTickKindRead) height:11 * kHeightRatio];
        _tick.image = img;
        _tick.tintColor = tickColor ?: UIColor.grayColor;
        _tickWidth.constant = ceil(img.size.width);
        _tickHeight.constant = img.size.height;
    }
}

@end
