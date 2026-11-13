//  IMHTTPService+Phone.h
//  手机号与短信验证码 REST（PROTOCOL §7.3，设计 PHONE_AUTH_DESIGN）：发码、验证码登录即注册、完善资料、忘记密码、
//  冷静期凭票恢复、隐私与安全状态、本人号码发码（verify）、设置 / 修改密码（proof）、绑定 / 更换手机号。
//  业务错误 HTTP 400 但响应体是标准信封：全部保留业务码，并把 data 里的 attempts_left / retry_after_sec / field / restore_ticket
//  挂进 NSError.userInfo（IMErrorByAttachingPhoneInfo；邮箱 / 两步验证 / 注销 / 导出的 runner 也挂，proof 的错误三处同口径）。
//  **日志红线**：号码、验证码、票据不得写日志（HTTP 层按键名脱敏，见 IMHTTPLogFormatter；本文件自己的日志只写打码号码）。

#import "IMHTTPService.h"
#import "IMPhoneAuth.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const IMErrorSMSAttemptsLeftKey; ///< NSNumber
FOUNDATION_EXPORT NSString * const IMErrorSMSRetryAfterKey;   ///< NSNumber
FOUNDATION_EXPORT NSString * const IMErrorSMSFieldKey;        ///< NSString：proof / code
FOUNDATION_EXPORT NSString * const IMErrorRestoreTicketKey;   ///< NSString：验证码登录命中冷静期时的一次性恢复票（只在内存）

/// 把响应 data 里的 attempts_left / retry_after_sec / field / restore_ticket 附到错误 userInfo（码与文案不变）。
FOUNDATION_EXPORT NSError *_Nullable IMErrorByAttachingPhoneInfo(NSError *_Nullable error, NSDictionary *_Nullable body);
/// 读错误上的附加值；没有返回 -1 / nil。
FOUNDATION_EXPORT NSInteger IMSMSAttemptsLeftFromError(NSError *_Nullable error);
FOUNDATION_EXPORT NSInteger IMSMSRetryAfterFromError(NSError *_Nullable error);
FOUNDATION_EXPORT NSString *_Nullable IMSMSFieldFromError(NSError *_Nullable error);

/// 发码成功体。
@interface IMSMSSendResult : NSObject
@property (nonatomic, assign) NSInteger resendAfter; ///< 缺省 -1（调用方按 60 兜底）
@property (nonatomic, assign) NSInteger expiresIn;
@property (nonatomic, copy, nullable) NSString *phoneMasked; ///< verify-code 才有
@end

/// 验证码登录 / 完善资料的结果：要么已登录（token / userID / username），要么需要完善资料（registerTicket）。
@interface IMSMSLoginResult : NSObject
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, copy, nullable) NSString *userID;
@property (nonatomic, copy, nullable) NSString *username; ///< 服务端给的公开用户名（本机会话只认它）
@property (nonatomic, assign) BOOL needRegister;
@property (nonatomic, copy, nullable) NSString *registerTicket; ///< 只在内存
@end

@interface IMHTTPService (Phone)

/// POST /sms/send-code {scene, country_code, phone, lang}。scene = login / reset 免鉴权；bind 需传 token。
- (void)sendSMSCodeForScene:(NSString *)scene countryCode:(NSString *)countryCode phone:(NSString *)phone
                      token:(nullable NSString *)token
                 completion:(void (^)(IMSMSSendResult *_Nullable result, NSError *_Nullable error))completion;

/// POST /login/sms。成功 → 走与密码登录相同的收尾（缓存 token、落续期凭据、记服务端 username）；
/// 200020 带 IMErrorTwoStepTicketKey；200005 带 IMErrorDeleteAtKey 与 IMErrorRestoreTicketKey。
- (void)loginWithSMSCountryCode:(NSString *)countryCode phone:(NSString *)phone code:(NSString *)code
                     completion:(void (^)(IMSMSLoginResult *_Nullable result, NSError *_Nullable error))completion;

/// POST /register/phone {register_ticket, nickname, device…} → 与登录成功相同。200048 票无效、200042 号码被抢注。
- (void)registerPhoneWithTicket:(NSString *)ticket nickname:(NSString *)nickname
                     completion:(void (^)(IMSMSLoginResult *_Nullable result, NSError *_Nullable error))completion;

/// POST /password/reset {country_code, phone, code, new_password}。
- (void)resetPasswordWithCountryCode:(NSString *)countryCode phone:(NSString *)phone code:(NSString *)code
                         newPassword:(NSString *)newPassword completion:(void (^)(NSError *_Nullable error))completion;

/// POST /account/restore {restore_ticket}。不签 token。
- (void)restoreAccountWithTicket:(NSString *)ticket completion:(void (^)(NSError *_Nullable error))completion;

/// GET /users/me/security。
- (void)fetchSecurityStateWithToken:(NSString *)token
                         completion:(void (^)(IMSecurityState *_Nullable state, NSError *_Nullable error))completion;

/// DELETE /users/me/legacy-phone：「不再提示」清掉资料里自填的旧号码（§15.1，幂等）。
- (void)dismissLegacyPhoneWithToken:(NSString *)token completion:(void (^)(NSError *_Nullable error))completion;

/// POST /users/me/verify-code {lang}：发 verify 场景验证码到本人号码，回 phone_masked。
- (void)sendVerifyCodeWithToken:(NSString *)token
                     completion:(void (^)(IMSMSSendResult *_Nullable result, NSError *_Nullable error))completion;

/// POST /users/me/password {proof, new_password}。设置（原本没密码）或修改；修改成功时就地换掉本机续期凭据。
- (void)updatePasswordWithToken:(NSString *)token proof:(IMIdentityProof *)proof newPassword:(NSString *)newPassword
                     completion:(void (^)(NSError *_Nullable error))completion;

/// POST /users/me/phone {proof, country_code, phone, code} → phone_masked。错误 data.field 标明 proof / code。
- (void)bindPhoneWithToken:(NSString *)token proof:(IMIdentityProof *)proof countryCode:(NSString *)countryCode
                     phone:(NSString *)phone code:(NSString *)code
                completion:(void (^)(NSString *_Nullable phoneMasked, NSError *_Nullable error))completion;

/// 本机会话里存的用户名不可信（手机号 / 邮箱形态，见 IMStoredUsernameIsTrusted）：拉一次 /users/me，拿到服务端 username 后覆盖落盘。
/// 拿到之前旧值原样保留（内存与磁盘）：只靠 legacyPassword 的老安装还要用它重登。
- (void)repairStoredUsernameIfNeeded;

@end

NS_ASSUME_NONNULL_END
