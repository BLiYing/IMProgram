//  IMAvatarPlaceholder.m

#import "IMAvatarPlaceholder.h"

NSString *IMAvatarInitials(NSString *_Nullable name) {
    return name.length >= 2 ? [name substringFromIndex:name.length - 2] : (name ?: @"");
}

UIColor *IMAvatarSeedColor(NSString *_Nullable seed) {
    // 柔和色板（与 Telegram 头像配色思路一致：按种子稳定取色）。
    static NSArray<UIColor *> *palette;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        palette = @[
            [UIColor colorWithRed:0.20 green:0.60 blue:0.96 alpha:1], // 蓝
            [UIColor colorWithRed:0.31 green:0.78 blue:0.47 alpha:1], // 绿
            [UIColor colorWithRed:0.96 green:0.62 blue:0.20 alpha:1], // 橙
            [UIColor colorWithRed:0.90 green:0.36 blue:0.42 alpha:1], // 红
            [UIColor colorWithRed:0.58 green:0.45 blue:0.90 alpha:1], // 紫
            [UIColor colorWithRed:0.18 green:0.72 blue:0.74 alpha:1], // 青
        ];
    });
    NSUInteger h = 0;
    for (NSUInteger i = 0; i < seed.length; i++) { h = h * 31 + [seed characterAtIndex:i]; }
    return palette[seed.length ? (h % palette.count) : 0];
}

NSData *_Nullable IMAvatarPlaceholderPNG(NSString *_Nullable name, NSString *_Nullable seed, CGFloat side) {
    if (side <= 0) { return nil; }
    CGSize size = CGSizeMake(side, side);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1; // side 已是像素尺寸
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *context) {
        [IMAvatarSeedColor(seed) setFill];
        UIRectFill((CGRect){CGPointZero, size});
        NSString *text = IMAvatarInitials(name.length ? name : seed);
        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:side * 0.4 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName: UIColor.whiteColor,
        };
        CGSize textSize = [text sizeWithAttributes:attrs];
        [text drawAtPoint:CGPointMake((side - textSize.width) / 2, (side - textSize.height) / 2) withAttributes:attrs];
    }];
}
