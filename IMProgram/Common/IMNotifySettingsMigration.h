//  IMNotifySettingsMigration.h
//  账号级通知设置迁移/合并的纯逻辑（M5，PROTOCOL §6.13）：私聊/群聊 {enabled,preview,sound} 与
//  badge.include_muted 从「每设备本地」迁到「账号级、服务端存、多端同步」。应用内三项（声音/振动/横幅）
//  与其余 IMNotificationSettings 字段**不受影响**，仍是每设备本地——本文件只管这四个搬家的字段。
//
//  纯函数便于单测（不依赖网络/单例/时钟）；编排（何时 GET/PUT、失败重试、写回 IMNotificationSettings）
//  在 Network/IMAccountNotifySettingsSync.m。
//
//  **跨端对称**：同一套「exists=false 迁移本地上去 / exists=true 覆盖本地 / dirty 优先重推」语义
//  由 im-android（NotificationSettingsStore.kt 的 sync 分支）与 im-web（notifySettings.ts 的迁移逻辑）
//  各自实现，三端读同一份 PROTOCOL §6.13 契约——改这里的判定前先看看三端是否需要一起改。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 账号级通知设置的四个字段（私聊/群聊各三项 + 角标口径），纯数据对象，不依赖 IMNotificationSettings 单例。
@interface IMNotifySettingsValues : NSObject
@property (nonatomic, assign) BOOL privateEnabled;
@property (nonatomic, assign) BOOL privatePreview;
@property (nonatomic, copy) NSString *privateSound;
@property (nonatomic, assign) BOOL groupEnabled;
@property (nonatomic, assign) BOOL groupPreview;
@property (nonatomic, copy) NSString *groupSound;
@property (nonatomic, assign) BOOL badgeIncludeMuted;
@end

/// 一轮同步该做什么：
/// - Push：把本地现值 PUT 上去（迁移，或本地此前失败待重推的 dirty 值）。
/// - ApplyServer：用服务端返回值覆盖本地。
typedef NS_ENUM(NSInteger, IMNotifySettingsSyncAction) {
    IMNotifySettingsSyncActionPush = 0,
    IMNotifySettingsSyncActionApplyServer,
};

/// 决定本轮同步动作（纯函数）：
/// - `dirty`=YES（上一次本地变更 PUT 失败、还没确认同步成功）→ 恒 Push，且**不管 `serverExists`**——
///   这一轮优先把未确认的本地值送上去，避免被服务端的旧值覆盖冲掉刚做的本地修改。
/// - `dirty`=NO 且 `serverExists`=NO（服务端还没有这份设置）→ Push（一次性迁移）。
/// - `dirty`=NO 且 `serverExists`=YES → ApplyServer（覆盖本地，服务端为准）。
FOUNDATION_EXPORT IMNotifySettingsSyncAction IMNotifySettingsSyncDecideAction(BOOL dirty, BOOL serverExists);

/// 收到 notify_settings_update 帧时，版本号是否比本地已知的新（纯函数，> 而非 >=：相同版本不必重拉）。
FOUNDATION_EXPORT BOOL IMNotifySettingsShouldRefetchForVersion(int64_t localVersion, int64_t incomingVersion);

/// 本机的通知设置同步状态原本属于 owner，现在登录的是 uid：两者都非空且不同 = 换了账号，
/// 本地三项与待补推标记必须清掉（否则会把上一个账号的设置补推/迁移到新账号上）。owner 空 = 升级前的老数据。
FOUNDATION_EXPORT BOOL IMNotifySettingsOwnerSwitched(NSString * _Nullable owner, NSString * _Nullable uid);

/// 服务端 JSON `{private:{enabled,preview,sound},group:{...},badge:{include_muted}}` → 值对象。
/// 容错：字段缺失/类型不对一律回退安全默认（enabled/preview=YES、sound=default、includeMuted=NO），
/// 不因为一个坏字段让整份设置解析失败——与 IMNotificationSoundIDNormalize 同一口径。
FOUNDATION_EXPORT IMNotifySettingsValues *IMNotifySettingsValuesFromServerJSON(NSDictionary *_Nullable json);

/// 值对象 → PUT 请求体的 `settings` 字段（与 FromServerJSON 互逆，未知 sound 由服务端再规整一次）。
FOUNDATION_EXPORT NSDictionary *IMNotifySettingsValuesToServerJSON(IMNotifySettingsValues *values);

NS_ASSUME_NONNULL_END
