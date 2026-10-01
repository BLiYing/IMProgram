//  IMAvatarPlaceholder.m

#import "IMAvatarPlaceholder.h"
#import <wctype.h>

/// 组合字符序列（NSString 的「一个字」，含变体选择符/组合标记，emoji 不会被切半）首个 Unicode 标量，
/// 用来判断这个字是不是汉字。surrogate pair（辅助平面字符，如扩展区汉字）按一对 UTF-16 代码单元解码。
static UInt32 IMFirstScalar(NSString *s) {
    if (s.length == 0) { return 0; }
    unichar c0 = [s characterAtIndex:0];
    if (s.length > 1 && CFStringIsSurrogateHighCharacter(c0) && CFStringIsSurrogateLowCharacter([s characterAtIndex:1])) {
        return CFStringGetLongCharacterForSurrogatePair(c0, [s characterAtIndex:1]);
    }
    return c0;
}

/// CJK 统一表意文字：基本区 + 兼容区 + 全部辅助平面扩展区（B 起，含 C/D/E/F/G…，该平面几乎全部留给 CJK 扩展）。
static BOOL IMIsHanScalar(UInt32 u) {
    return (u >= 0x4E00 && u <= 0x9FFF) || (u >= 0x3400 && u <= 0x4DBF)
        || (u >= 0xF900 && u <= 0xFAFF) || (u >= 0x20000 && u <= 0x3FFFD);
}

/// 大写一个字，但保证还是「一个字」——`-uppercaseString` 走完整 Unicode 大小写折叠，极少数字符会一拆二
/// （德语 ß → "SS"，两个字符），破坏首字母头像「只有一个字」的前提（画出来的圆里挤进两个字母）。
/// 改用 `towupper` 的简单大写映射：没有对应大写形式的字符原样返回，绝不增字（ß 验证过原样返回）。
static NSString *IMUppercaseSingleGrapheme(NSString *grapheme) {
    UInt32 scalar = IMFirstScalar(grapheme);
    wint_t upper = towupper((wint_t)scalar);
    UniChar buf[2];
    NSUInteger len;
    if (upper > 0xFFFF) {
        buf[0] = (UniChar)(((upper - 0x10000) >> 10) + 0xD800);
        buf[1] = (UniChar)(((upper - 0x10000) & 0x3FF) + 0xDC00);
        len = 2;
    } else {
        buf[0] = (UniChar)upper;
        len = 1;
    }
    NSString *upperStr = [NSString stringWithCharacters:buf length:len];
    NSUInteger baseLen = (scalar > 0xFFFF) ? 2 : 1; // 原字符占几个 UTF-16 code unit（辅助平面代理对占 2）
    if (grapheme.length > baseLen) { // 保留首标量之后的组合标记（若这个「字」本身是 base+组合标记）
        return [upperStr stringByAppendingString:[grapheme substringFromIndex:baseLen]];
    }
    return upperStr;
}

NSString *IMAvatarInitials(NSString *_Nullable name) {
    NSString *t = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (t.length == 0) { return @""; }
    NSRange lastRange = [t rangeOfComposedCharacterSequenceAtIndex:t.length - 1];
    NSString *last = [t substringWithRange:lastRange];
    if (IMIsHanScalar(IMFirstScalar(last))) { return last; } // 中文名：取末字
    NSRange firstRange = [t rangeOfComposedCharacterSequenceAtIndex:0];
    return IMUppercaseSingleGrapheme([t substringWithRange:firstRange]); // 英文名/用户名：取首字母，大写
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
