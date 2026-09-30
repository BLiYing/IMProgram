//  IMHTTPService+Push.h
//  M5 离线推送第一批：设备推送令牌上报 + 账号级通知设置读写（PROTOCOL §6.13/§6.14、§11 push/token、notify-settings）。
//  拆分理由同 +ConvQueries：这两组接口只被 IMPushTokenManager / IMAccountNotifySettingsSync 调用，
//  与登录、上传、好友等既有接口没有共享状态，天然独立成 category（CODING_STYLE §7 ②）。

#import "IMHTTPService.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMHTTPService (Push)

/// 登记本设备推送令牌：PUT /api/v1/push/token {provider,token,environment,bundle_id,locale}。
/// 令牌挂在本次登录会话（sid）上，退出/被踢/改密下线时随会话失效；同一 token 已属于别的会话时
/// 服务端先删旧行（换号登录不串推）。completion 在主线程回调。
- (void)registerPushTokenWithToken:(NSString *)token
                           provider:(NSString *)provider
                     deviceTokenHex:(NSString *)deviceTokenHex
                        environment:(NSString *)environment
                           bundleID:(NSString *)bundleID
                             locale:(NSString *)locale
                         completion:(void (^)(NSError *_Nullable error))completion;

/// 删除本设备推送令牌（设置里关闭「接收离线推送」时调）：DELETE /api/v1/push/token。幂等。
- (void)deletePushTokenWithToken:(NSString *)token
                       completion:(void (^)(NSError *_Nullable error))completion;

/// 账号级通知设置：GET /api/v1/notify-settings → data `{version,exists,settings}`（PROTOCOL §6.13）。
/// `exists=false` 表示服务端还没有这份设置（返回的是默认值）。completion 在主线程回调。
- (void)notifySettingsWithToken:(NSString *)token
                      completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion;

/// 整体替换账号级通知设置：PUT /api/v1/notify-settings {settings} → data `{version,exists:true,settings}`。
/// 服务端规整 sound 枚举、bump 版本并推 notify_settings_update 给本人全部在线设备（含发起端自身）。
- (void)updateNotifySettingsWithToken:(NSString *)token
                              settings:(NSDictionary *)settings
                            completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
