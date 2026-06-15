//  IMTheme.h
//  设计令牌（design tokens），对齐 IMServer/docs/UI.md 与 Web 端 CSS 变量。
//  统一颜色/间距/圆角，新增 UI 只引用这里，不写魔法值。用语义色自动适配深色模式。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMTheme : NSObject

// 颜色
@property (class, nonatomic, readonly) UIColor *accent;        // 主色
@property (class, nonatomic, readonly) UIColor *bubbleMe;      // 自己气泡底
@property (class, nonatomic, readonly) UIColor *bubbleMeText;  // 自己气泡字
@property (class, nonatomic, readonly) UIColor *bubbleThem;    // 对方气泡底
@property (class, nonatomic, readonly) UIColor *textPrimary;
@property (class, nonatomic, readonly) UIColor *textSecondary;

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

@end

NS_ASSUME_NONNULL_END
