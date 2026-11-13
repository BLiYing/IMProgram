//  IMHTTPService+TwoStep.h
//  两步验证（TOTP + 恢复码）REST，契约 ../IMServer/docs/PROTOCOL.md §7.1。
//  业务错误 HTTP 400 但响应体是标准信封：本文件所有请求都保留业务码，并把 data 里的 ticket / attempts_left 挂进 NSError.userInfo。
//  **日志红线**：验证码 / 密钥 / 恢复码 / ticket 不得写日志（HTTP 层统一日志已按键名脱敏，见 IMHTTPLogFormatter）。

#import "IMHTTPService.h"
#import "IMTwoStep.h"
#import "IMPhoneAuth.h"

NS_ASSUME_NONNULL_BEGIN

/// NSError.userInfo 键：200020 的登录凭证（NSString，只留内存，离开二步页即丢弃）。
FOUNDATION_EXPORT NSString * const IMErrorTwoStepTicketKey;
/// NSError.userInfo 键：200021（登录第二步）剩余可尝试次数（NSNumber）。
FOUNDATION_EXPORT NSString * const IMErrorTwoStepAttemptsLeftKey;

/// 把响应 `data` 里的 ticket / attempts_left 附到错误的 userInfo（码与文案不变）。body 里没有就原样返回。
FOUNDATION_EXPORT NSError *IMErrorByAttachingTwoStepInfo(NSError *error, NSDictionary *_Nullable body);

/// setup 的结果：密钥只存在于这个对象里（内存），不落盘不写日志。
@interface IMTwoStepSetup : NSObject
@property (nonatomic, copy) NSString *secret;      ///< 无分隔的 Base32
@property (nonatomic, copy) NSString *otpauthURI;  ///< 二维码内容，客户端本地绘制
@property (nonatomic, assign) NSTimeInterval expiresIn;
@end

@interface IMHTTPService (TwoStep)

/// GET /users/me/two-step。主线程回调。
- (void)fetchTwoStepStateWithToken:(NSString *)token
                        completion:(void (^)(IMTwoStepState *_Nullable state, NSError *_Nullable error))completion;

/// POST /users/me/two-step/setup {proof}。200002 密码错、200043 验证码错、200024 已开启、200025 服务端未启用、100002 限流。
- (void)setupTwoStepWithToken:(NSString *)token proof:(IMIdentityProof *)proof
                   completion:(void (^)(IMTwoStepSetup *_Nullable setup, NSError *_Nullable error))completion;

/// POST /users/me/two-step/enable {code}。成功回 10 个恢复码（唯一一次明文）。200021 码不对、200022 待确认超时。
- (void)enableTwoStepWithToken:(NSString *)token code:(NSString *)code
                    completion:(void (^)(NSArray<NSString *> *_Nullable recoveryCodes, NSError *_Nullable error))completion;

/// POST /users/me/two-step/disable {proof, code}；code 可为动态码或恢复码。
- (void)disableTwoStepWithToken:(NSString *)token proof:(IMIdentityProof *)proof code:(NSString *)code
                     completion:(void (^)(NSError *_Nullable error))completion;

/// POST /users/me/two-step/recovery-codes {proof, code}；旧码全部作废，回新的 10 个。
- (void)regenerateRecoveryCodesWithToken:(NSString *)token proof:(IMIdentityProof *)proof code:(NSString *)code
                              completion:(void (^)(NSArray<NSString *> *_Nullable recoveryCodes, NSError *_Nullable error))completion;

/// POST /login/two-step {ticket, code}：成功体与 /login 逐字段相同，走同一条「登录成功」收尾（缓存 token、落盘续期凭据、擦密码）。
/// 回 token 与服务端分配的内部 ID。错误保留业务码；200021 带 IMErrorTwoStepAttemptsLeftKey。主线程回调。
- (void)loginTwoStepWithTicket:(NSString *)ticket code:(NSString *)code
                    completion:(void (^)(NSString *_Nullable token, NSString *_Nullable userID, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
