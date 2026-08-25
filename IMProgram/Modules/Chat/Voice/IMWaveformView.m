//
//  IMWaveformView.m
//

#import "IMWaveformView.h"

@implementation IMWaveformView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
        _inactiveColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        _activeColor = [UIColor systemBlueColor];
        _barWidth = 3.0;
        _barSpacing = 2.5;
        _barCornerRadius = 1.5;
    }
    return self;
}

+ (nullable NSArray<NSNumber *> *)amplitudesFromBase64:(NSString *)base64 {
    if (base64.length == 0) { return nil; }
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (data.length == 0) { return nil; }
    const uint8_t *bytes = data.bytes;
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:data.length];
    for (NSUInteger i = 0; i < data.length; i++) {
        float v = MIN(100.f, (float)bytes[i]) / 100.f;
        [out addObject:@(v)];
    }
    return out;
}

- (void)setAmplitudes:(NSArray<NSNumber *> *)amplitudes { _amplitudes = [amplitudes copy]; [self setNeedsDisplay]; }
- (void)setProgress:(CGFloat)progress { _progress = MAX(0, MIN(1, progress)); [self setNeedsDisplay]; }
- (void)setInactiveColor:(UIColor *)c { _inactiveColor = c ?: UIColor.grayColor; [self setNeedsDisplay]; }
- (void)setActiveColor:(UIColor *)c { _activeColor = c ?: UIColor.systemBlueColor; [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGRect bounds = self.bounds;
    if (CGRectGetWidth(bounds) < 4 || CGRectGetHeight(bounds) < 4) { return; }
    CGFloat pitch = self.barWidth + self.barSpacing;
    NSInteger drawableBars = MAX(1, (NSInteger)((CGRectGetWidth(bounds) + self.barSpacing) / pitch));
    NSArray<NSNumber *> *amps = self.amplitudes;
    if (amps.count == 0) {
        // 无波形数据：等高条纹兜底（0.35 归一）。
        NSMutableArray *fill = [NSMutableArray arrayWithCapacity:drawableBars];
        for (NSInteger i = 0; i < drawableBars; i++) { [fill addObject:@0.35]; }
        amps = fill;
    }
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) { return; }
    CGFloat h = CGRectGetHeight(bounds);
    CGFloat minH = 3.0;      // 最低柱高（视觉底噪，防止全黑）
    CGFloat maxH = h - 2.0;  // 上下留 1pt
    CGFloat progressPx = self.progress * CGRectGetWidth(bounds);

    for (NSInteger i = 0; i < drawableBars; i++) {
        // 下采（按 bucket 取最大值，保峰形，与设计文档 §1 收端策略一致）。
        NSInteger lo = (NSInteger)((double)i * amps.count / (double)drawableBars);
        NSInteger hi = MAX(lo + 1, (NSInteger)((double)(i + 1) * amps.count / (double)drawableBars));
        hi = MIN((NSInteger)amps.count, hi);
        float v = 0;
        for (NSInteger j = lo; j < hi; j++) { float av = amps[j].floatValue; if (av > v) { v = av; } }
        CGFloat barH = MAX(minH, v * maxH);
        CGFloat x = i * pitch;
        CGFloat y = (h - barH) * 0.5;
        CGRect r = CGRectMake(x, y, self.barWidth, barH);
        UIColor *color = (x + self.barWidth * 0.5) < progressPx ? self.activeColor : self.inactiveColor;
        [color setFill];
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:self.barCornerRadius];
        [p fill];
    }
}

@end
