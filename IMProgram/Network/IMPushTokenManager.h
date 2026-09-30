//  IMPushTokenManager.h
//  设备推送令牌注册与上报（M5 离线推送第一批）。PROTOCOL §6.14/§11 push/token、
//  IMServer/docs/design/PUSH_M5_DESIGN.md §1。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPushTokenManager : NSObject

+ (instancetype)shared;

/// App 启动调一次（幂等）：观察 socket 连接态，每次(重)连成功即尝试 `registerIfEligible`
/// （对齐"每次启动/登录都上报一次，幂等"的要求；registerForRemoteNotifications 本身廉价可重复调）。
- (void)start;

/// 登录后第一次进主页调用（IMMainTabBarController 每个实例只应调一次）：
/// 请求系统通知授权（alert|sound|badge）。若此前已授权/已拒绝，系统直接回原结果、不重复弹框
/// （PUSH_M5_DESIGN §5/§8-4：登录后第一次进主页直接弹）。完成后尝试 `registerIfEligible`。
- (void)requestAuthorizationOnFirstMainScreen;

/// 若「已登录 且 系统通知已授权 且 本机『接收离线推送』开」，调用 `registerForRemoteNotifications`；
/// 否则静默跳过（不强弹授权——授权只在 `requestAuthorizationOnFirstMainScreen` 触发）。
- (void)registerIfEligible;

/// AppDelegate `didRegisterForRemoteNotificationsWithDeviceToken:` 转发：转 hex、拼环境/bundle/locale，
/// PUT 上报（PROTOCOL §11）。未登录（currentToken 为空）时静默跳过。
- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;

/// AppDelegate `didFailToRegisterForRemoteNotificationsWithError:` 转发：仅记日志，不重试
/// （系统会在下次启动/网络恢复时自己再触发一次）。
- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;

/// 设置页「接收离线推送」关掉时调用：DELETE 本机令牌；此后 `registerIfEligible` 不会再注册。
- (void)disableAndDeleteToken;

/// 设置页「接收离线推送」打开时调用：若已获系统通知授权，立即重新走一遍注册+上报。
- (void)enableAndRegisterIfAuthorized;

@end

/// 纯函数：APNs device token（NSData）→ 小写 hex 字符串。数据为空回空串。
FOUNDATION_EXPORT NSString *IMPushTokenHexFromData(NSData *tokenData);

/// 纯函数：从 `embedded.mobileprovision` 原始文件字节解析 `Entitlements.aps-environment`
/// → "sandbox"（development）/ "production"（production 或解析失败/字段缺失时的保守回退）。
/// 该文件是 CMS 签名的二进制信封，中间嵌一段 `<?xml … </plist>` 明文 plist——按此规则截取后再解析
/// （PUSH_M5_DESIGN §1.1）。传空数据（如 App Store 包没有这个文件）回 "production"。
FOUNDATION_EXPORT NSString *IMPushEnvironmentFromMobileProvisionData(NSData *_Nullable rawMobileProvisionData);

/// 便利入口：真机读主 Bundle 里的 `embedded.mobileprovision`（找不到=App Store 包→"production"）。
/// 测试请直接用上面的纯函数注入样例数据，不要依赖真实签名包。
FOUNDATION_EXPORT NSString *IMPushEnvironmentDetect(void);

NS_ASSUME_NONNULL_END
