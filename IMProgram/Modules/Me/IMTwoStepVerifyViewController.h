//  IMTwoStepVerifyViewController.h
//  状态页的两个管理动作共用的「动态码 / 恢复码」验证页（身份确认在点按钮后的确认身份弹层里：密码或短信验证码）：关闭两步验证（红按钮 + 系统二次确认）/ 重新生成恢复码（成功后进恢复码页）。
//  码框可在「6 位动态码」与「恢复码」之间切换（恢复码大小写 / 连字符 / 空格不敏感，归一化只在提交时做）。

#import "IMTwoStepFormViewController.h"

@class IMProofSession;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMTwoStepVerifyMode) {
    IMTwoStepVerifyModeDisable,
    IMTwoStepVerifyModeRegenerate,
};

@interface IMTwoStepVerifyViewController : IMTwoStepFormViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID mode:(IMTwoStepVerifyMode)mode;
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_UNAVAILABLE;
/// 确认身份弹层会话（由状态页传入共用；没传就自建）。
@property (nonatomic, strong, null_resettable) IMProofSession *proofSession;
@end

NS_ASSUME_NONNULL_END
