//  IMDayPillView.h
//  聊天流里的「日期分隔胶囊」（今天 / 昨天 / M月d日）。IMSystemCell 与 IMMessageCell 共用；
//  IMBubbleCell / IMVoiceBubbleCell 历史上各自内置了一份同款，样式改动时一并改。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 宿主只需把 top/leading/trailing 贴 contentView（高度由本视图自管）。无文案时高 0、隐藏；
/// 有文案时 = 上边距 8 + 胶囊高 24，胶囊水平居中。
@interface IMDayPillView : UIView

/// 非空 = 显示；nil/空 = 收起为高 0。复用 cell 时按当前主题强调色刷新。
- (void)applyText:(nullable NSString *)text;

@end

NS_ASSUME_NONNULL_END
