//
//  IMReadTick.h
//  「我发的消息」已读状态图标：未读 = 单勾，已读 = 双勾（READ_TICK_DESIGN.md）。
//  UIBezierPath 按设计稿同一份路径渲染成 template UIImage（不入 xcassets：无 SVG→PDF 工具链，路径即真相）。
//  各 cell / 会话列表一律走本类，不再各拼 ✓/✓✓ 文本。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 勾与时间文字的间距（pt）。
FOUNDATION_EXPORT const CGFloat kIMReadTickGap;

@interface IMReadTick : NSObject

/// 单勾(13×10)/双勾(18×10) 的 template 图，高度 height pt（宽按 viewBox 比例），按 scale 缓存。
+ (UIImage *)imageDouble:(BOOL)isDouble height:(CGFloat)height;

/// 仅勾的富文本：NSTextAttachment（图高 = 字号×0.95，底边落在基线上）+ 前景色着色。
+ (NSAttributedString *)tickAttributedStringRead:(BOOL)read font:(UIFont *)font color:(UIColor *)color;

/// 「时间 + 3pt + 勾」：time 为空则只有勾；time 用 font/timeColor，勾用 tickColor。
+ (NSAttributedString *)metaWithTime:(nullable NSString *)time
                                read:(BOOL)read
                                font:(UIFont *)font
                           timeColor:(UIColor *)timeColor
                           tickColor:(UIColor *)tickColor;

@end

NS_ASSUME_NONNULL_END
