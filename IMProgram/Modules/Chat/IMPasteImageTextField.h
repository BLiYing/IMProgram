//  IMPasteImageTextField.h
//  支持粘贴图片的输入框（#2）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// UITextField 默认不接受图片粘贴；剪贴板有图片时放开 paste 菜单并回调图片（文本粘贴走原生路径）。
@interface IMPasteImageTextField : UITextField
@property (nonatomic, copy, nullable) void (^onPasteImage)(UIImage *image);
@end

NS_ASSUME_NONNULL_END
