//  IMGroupManageRowIcon.m

#import "IMGroupManageRowIcon.h"
#import "IMTheme.h"

UIImage *IMGroupManageRowIconTinted(NSString *symbolName, UIColor *tint) {
    CGFloat side = 30, radius = 7, maxGlyph = 18;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [(tint ?: IMTheme.accent) setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:radius] fill];
        UIImage *glyph = [[UIImage systemImageNamed:symbolName
                                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]]
                          imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize gs = glyph.size;
        if (gs.width <= 0 || gs.height <= 0) { return; }
        CGFloat scale = MIN(1.0, MIN(maxGlyph / gs.width, maxGlyph / gs.height));
        CGSize drawn = CGSizeMake(gs.width * scale, gs.height * scale);
        [glyph drawInRect:CGRectMake((side - drawn.width) / 2.0, (side - drawn.height) / 2.0, drawn.width, drawn.height)];
    }];
}

/// 保持本页「单一 accent 纯色·跟随主题」的现状（不用「我」页那种逐行彩色），
/// 主题切换后重开页面即以当前主题色重绘。
UIImage *IMGroupManageRowIcon(NSString *symbolName) {
    return IMGroupManageRowIconTinted(symbolName, IMTheme.accent);
}
