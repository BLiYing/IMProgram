//  IMHTTPService+Email.h
//  邮箱登录 REST，契约 ../IMServer/docs/PROTOCOL.md §7.2。
//  业务错误 HTTP 400 但响应体是标准信封：本文件所有请求都保留业务码，并把 data 里的 attempts_left / retry_after_sec 挂进 NSError.userInfo。
//  **日志红线**：密码 / 验证码不得写日志（HTTP 层统一日志按键名脱敏；email 值由 IMHTTPLogFormatter 脱敏成 a***@domain）。

#import "IMHTTPService.h"
#import "IMEmailLogin.h"
#import "IMPhoneAuth.h"

NS_ASSUME_NONNULL_BEGIN

/// NSError.userInfo 键：200032 剩余可尝试次数（NSNumber）。
FOUNDATION_EXPORT NSString * const IMErrorEmailAttemptsLeftKey;
/// NSError.userInfo 键：100002 / 200033 距可重发的秒数（NSNumber，0 = 现在就能重发）。
FOUNDATION_EXPORT NSString * const IMErrorEmailRetryAfterKey;

/// 把响应 `data` 里的 attempts_left / retry_after_sec 附到错误的 userInfo（码与文案不变）。body 里没有就原样返回。
FOUNDATION_EXPORT NSError *IMErrorByAttachingEmailInfo(NSError *error, NSDictionary *_Nullable body);
/// 读错误上的附加值；没有返回 -1。
FOUNDATION_EXPORT NSInteger IMEmailAttemptsLeftFromError(NSError *_Nullable error);
FOUNDATION_EXPORT NSInteger IMEmailRetryAfterFromError(NSError *_Nullable error);

/// send-code 成功体。
@interface IMEmailSendResult : NSObject
@property (nonatomic, assign) NSInteger expiresIn;    ///< 默认 600
@property (nonatomic, assign) NSInteger resendAfter;  ///< 默认 60
@end

@interface IMHTTPService (Email)

/// GET /users/me/email。主线程回调。
- (void)fetchEmailStateWithToken:(NSString *)token
                      completion:(void (^)(IMEmailState *_Nullable state, NSError *_Nullable error))completion;

/// POST /users/me/email/send-code {email, proof, lang}。绑定与更换共用。
/// 200002 密码错、200043 / 200044 验证码错 / 过期、200030 格式、200031 已被占用、200035 与当前相同、200036 未启用、200037 发信失败、100002 限流（带 retry_after_sec）。
- (void)sendEmailCodeWithToken:(NSString *)token email:(NSString *)email proof:(IMIdentityProof *)proof
                    completion:(void (^)(IMEmailSendResult *_Nullable result, NSError *_Nullable error))completion;

/// POST /users/me/email/verify {email, code, lang}。成功回已绑定状态。200032 带 attempts_left，200033 带 retry_after_sec。
- (void)verifyEmailWithToken:(NSString *)token email:(NSString *)email code:(NSString *)code
                  completion:(void (^)(IMEmailState *_Nullable bound, NSError *_Nullable error))completion;

/// POST /users/me/email/unbind {proof}。200034 未绑定、200002 密码错、200043 验证码错。
- (void)unbindEmailWithToken:(NSString *)token proof:(IMIdentityProof *)proof
                  completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
