//  IMTwoStepBindViewController.h
//  开启流程 ③「绑定认证器」：本地绘制的二维码 + 折叠的手动密钥（4 位一组、等宽、复制）+ 6 位码。
//  POST /users/me/two-step/enable 成功即已启用，回 10 个恢复码 → 进「恢复码」页。

#import "IMTwoStepFormViewController.h"

@class IMTwoStepSetup;

NS_ASSUME_NONNULL_BEGIN

@interface IMTwoStepBindViewController : IMTwoStepFormViewController
/// setup 结果（密钥只留内存，页面销毁即丢）。
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID setup:(IMTwoStepSetup *)setup;
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
