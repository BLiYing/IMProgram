//  IMPhoneBindViewController.h
//  隐私与安全 ·「登录手机号」绑定 / 更换（PHONE_AUTH_DESIGN §6.3 / §6.4，交互稿 1-8）：
//  先验证新号码（send-code scene=bind）→ 点「下一步」弹确认身份弹层（绑定只有密码；更换可用密码或旧号码验证码）→ POST /users/me/phone。
//  证明本身的错留在弹层里重输，页面上已填的新号码与验证码不动；新号码那边的错（data.field=code、已被占用、格式）回到本页红字。
//  更换时页面顶部显示当前号码。号码变化即重置该号码的发码倒计时（按号码计）。
//  绑定时 security 带 legacy_phone（资料里曾自填的号码，§15.1）→ 页顶提示「是否绑定为登录手机号」：
//  「绑定」预填国家码 + 号码（仍要验证码 + 确认身份）；「不再提示」DELETE /users/me/legacy-phone，成功才收起，失败吐司。

#import "IMTwoStepFormViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class IMSecurityState, IMProofSession, IMSMSCodeField;

@interface IMPhoneBindViewController : IMTwoStepFormViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID security:(IMSecurityState *)security;
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_UNAVAILABLE;
@property (nonatomic, strong, readonly) UITextField *phoneField;
@property (nonatomic, strong, readonly) IMSMSCodeField *codeField;
@property (nonatomic, strong, readonly) IMProofSession *proofSession;
/// 绑定成功回调（新的打码号码），隐私与安全页据此就地更新右值。
@property (nonatomic, copy, nullable) void (^onBound)(NSString *phoneMasked);
@end

NS_ASSUME_NONNULL_END
