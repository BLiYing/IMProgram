//  IMTwoStepPasswordViewController.h
//  开启流程 ②「验证密码」：一个密码框 + 继续；POST /users/me/two-step/setup 成功后进「绑定认证器」。

#import "IMTwoStepFormViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMTwoStepPasswordViewController : IMTwoStepFormViewController
@end

NS_ASSUME_NONNULL_END
