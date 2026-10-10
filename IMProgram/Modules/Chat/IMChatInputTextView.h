//  IMChatInputTextView.h
//  聊天输入框：多行自动换行 + 随内容增高（封顶后内部滚动）+ 支持粘贴图片（#2）。
//  对外刻意保持 UITextField 的用法习惯（placeholder / enabled），聊天页其余代码无需改动。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kIMChatInputMinHeight;   ///< 单行高度 36
extern const NSInteger kIMChatInputMaxLines;  ///< 最多显示行数，超出内部滚动

@interface IMChatInputTextView : UITextView
@property (nonatomic, copy, nullable) NSString *placeholder;
/// 对应 editable（被禁言时置 NO）。
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
/// 剪贴板有图片时回调（文本粘贴走原生路径）。
@property (nonatomic, copy, nullable) void (^onPasteImage)(UIImage *image);
/// 内容高度变化（含程序化改 text、改字体、宽度变化）→ 宿主据此更新高度约束。参数为封顶后的目标高度。
@property (nonatomic, copy, nullable) void (^onHeightChange)(CGFloat height);
/// 重算并（变化时）回调高度。
- (void)updateHeight;
@end

NS_ASSUME_NONNULL_END
