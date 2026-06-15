//  IMChatBackgroundView.m

#import "IMChatBackgroundView.h"
#import "IMTheme.h"

@implementation IMChatBackgroundView {
    CAGradientLayer *_gradient;
    UIView *_doodle;          // 涂鸦图案层（backgroundColor = 平铺图案色）
    UIImage *_doodleTile;     // 当前 traitCollection 下的涂鸦平铺图
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _gradient = [CAGradientLayer layer];
        [self.layer addSublayer:_gradient];

        _doodle = [UIView new];
        _doodle.userInteractionEnabled = NO;
        [self addSubview:_doodle];

        [self applyColors];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _gradient.frame = self.bounds;
    _doodle.frame = self.bounds;
}

/// 深色/浅色切换时刷新渐变与涂鸦色。
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) {
        [self applyColors];
    }
}

- (void)applyColors {
    // resolvedColor: 在当前 trait 下取出具体色给 CALayer（CALayer 不随动态色自动刷新）。
    _gradient.colors = @[
        (id)[IMTheme.wallpaperTop resolvedColorWithTraitCollection:self.traitCollection].CGColor,
        (id)[IMTheme.wallpaperBottom resolvedColorWithTraitCollection:self.traitCollection].CGColor,
    ];
    _doodleTile = [self makeDoodleTile];
    _doodle.backgroundColor = [UIColor colorWithPatternImage:_doodleTile];
}

/// 生成一张涂鸦平铺图：在固定网格上画一组 SF Symbol（位置/符号写死 → 平铺稳定不抖）。
- (UIImage *)makeDoodleTile {
    CGFloat tile = 220;
    UIColor *ink = [IMTheme.wallpaperDoodle resolvedColorWithTraitCollection:self.traitCollection];

    // (symbolName, x, y, pointSize)：在 220×220 网格内错落分布，平铺后形成连续涂鸦感。
    NSArray *items = @[
        @[@"heart.fill",        @28,  @30,  @22],
        @[@"star.fill",         @150, @18,  @20],
        @[@"gamecontroller.fill",@95, @70,  @26],
        @[@"gift.fill",         @186, @92,  @22],
        @[@"music.note",        @38,  @110, @24],
        @[@"leaf.fill",         @170, @158, @22],
        @[@"bolt.fill",         @110, @150, @20],
        @[@"moon.fill",         @18,  @178, @20],
        @[@"cup.and.saucer.fill",@70, @196, @22],
        @[@"camera.fill",       @196, @196, @20],
    ];

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(tile, tile) format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        for (NSArray *it in items) {
            NSString *name = it[0];
            CGFloat x = [it[1] floatValue], y = [it[2] floatValue], pt = [it[3] floatValue];
            UIImageSymbolConfiguration *cfg =
                [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightRegular];
            UIImage *sym = [[UIImage systemImageNamed:name withConfiguration:cfg]
                            imageWithTintColor:ink renderingMode:UIImageRenderingModeAlwaysOriginal];
            if (!sym) { continue; }
            [sym drawAtPoint:CGPointMake(x - sym.size.width / 2, y - sym.size.height / 2)];
        }
    }];
}

@end
