//  IMGroupTextEditViewController.h
//  群公告 / 群简介 多行编辑页（决策 18）：替换旧单行 UIAlertController 文本框。
//  多行 UITextView + 右下字数计数；公告可「撤下」（发空串）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMGroupTextEditViewController : UIViewController

/// 以独立页（模态 nav）弹出编辑器。onCommit 回带 trim 后的文本（撤下=空串）；调用方自行比对是否变化。
/// @param maxChars     字数上限（公告 500 / 简介 200）。
/// @param commitTitle  右上按钮文案（@"发布" / @"保存"）。
/// @param allowRetract YES 时底部显示红色「撤下公告」（回带空串）。
/// @param footer       底部说明文案（可空）。
+ (void)presentFrom:(UIViewController *)host
              title:(NSString *)title
               text:(NSString *)text
        placeholder:(NSString *)placeholder
           maxChars:(NSInteger)maxChars
        commitTitle:(NSString *)commitTitle
       allowRetract:(BOOL)allowRetract
             footer:(nullable NSString *)footer
           onCommit:(void (^)(NSString *text))onCommit;

@end

NS_ASSUME_NONNULL_END
