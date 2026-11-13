//  IMChangePasswordViewController.h
//  隐私与安全 ·「登录密码」（PHONE_AUTH_DESIGN §6.1 / §6.2，交互稿 1-6 / 1-7；版式沿用 IMTwoStepFormViewController）：
//  - 没设密码（验证码注册的账号）→ 设置密码：验证码（发到本人号码）+ 新密码两遍；成功**不**下线其它设备。
//  - 已设密码 → 修改密码：默认旧密码 + 新密码两遍；已绑定手机号且短信可用时可切「用短信验证码修改」。成功后其它设备下线、本机续期凭据就地替换。
//  两种证明方式下都显示「其它设备将下线」的说明；短信方式下不提示「与旧密码不同」。
//  状态（password_set / phone_bound / sms_available）由入口传入；没传（设置搜索直达）就先取一次。

#import "IMTwoStepFormViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class IMSecurityState, IMSMSCodeField;

@interface IMChangePasswordViewController : IMTwoStepFormViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID security:(nullable IMSecurityState *)security;
@property (nonatomic, strong, readonly) UITextField *oldField;
@property (nonatomic, strong, readonly) UITextField *freshField;
@property (nonatomic, strong, readonly) UITextField *confirmField;
@property (nonatomic, strong, readonly) IMSMSCodeField *codeField;
/// YES = 设置密码；NO = 修改（状态未知时按修改，即改造前的行为）。
@property (nonatomic, assign, readonly) BOOL setMode;
/// 修改密码时是否切到了短信验证码方式。
@property (nonatomic, assign, readonly) BOOL usingSMS;
@end

NS_ASSUME_NONNULL_END
