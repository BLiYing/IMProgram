//  IMPublicConfig.h
//  登录前就要知道的部署开关：免鉴权 GET /api/v1/public-config → data.{register_enabled, sms_available, sms_regions, register_methods}
//  （PROTOCOL §11 / §7.3）。登录页据此决定页签、「忘记密码？」、自动注册提示与地区；解析在 IMLoginConfig（Common/IMPhoneAuth）。
//  登录页打开 / 改服务器地址时读一次。register_enabled 只解析不驱动界面：注册只走验证码登录即注册，关闭时由服务端回 200007。
//  拉不到（离线 / 老服务端 404 / 字段缺失）一律按老服务端口径处理。

#import <Foundation/Foundation.h>
#import "IMPhoneAuth.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMPublicConfig : NSObject

/// 匿名拉取整份登录配置（主线程）。**只有最近一次发起的请求会回调**：服务器地址改了时，先发后到的旧响应直接丢弃，
/// 不会覆盖新结果。拉不到回 IMLoginConfig.fallbackConfig，failed=YES。
- (void)fetchConfigWithScheme:(nullable NSString *)scheme
                         host:(NSString *)host
                   completion:(void (^)(IMLoginConfig *config, BOOL failed))completion;

/// 作废在途请求（其回调不再触发）。服务器地址非法时调用。
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
