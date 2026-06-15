//  IMTheme.h
//  设计令牌（design tokens），对齐 IMServer/docs/UI.md 与 Web 端 CSS 变量。
//  统一颜色/间距/圆角，新增 UI 只引用这里，不写魔法值。用语义色自动适配深色模式。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMTheme : NSObject

// 颜色
@property (class, nonatomic, readonly) UIColor *accent;        // 主色
@property (class, nonatomic, readonly) UIColor *bubbleMe;      // 自己气泡底（Telegram 绿主题：浅绿）
@property (class, nonatomic, readonly) UIColor *bubbleMeText;  // 自己气泡字
@property (class, nonatomic, readonly) UIColor *bubbleThem;    // 对方气泡底（白/深灰）
@property (class, nonatomic, readonly) UIColor *textPrimary;
@property (class, nonatomic, readonly) UIColor *textSecondary;
@property (class, nonatomic, readonly) UIColor *checkRead;     // 已读双勾绿
@property (class, nonatomic, readonly) UIColor *unreadBadge;   // 未读胶囊（蓝，区别于绿在线点/绿勾）
@property (class, nonatomic, readonly) UIColor *bubbleMetaTime; // 气泡内时间小字（浅色气泡上的次要色）

// 聊天壁纸（Telegram 绿主题：渐变 + 涂鸦）
@property (class, nonatomic, readonly) UIColor *wallpaperTop;     // 渐变上端
@property (class, nonatomic, readonly) UIColor *wallpaperBottom;  // 渐变下端
@property (class, nonatomic, readonly) UIColor *wallpaperDoodle;  // 涂鸦图案色（低透明白）
@property (class, nonatomic, readonly) UIColor *datePillBg;       // 日期/未读分隔胶囊底
@property (class, nonatomic, readonly) UIColor *datePillText;     // 日期/未读分隔胶囊字

// 间距 / 圆角
@property (class, nonatomic, readonly) CGFloat space1;        // 4
@property (class, nonatomic, readonly) CGFloat space2;        // 8
@property (class, nonatomic, readonly) CGFloat space3;        // 12
@property (class, nonatomic, readonly) CGFloat space4;        // 16
@property (class, nonatomic, readonly) CGFloat radiusBubble;  // 14
@property (class, nonatomic, readonly) CGFloat radiusCard;    // 8

// 工具
/// 毫秒时间戳 → "HH:mm"（今天）/"MM-dd"（更早）；0 返回空串。
+ (NSString *)timeStringFromMillis:(int64_t)ms;
/// 由种子（uid）派生稳定的头像底色（一组柔和色循环）。
+ (UIColor *)avatarColorForSeed:(nullable NSString *)seed;

/// 两个毫秒时间戳是否同一自然日（用于聊天页按日期分组）。
+ (BOOL)isMillis:(int64_t)a sameDayAsMillis:(int64_t)b;
/// 毫秒时间戳 → 日期分隔文案："今天"/"昨天"/"M月d日"（今年）/"yyyy年M月d日"（往年）；0 返回空串。
+ (NSString *)dayHeaderStringFromMillis:(int64_t)ms;

@end

NS_ASSUME_NONNULL_END
