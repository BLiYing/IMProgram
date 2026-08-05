//  IMPresence.h
//  在线态（对齐后端 protocol.Presence* 的租约模型，2026-08-05）。
//
//  设计要点：服务端只推「上线」，不推「下线」——在线与否由 onlineUntil 到期本地判定。
//  好处是漏收一帧不会让状态永久陈旧，代价是对端离开后「在线」最长残留一个租约周期（约 5 分钟）。
//  故 isOnline 必须**每次读取时按当前时间重算**，不能缓存成 BOOL。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 在线态粗档（对齐后端 protocol.Presence* 字符串）。
typedef NS_ENUM(NSInteger, IMPresenceLevel) {
    IMPresenceLevelUnknown = 0,  // 未知（未取到快照）
    IMPresenceLevelOnline,       // 在线
    IMPresenceLevelRecently,     // 3 天内
    IMPresenceLevelLastWeek,     // 7 天内
    IMPresenceLevelLastMonth,    // 30 天内
    IMPresenceLevelLongAgo,      // 更早 / 从未上线
};

@interface IMPresence : NSObject

@property (nonatomic, assign) IMPresenceLevel level;
@property (nonatomic, assign) int64_t onlineUntil;  // 在线租约到期（毫秒）；0=无租约
@property (nonatomic, assign) int64_t lastSeen;     // 最后在线（毫秒）；0=未知/不可见

/// 当前是否在线：按**此刻**与租约比较（租约到期即自动降级，无需服务端下线帧）。
@property (nonatomic, readonly) BOOL isOnline;

/// 标题栏副标题文案：在线 / 刚刚在线 / N 分钟前 / 今天 HH:mm / 昨天 HH:mm / M月d日 / 最近在线…
/// 取不到任何信息时返回空串（调用方据此隐藏副标题，不显示占位）。
@property (nonatomic, readonly) NSString *subtitleText;

/// 从会话列表项解析（键 peer_presence / peer_online_until / peer_last_seen）。
+ (instancetype)presenceFromConversationDictionary:(nullable NSDictionary *)dict;

/// 从资料卡解析（键 presence / online_until / last_seen）。
+ (instancetype)presenceFromProfileDictionary:(nullable NSDictionary *)dict;

/// 从 presence 帧解析（键 status / online_until / last_seen）。
+ (instancetype)presenceFromFrameDictionary:(nullable NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
