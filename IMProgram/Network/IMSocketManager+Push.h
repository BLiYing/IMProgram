//  IMSocketManager+Push.h
//  前后台状态上报 app_state（PROTOCOL §6.12，M5）+ 账号级通知设置版本变更 notify_settings_update（§6.13）。
//  与 +CallRecord/+Sync 同一拆分理由：一组内聚方法归自己的 category 文件，主实现只留调用口子
//  （CODING_STYLE §7 ②）；IMSocketManager.m 已逼近体量门禁的历史欠账上限（1600 行，只准降不准升），
//  新逻辑一律不进主文件。

#import "IMSocketManager.h"

NS_ASSUME_NONNULL_BEGIN

/// 账号级通知设置版本变更（M5，PROTOCOL §6.13）广播（主线程）：IMAccountNotifySettingsSync 据此
/// 按版本判断是否重拉 GET /notify-settings。userInfo[@"version"] = NSNumber(int64_t)。
extern NSNotificationName const IMSocketDidReceiveNotifySettingsUpdateNotification;

@interface IMSocketManager (Push)

/// App 进入后台（SceneDelegate `sceneDidEnterBackground` 调用一次）：已连接则发
/// `{type:"app_state",data:{state:"background"}}`；未连接静默——帧丢了只退化成"60s 心跳超时前不推"，
/// 不会多推（PROTOCOL §6.12）。
- (void)noteAppDidEnterBackground;

/// App 回到前台（SceneDelegate `sceneWillEnterForeground` 调用一次）：记下"现在是前台"，
/// 已连接则立即补发一次 foreground；若这时连接还没恢复，等 handshake 成功后自动补发
/// （见 `sendAppStateAfterHandshake`，主实现在握手成功处调用）。
- (void)noteAppDidBecomeActive;

@end

NS_ASSUME_NONNULL_END
