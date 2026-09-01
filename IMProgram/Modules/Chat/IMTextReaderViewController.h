//  IMTextReaderViewController.h
//  超长文本消息的全屏阅读器：可滚动 / 选中复制 / 字号调节。
//  由聊天页在文本超过 huge 门槛（见 IMBubbleCell textTierForContent:）时点击摘要卡打开。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class IMMentionSpan;

@interface IMTextReaderViewController : UIViewController

/// 用整段文本构造一个模态阅读器（内部 UITextView 只读可选中）。
/// `mentions`：`@昵称` → uid（uid 空串＝仅高亮不可点，如 @所有人），与气泡内 @提及高亮/跳资料同一套。
+ (instancetype)readerWithText:(NSString *)text
                      mentions:(nullable NSDictionary<NSString *, NSString *> *)mentions
                         spans:(nullable NSArray<IMMentionSpan *> *)spans;

/// 阅读器内点到某个可点 `@昵称` token 时回调其 uid（阅读器已先自我 dismiss）。
@property (nonatomic, copy, nullable) void (^onTapMentionUID)(NSString *uid);

@end

NS_ASSUME_NONNULL_END
