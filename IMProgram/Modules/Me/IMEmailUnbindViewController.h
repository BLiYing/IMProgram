//  IMEmailUnbindViewController.h
//  解除绑定：说明页 → UIAlertController(.destructive) 二次确认 → 确认身份弹层（密码或短信验证码）→ POST unbind → 回根页（未绑定）+ toast。不需要邮箱验证码。

#import "IMTwoStepFormViewController.h"

@class IMProofSession;

NS_ASSUME_NONNULL_BEGIN

@interface IMEmailUnbindViewController : IMTwoStepFormViewController
@property (nonatomic, strong, readonly) IMProofSession *proofSession;
/// 确认框通过后弹确认身份弹层并发请求（测试可直接调；页面里由 destructive 按钮触发）。
- (void)performUnbind;
@end

NS_ASSUME_NONNULL_END
