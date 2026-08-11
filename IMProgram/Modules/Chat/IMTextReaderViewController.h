//  IMTextReaderViewController.h
//  超长文本消息的全屏阅读器：可滚动 / 选中复制 / 字号调节。
//  由聊天页在文本超过 huge 门槛（见 IMBubbleCell textTierForContent:）时点击摘要卡打开。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMTextReaderViewController : UIViewController

/// 用整段文本构造一个模态阅读器（内部 UITextView 只读可选中）。
/// `mentionNames`：需高亮的 `@昵称` 名单（nil=不高亮），与气泡内 @提及高亮同一套。
+ (instancetype)readerWithText:(NSString *)text mentionNames:(nullable NSArray<NSString *> *)mentionNames;

@end

NS_ASSUME_NONNULL_END
