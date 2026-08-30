//  IMTheme.h
//  设计令牌（design tokens），对齐 IMServer/docs/UI.md 与 Web 端 CSS 变量。
//  统一颜色/间距/圆角，新增 UI 只引用这里，不写魔法值。用语义色自动适配深色模式。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMTheme : NSObject

// 颜色
@property (class, nonatomic, readonly) UIColor *accent;        // 主色
@property (class, nonatomic, readonly) UIColor *accentSoft;    // 主色淡底（accent @ 12% alpha）：彩色圆角图标淡底（收藏文本/链接图标等），Web 对应 --accent-soft
@property (class, nonatomic, readonly) UIColor *bubbleMe;      // 自己气泡底（Telegram 绿主题：浅绿）
@property (class, nonatomic, readonly) UIColor *bubbleMeText;  // 自己气泡字
@property (class, nonatomic, readonly) UIColor *bubbleThem;    // 对方气泡底（白/深灰）
@property (class, nonatomic, readonly) UIColor *textPrimary;
@property (class, nonatomic, readonly) UIColor *textSecondary;
@property (class, nonatomic, readonly) UIColor *textTertiary;
@property (class, nonatomic, readonly) UIColor *pageBackground;
@property (class, nonatomic, readonly) UIColor *groupedBackground;
@property (class, nonatomic, readonly) UIColor *cardBackground;
@property (class, nonatomic, readonly) UIColor *surface;
@property (class, nonatomic, readonly) UIColor *surfaceElevated;
@property (class, nonatomic, readonly) UIColor *separator;
@property (class, nonatomic, readonly) UIColor *danger;
@property (class, nonatomic, readonly) UIColor *checkRead;     // 已读双勾绿
@property (class, nonatomic, readonly) UIColor *onlineDot;     // 在线态绿点（会话列表/通讯录头像右下角）
@property (class, nonatomic, readonly) UIColor *unreadBadge;   // 未读胶囊（蓝，区别于绿在线点/绿勾）
@property (class, nonatomic, readonly) UIColor *bubbleMetaTime; // 气泡内时间小字（浅色气泡上的次要色）
// 媒体（图片/视频）上的悬浮角标：底恒为半透明黑，故字色不随明暗主题变化（浅色图上也要读得清）。
@property (class, nonatomic, readonly) UIColor *mediaBadgeBackground; // 时长/时间/进度角标底
@property (class, nonatomic, readonly) UIColor *mediaBadgeText;       // 角标文字（白）
@property (class, nonatomic, readonly) UIColor *mediaBadgeCheckRead;  // 角标内已读双勾（亮绿，暗底可辨）

// 聊天壁纸（Telegram 绿主题：渐变 + 涂鸦）
@property (class, nonatomic, readonly) UIColor *wallpaperTop;     // 渐变上端
@property (class, nonatomic, readonly) UIColor *wallpaperBottom;  // 渐变下端
@property (class, nonatomic, readonly) UIColor *wallpaperDoodle;  // 涂鸦图案色（低透明白）
@property (class, nonatomic, readonly) UIColor *datePillBg;       // 日期/未读分隔胶囊底
@property (class, nonatomic, readonly) UIColor *datePillText;     // 日期/未读分隔胶囊字
/// 群系统消息里**人名段**的颜色（可点）。**不能用 accent**：胶囊底就是主题绿，绿字绿底看不出
/// 哪几个字是名字（2026-08-30 反馈）。取浅琥珀——在浅色的绿胶囊与深色的黑胶囊上都足够跳，
/// 且与白色正文一眼可分。Web 对应 `--sys-name`，改一处两端要一起改。
@property (class, nonatomic, readonly) UIColor *datePillNameText;

// 间距 / 圆角
@property (class, nonatomic, readonly) CGFloat space1;        // 4
@property (class, nonatomic, readonly) CGFloat space2;        // 8
@property (class, nonatomic, readonly) CGFloat space3;        // 12
@property (class, nonatomic, readonly) CGFloat space4;        // 16
@property (class, nonatomic, readonly) CGFloat radiusBubble;  // 14
@property (class, nonatomic, readonly) CGFloat radiusCard;    // 8
@property (class, nonatomic, readonly) CGFloat chatFontSize;

// 工具
/// 气泡类 cell 的「收发方向样式」单一入口：底色（我方 bubbleMe / 对方 bubbleThem）+ 圆角（radiusBubble）
/// + 尾角（自己右下直角、对方左下直角）。文本/文件/链接卡/聊天记录/（将来）语音等所有气泡类 cell 共用，
/// 媒体类（图片/视频/相册）不加尾角故不调本方法。长按预览的 visiblePath 读同一 maskedCorners，形状自动跟随。
+ (void)applyBubbleDirectionStyle:(UIView *)bubble mine:(BOOL)mine;

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
