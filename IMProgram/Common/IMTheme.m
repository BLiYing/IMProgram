//  IMTheme.m

#import "IMTheme.h"

@interface IMTheme ()
+ (UIColor *)dynamicLight:(UIColor *)light dark:(UIColor *)dark;
+ (UIColor *)rgb:(NSInteger)hex;
+ (UIColor *)rgb:(NSInteger)hex alpha:(CGFloat)a;
@end

@implementation IMTheme

/// 浅/深两套取值的动态色（系统切深色自动适配，满足 UI.md 强制深色规则）。
+ (UIColor *)dynamicLight:(UIColor *)light dark:(UIColor *)dark {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

+ (UIColor *)rgb:(NSInteger)hex { return [self rgb:hex alpha:1]; }
+ (UIColor *)rgb:(NSInteger)hex alpha:(CGFloat)a {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0 alpha:a];
}

+ (UIColor *)accent { return UIColor.systemGreenColor; }
// Telegram 绿主题：自己气泡浅绿（深色为暗绿），对方气泡白（深色为暗灰），字均用主文本色（深色模式自动转白）。
+ (UIColor *)bubbleMe { return [self dynamicLight:[self rgb:0xE3FDD0] dark:[self rgb:0x1F4D2E]]; }
+ (UIColor *)bubbleMeText { return UIColor.labelColor; }
+ (UIColor *)bubbleThem { return [self dynamicLight:UIColor.whiteColor dark:[self rgb:0x262D31]]; }
+ (UIColor *)textPrimary { return UIColor.labelColor; }
+ (UIColor *)textSecondary { return UIColor.secondaryLabelColor; }
// 已读双勾绿：浅色气泡上偏深一点的绿，深色气泡上偏亮的绿，保证对比。
+ (UIColor *)checkRead { return [self dynamicLight:[self rgb:0x4CA64C] dark:[self rgb:0x7DDc7D]]; }
+ (UIColor *)unreadBadge { return UIColor.systemBlueColor; }
+ (UIColor *)bubbleMetaTime { return [self dynamicLight:[self rgb:0x6B8A5E] dark:[self rgb:0x9FB89A]]; }

+ (UIColor *)wallpaperTop { return [self dynamicLight:[self rgb:0xD6E8C4] dark:[self rgb:0x0E1A12]]; }
+ (UIColor *)wallpaperBottom { return [self dynamicLight:[self rgb:0xB4D89B] dark:[self rgb:0x16261A]]; }
+ (UIColor *)wallpaperDoodle {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1 alpha:0.04]
            : [UIColor colorWithWhite:1 alpha:0.16];
    }];
}
+ (UIColor *)datePillBg { return [self dynamicLight:[self rgb:0x5C8A4C alpha:0.55] dark:[self rgb:0x000000 alpha:0.45]]; }
+ (UIColor *)datePillText { return UIColor.whiteColor; }

+ (CGFloat)space1 { return 4; }
+ (CGFloat)space2 { return 8; }
+ (CGFloat)space3 { return 12; }
+ (CGFloat)space4 { return 16; }
+ (CGFloat)radiusBubble { return 14; }
+ (CGFloat)radiusCard { return 8; }

+ (NSString *)timeStringFromMillis:(int64_t)ms {
    if (ms <= 0) { return @""; }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ms / 1000.0];
    static NSDateFormatter *timeFmt, *dateFmt; static NSCalendar *cal;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        timeFmt = [NSDateFormatter new]; timeFmt.dateFormat = @"HH:mm";
        dateFmt = [NSDateFormatter new]; dateFmt.dateFormat = @"MM-dd";
        cal = NSCalendar.currentCalendar;
    });
    BOOL today = [cal isDateInToday:date];
    return [(today ? timeFmt : dateFmt) stringFromDate:date];
}

+ (BOOL)isMillis:(int64_t)a sameDayAsMillis:(int64_t)b {
    if (a <= 0 || b <= 0) { return NO; }
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *da = [NSDate dateWithTimeIntervalSince1970:a / 1000.0];
    NSDate *db = [NSDate dateWithTimeIntervalSince1970:b / 1000.0];
    return [cal isDate:da inSameDayAsDate:db];
}

+ (NSString *)dayHeaderStringFromMillis:(int64_t)ms {
    if (ms <= 0) { return @""; }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ms / 1000.0];
    NSCalendar *cal = NSCalendar.currentCalendar;
    if ([cal isDateInToday:date]) { return @"今天"; }
    if ([cal isDateInYesterday:date]) { return @"昨天"; }
    static NSDateFormatter *sameYearFmt, *fullFmt; static dispatch_once_t once;
    dispatch_once(&once, ^{
        sameYearFmt = [NSDateFormatter new]; sameYearFmt.dateFormat = @"M月d日";
        fullFmt = [NSDateFormatter new]; fullFmt.dateFormat = @"yyyy年M月d日";
    });
    BOOL sameYear = [cal component:NSCalendarUnitYear fromDate:date] ==
                    [cal component:NSCalendarUnitYear fromDate:NSDate.date];
    return [(sameYear ? sameYearFmt : fullFmt) stringFromDate:date];
}

+ (UIColor *)avatarColorForSeed:(NSString *)seed {
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

@end
