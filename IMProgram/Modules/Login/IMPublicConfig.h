//  IMPublicConfig.h
//  登录前就要知道的部署开关：免鉴权 GET /api/v1/public-config → data.{register_enabled, sms_available, sms_regions, register_methods}
//  （PROTOCOL §11 / §7.3）。登录页据此决定页签、「忘记密码？」「用户名注册」与地区；解析在 IMLoginConfig（Common/IMPhoneAuth）。
//  注册页打开 / 切到注册页签 / 改服务器地址时读一次：false 则注册页提示「管理员已暂停注册新账号」并禁用提交。
//  拉不到（离线 / 老服务端 404 / 字段缺失）一律按「开放」处理——服务端注册接口会回 200007 兜底。

#import <Foundation/Foundation.h>
#import "IMPhoneAuth.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMPublicConfig : NSObject

/// 解析信封响应体里的 register_enabled。只有 `code == 0` 且 `data.register_enabled` 是布尔 false 时返回 NO；
/// 非 JSON / code≠0 / data 缺失 / 字段缺失或类型不对 → YES（未知按开放，服务端仍会拦）。
+ (BOOL)registerEnabledFromResponseData:(nullable NSData *)data;

/// 匿名拉取并回调 register_enabled（主线程）。**只有最近一次发起的请求会回调**：
/// 服务器地址改了、或连点页签时，先发后到的旧响应直接丢弃，不会覆盖新结果。失败回调 YES。
- (void)fetchRegisterEnabledWithScheme:(nullable NSString *)scheme
                                  host:(NSString *)host
                            completion:(void (^)(BOOL registerEnabled))completion;

/// 匿名拉取整份登录配置（主线程）。同样只有最近一次请求会回调；拉不到回 IMLoginConfig.fallbackConfig，failed=YES。
- (void)fetchConfigWithScheme:(nullable NSString *)scheme
                         host:(NSString *)host
                   completion:(void (^)(IMLoginConfig *config, BOOL failed))completion;

/// 作废在途请求（其回调不再触发）。离开注册页签时调用。
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
