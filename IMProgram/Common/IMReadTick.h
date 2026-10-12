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

/// 勾的种类：无 / 单勾（已送达）/ 双勾（已读）。
typedef NS_ENUM(NSInteger, IMReadTickKind) {
    IMReadTickKindNone = 0,
    IMReadTickKindSent,
    IMReadTickKindRead,
};

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

/// 「时间文字 + 勾」一行：文字走 UILabel、勾走独立 UIImageView（底边落在文字基线）。
/// 不能把勾做成 UILabel 富文本末尾的 NSTextAttachment——真机上 UILabel 对「以附件结尾」的文本量出的宽度偏窄，
/// 双勾第二笔会被裁（会话列表 / 语音气泡 / 各媒体气泡都踩过）。尺寸由内部约束撑出，外部像普通 label 一样约束即可。
@interface IMTickMetaView : UIView

/// 仅文字部分（时间 / 发送中… / 未发送 ✗）；字体与颜色由富文本属性给出。
@property (nonatomic, copy, nullable) NSAttributedString *attributedText;
/// 字号基准（勾高 = 字号 × 0.95，同 IMReadTick）。默认 11。
@property (nonatomic, assign) CGFloat tickFontSize;

/// 一次设定文字与勾；kind=None 时不画勾、tickColor 忽略。
- (void)setAttributedText:(nullable NSAttributedString *)text tick:(IMReadTickKind)kind tickColor:(nullable UIColor *)tickColor;

@end

NS_ASSUME_NONNULL_END
