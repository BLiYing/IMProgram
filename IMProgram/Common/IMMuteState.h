//  IMMuteState.h
//  定时免打扰统一判定（通知第二期 · 第二批，NOTIFICATIONS_P1_DESIGN §4.3）：三端同名纯函数
//  IMIsMutedNow / 到期文案分类器。**所有**过去直接读 `muted` 的地方都要改走 IMIsMutedNow——
//  会话列表铃铛与未读变灰、IMTabUnreadCount、IMSocketManager+Alerts 的 ctx.muted、例外列表过滤、
//  「添加例外」选择页过滤、聊天详情页状态（见 §6.2 iOS 列）。漏一处就是"这里显示免打扰、那里照样响"。
//  对端 im-android data/MuteState.kt、im-web src/muteState.ts；向量 IMServer/docs/conformance/mute_state.json。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 有效免打扰 = muted && (muteUntil == 0 || nowMs < muteUntil)。
/// muteUntil==0 视为永久；nowMs==muteUntil 视为**已解除**（不是"还差一毫秒"）；
/// muted=false 时忽略残留的 muteUntil（不算免打扰）——与服务端 conversation.EffectiveMute 同口径。
FOUNDATION_EXPORT BOOL IMIsMutedNow(BOOL muted, int64_t muteUntilMs, int64_t nowMs);

/// 到期文案分类：today（同一天）/ tomorrow（差一个日历日）/ date（更晚）/ forever（muteUntil==0）。
/// 按**日历日**而非 24 小时整数倍比较，故"8 小时后跨过午夜"归 tomorrow、"7 天后"或"后天零点"归 date。
typedef NS_ENUM(NSInteger, IMMuteUntilKind) {
    IMMuteUntilKindForever = 0,
    IMMuteUntilKindToday,
    IMMuteUntilKindTomorrow,
    IMMuteUntilKindDate,
};

/// 分类结果：kind=today/tomorrow 时 time 非空（"HH:mm"，24 小时制，与协议时间戳算法无关，
/// 纯按 tzOffsetMinutes 数值推导，不经系统日历/时区库，避免 DST 造成分类漂移，向量按此假定核对）；
/// kind=date 时 month/day 非零（1-12 / 1-31）；kind=forever 时三者皆空/零。
@interface IMMuteUntilLabel : NSObject
@property (nonatomic, readonly) IMMuteUntilKind kind;
@property (nonatomic, copy, readonly, nullable) NSString *time;
@property (nonatomic, readonly) NSInteger month;
@property (nonatomic, readonly) NSInteger day;
@end

/// 仅应在 IMIsMutedNow 为真时调用（muteUntilMs<=nowMs 时的行为未在向量中约束，按"date"兜底不崩）。
/// timeZone 用于把绝对时间戳换算成"本地日历日"；传入固定时区是为了让向量可测（不依赖跑测试的机器时区）。
FOUNDATION_EXPORT IMMuteUntilLabel *IMMuteUntilLabelMake(int64_t muteUntilMs, int64_t nowMs, NSTimeZone *timeZone);

/// 展示文案拼装（详情页右值「至今天 11:00」/例外行「免打扰至...」共用的「至...」后缀，
/// 已代入 i18n 模板 notif.mute.until_today/_tomorrow/_date；不含"免打扰"/"永久"前后缀，那些由调用方按
/// 各自场景的字符串键拼）。timeZone 传 nil 用系统当前时区（展示用；分类器单测传固定时区）。
/// **不要在 kind=forever 时调用**——调用方应先判 muteUntilMs==0 走各自的"永久"文案。
FOUNDATION_EXPORT NSString *IMMuteUntilSuffixText(int64_t muteUntilMs, int64_t nowMs, NSTimeZone *_Nullable timeZone);

/// 聊天详情页「免打扰」行右值：关闭(common.off) / 至...(IMMuteUntilSuffixText) / 永久(common.permanent)。
FOUNDATION_EXPORT NSString *IMMuteDetailValueText(BOOL isMutedNow, int64_t muteUntilMs, int64_t nowMs);

/// 例外列表副标题：免打扰(forever) / 免打扰至...(timed)，mentionUnread 时追加"· @我仍提醒"变体。
/// 仅应在会话确实处于有效免打扰时调用（例外列表本身就是"muted=YES 且过滤过期"的会话集合）。
FOUNDATION_EXPORT NSString *IMMuteExceptionSubtitle(int64_t muteUntilMs, int64_t nowMs, BOOL mentionUnread);

NS_ASSUME_NONNULL_END
