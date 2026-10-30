//  IMTwoStepViewController.h
//  「两步验证」入口页（隐私与安全 ▸ 账号保护）：进页拉 GET /users/me/two-step，关闭态 → 介绍页，开启态 → 状态页。
//  设计 ../IMServer/docs/design/TWO_STEP_VERIFICATION_DESIGN.md §2；后续页：密码 → 绑定 → 恢复码 / 验证（关闭、重新生成）。

#import "IMTwoStepFormViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMTwoStepViewController : IMTwoStepFormViewController
@end

NS_ASSUME_NONNULL_END
