//  IMEmailLoginViewController.h
//  邮箱登录流程的根页（隐私与安全 ▸ 邮箱登录）：未绑定 → 说明页（「绑定邮箱」）；已绑定 → 邮箱 + 绑定日期 + 更换邮箱 / 解除绑定。
//  设计 ../IMServer/docs/design/EMAIL_LOGIN_DESIGN.md §2 / §5.1，契约 PROTOCOL §7.2。版式复用 IMTwoStepFormViewController 骨架。
//  进页（含子页返回）都重新 GET /users/me/email，不做本地缓存。

#import "IMTwoStepFormViewController.h"
#import "IMEmailLogin.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMEmailLoginViewController : IMTwoStepFormViewController
/// 最近一次取到（或流程回传）的状态；nil = 还没取到。
@property (nonatomic, strong, readonly, nullable) IMEmailState *state;
/// 直接采用一个状态（流程末页回根页前调用，避免根页闪一下旧状态）。
- (void)applyState:(nullable IMEmailState *)state;
/// 流程末页收尾：回根页并弹 toast。state 为 nil 表示「已解绑」（沿用根页已知的 available）。
+ (void)finishFlowFromPage:(IMTwoStepFormViewController *)page state:(nullable IMEmailState *)state toast:(nullable NSString *)toast;
@end

NS_ASSUME_NONNULL_END
