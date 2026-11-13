//  IMLoginSubpageViews.h
//  登录页里「替换栈内容」的两个子视图（同两步验证二步页，交互稿 1-3 / 1-4）：
//  - IMLoginCompleteProfileView「完善资料」：验证码登录命中未注册号码后填昵称 →「完成」即注册并登录。本期不加邀请码框。
//  - IMLoginResetPasswordView「重设密码」：手机号 + 验证码（scene=reset）+ 新密码两遍。
//  取值：标题 22 semibold、提示 13 secondaryLabel、字段 RoundedRect 44、错误 13 systemRed、主按钮 filled（accent）、返回 15 secondaryLabel。
//  只负责显示与输入；请求由登录页发起（IMLoginViewController+Phone）。

#import <UIKit/UIKit.h>
#import "IMLoginPhoneFields.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMLoginCompleteProfileView : UIView
@property (nonatomic, strong, readonly) UITextField *nicknameField;
@property (nonatomic, strong, readonly) UIButton *submitButton;
@property (nonatomic, copy, nullable) void (^onSubmit)(NSString *nickname);
@property (nonatomic, copy, nullable) void (^onBack)(void);
@property (nonatomic, assign) BOOL busy;
/// 进入时设置：显示「+86 136****0001 已验证」（按本机输入打码），清空昵称与错误。
- (void)resetWithMaskedPhone:(NSString *)maskedPhone;
- (void)showError:(nullable NSString *)message;
@end

@interface IMLoginResetPasswordView : UIView
@property (nonatomic, strong, readonly) IMLoginPhoneFields *phoneFields;
@property (nonatomic, strong, readonly) UITextField *passwordField;
@property (nonatomic, strong, readonly) UITextField *confirmField;
@property (nonatomic, strong, readonly) UIButton *submitButton;
@property (nonatomic, copy, nullable) void (^onSubmit)(void);
@property (nonatomic, copy, nullable) void (^onBack)(void);
@property (nonatomic, assign) BOOL busy;
- (void)showError:(nullable NSString *)message;
/// 清空密码两栏与错误（号码保留，便于从验证码登录带过来）。
- (void)resetPasswords;
@end

NS_ASSUME_NONNULL_END
