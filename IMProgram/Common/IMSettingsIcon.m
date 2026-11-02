//  IMSettingsIcon.m

#import "IMSettingsIcon.h"

const CGFloat kIMSettingsIconSide = 29;

UIImage *IMSettingsIconImage(NSString *symbol, UIColor *bg) {
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    UIImage *cached = cache[symbol];
    if (cached) { return cached; }
    CGFloat side = kIMSettingsIconSide;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *tile = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:7];
        [bg setFill];
        [tile fill];
        UIImage *glyph = [[UIImage systemImageNamed:symbol
                                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]]
                          imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize g = glyph.size;
        [glyph drawInRect:CGRectMake((side - g.width) / 2, (side - g.height) / 2, g.width, g.height)];
    }];
    cache[symbol] = img;
    return img;
}

UIImage *IMSettingsIconSpacer(void) {
    static UIImage *spacer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kIMSettingsIconSide, kIMSettingsIconSide)];
        spacer = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {}]; // 全透明
    });
    return spacer;
}
