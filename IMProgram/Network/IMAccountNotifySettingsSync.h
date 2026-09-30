//  IMAccountNotifySettingsSync.h
//  账号级通知设置（私聊/群聊 enabled·preview·sound + badge.include_muted）与服务端同步的编排
//  （M5，PROTOCOL §6.13）。决策纯逻辑见 Common/IMNotifySettingsMigration；本类只管"何时调、调完写回哪"，
//  写法照抄 IMDownloadSettingsStore（同一模式：start 时订阅 + 首次拉，socket 连上补拉，账号级配置变更帧重拉）。
//
//  迁移语义：登录/启动 GET 一次——服务端还没有这份设置（exists=false）→ 把本地现值 PUT 上去（一次性迁移）；
//  已有（exists=true）→ 覆盖本地 IMNotificationSettings 的私聊/群聊/角标字段、记住 version。
//  本地在这之后的编辑（设置页改开关/提示音/角标口径）→ 立即 PUT；失败保留本地值、置 dirty，
//  下次启动/重连时优先把这份 dirty 值重推（而不是被服务端旧值覆盖）。
//
//  应用内三项（声音/振动/横幅）与其余 IMNotificationSettings 字段不受影响，仍是每设备本地——
//  本类只搬私聊/群聊/角标这四个字段，其余读写路径对 App 其它地方完全透明（仍是 IMNotificationSettings.shared）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAccountNotifySettingsSync : NSObject

+ (instancetype)shared;

/// 开始观察 notify_settings_update / socket 连接态并首次同步（App 启动调一次，幂等）。
- (void)start;

/// 手动触发一轮同步（未登录时静默跳过）：按 IMNotifySettingsSyncDecideAction 走 Push 或 ApplyServer。
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
