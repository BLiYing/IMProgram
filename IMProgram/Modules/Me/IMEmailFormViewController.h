//  IMEmailFormViewController.h
//  填邮箱页（绑定 / 更换同页，仅标题与 footer 不同）→ 确认身份弹层（密码或短信验证码）→ POST send-code → 推验证码页。
//  所有输入遇错不清空；邮箱先做轻量预检（IMEmailPrecheck），不合规点按钮只出红字、不发请求。

#import "IMTwoStepFormViewController.h"

@class IMProofSession;

NS_ASSUME_NONNULL_BEGIN

@interface IMEmailFormViewController : IMTwoStepFormViewController
/// change=YES 为更换邮箱；currentEmail 仅用于日志（脱敏）与判断，不做本地比较（相同邮箱由服务端回 200035）。
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID change:(BOOL)change currentEmail:(nullable NSString *)currentEmail;
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_UNAVAILABLE;
@property (nonatomic, strong, readonly) UITextField *emailField;
@property (nonatomic, strong, readonly) IMProofSession *proofSession;
@end

NS_ASSUME_NONNULL_END
