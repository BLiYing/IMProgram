//  IMEmailUnbindViewController.h
//  解除绑定：当前密码页 → UIAlertController(.destructive) 二次确认 → POST unbind → 回根页（未绑定）+ toast。不需要邮箱验证码。

#import "IMTwoStepFormViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMEmailUnbindViewController : IMTwoStepFormViewController
@property (nonatomic, strong, readonly) UITextField *passwordField;
/// 确认框通过后真正发请求（测试可直接调；页面里由 destructive 按钮触发）。
- (void)performUnbind;
@end

NS_ASSUME_NONNULL_END
