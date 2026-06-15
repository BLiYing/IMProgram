//  IMTheme.m

#import "IMTheme.h"

@implementation IMTheme

+ (UIColor *)accent { return UIColor.systemBlueColor; }
+ (UIColor *)bubbleMe { return UIColor.systemBlueColor; }
+ (UIColor *)bubbleMeText { return UIColor.whiteColor; }
+ (UIColor *)bubbleThem { return UIColor.secondarySystemBackgroundColor; }
+ (UIColor *)textPrimary { return UIColor.labelColor; }
+ (UIColor *)textSecondary { return UIColor.secondaryLabelColor; }

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
