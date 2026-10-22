//  IMAutoDelete.h
//  自动删除消息（IMServer/docs/design/AUTO_DELETE_DESIGN.md）的纯判定函数与档位表。
//  口径三端一字不差，向量 IMServer/docs/conformance/auto_delete.json（IMAutoDeleteTests 读它）；改口径先改向量。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 常用秒数。
FOUNDATION_EXPORT const int64_t IMAutoDeleteSecMinute2, IMAutoDeleteSecHour, IMAutoDeleteSecDay, IMAutoDeleteSecWeek, IMAutoDeleteSecMonth, IMAutoDeleteSecYear;

/// 是否合法档位：0 或 IMAutoDeleteCustomTiers() 里的 18 档之一（其余一律非法，服务端同口径回 100001）。
FOUNDATION_EXPORT BOOL IMAutoDeleteIsValidSec(int64_t sec);

/// 过期判定（v2 设计稿 §2）：sec > 0 && ts >= from && ts + sec*1000 <= now（含等号）。sec<=0 恒不过期；
/// `ts < from`（设置生效之前的消息）永不过期。毫秒。
FOUNDATION_EXPORT BOOL IMAutoDeleteExpired(int64_t ts, int64_t sec, int64_t from, int64_t now);

/// 过期窗口 [lo, hi] = [from, now - sec*1000]（ts 落在窗口内即过期）。sec<=0 或 hi<lo（窗口为空）返回 NO、不写出参。
FOUNDATION_EXPORT BOOL IMAutoDeleteWindow(int64_t sec, int64_t from, int64_t now, int64_t *_Nullable lo, int64_t *_Nullable hi);

/// 档位变更系统消息 timestamp=sysTs 时本次生效的 from：sec>0 ? sysTs+1 : 0（通知自己不过期）。服务端算好随帧下发，
/// 本端不自己算；留给向量测试对口径。
FOUNDATION_EXPORT int64_t IMAutoDeleteFromAfterSystemMessage(int64_t sysTs, int64_t sec);

/// 一个会话的自动删除设置（sec + from 恒成对出现、一起覆盖）。不可变。
@interface IMAutoDeleteConfig : NSObject
@property (nonatomic, assign, readonly) int64_t sec;   ///< 0=关
@property (nonatomic, assign, readonly) int64_t from;  ///< 毫秒；本次设置生效时刻，ts<from 的消息永不过期
+ (instancetype)configWithSec:(int64_t)sec from:(int64_t)from;
@property (nonatomic, assign, readonly, getter=isActive) BOOL active; ///< sec>0
- (BOOL)isExpiredTimestamp:(int64_t)ts now:(int64_t)now;
- (BOOL)isEqualToConfig:(IMAutoDeleteConfig *)other;
@end

/// 把服务端 JSON 里的 auto_delete_sec + auto_delete_from 收成一份设置。非法档位 / sec>0 却没有 from（老服务端的个人档位语义）
/// 一律当关闭——否则 from=0 会让整段历史被追溯清掉。
FOUNDATION_EXPORT IMAutoDeleteConfig *IMAutoDeleteConfigFromJSON(id _Nullable secValue, id _Nullable fromValue);

/// 选择页固定行（顺序即页面顺序）：@[@0, @120, @86400, @604800, @2592000]（关闭 / 2 分钟 / 1 天 / 1 周 / 1 个月）。
FOUNDATION_EXPORT NSArray<NSNumber *> *IMAutoDeleteTiers(void);

/// 「自定义」弹窗 18 档（升序，不含 0）：2 分钟、1 小时、1–6 天、1–3 周、1–6 个月（30 天）、1 年（365 天）。
FOUNDATION_EXPORT NSArray<NSNumber *> *IMAutoDeleteCustomTiers(void);

/// 「自定义」行是否该打 ✓ 并显示右值：合法的正档位且不在固定行里（如 3 天）。选到与固定行相同的值（如 1 天）✓ 归固定行。
FOUNDATION_EXPORT BOOL IMAutoDeleteIsCustomSelection(int64_t sec);

/// 任意档位的时长文案（autodel.unit.* 复数键）。折算优先级：整除 365 天→年；30 天→月；7 天→周；1 天→天；3600→小时；否则分钟。
/// 所以 30 天=1 个月、7 天=1 周、120 秒=2 分钟。sec<=0 返回空串（不做「关闭」判断）。
FOUNDATION_EXPORT NSString *IMAutoDeleteDurationText(int64_t sec);

/// 档位名：0/非法 -> 关闭（common.off）；其余 = IMAutoDeleteDurationText。
FOUNDATION_EXPORT NSString *IMAutoDeleteTierTitle(int64_t sec);

/// 确认框里 {period} 用的短语（同 IMAutoDeleteDurationText）；关/非法返回空串。
FOUNDATION_EXPORT NSString *IMAutoDeletePeriodWord(int64_t sec);

/// 会话级改档位要不要先弹说明确认框（v2：非 destructive、不追溯）：new>0 且 new != 旧。关闭不弹。
FOUNDATION_EXPORT BOOL IMAutoDeleteNeedsConfirm(int64_t oldSec, int64_t newSec);

/// 把服务端回来的任意 JSON 值收成档位秒（非数字/非白名单 = 0）。
FOUNDATION_EXPORT int64_t IMAutoDeleteSecFromJSON(id _Nullable value);

NS_ASSUME_NONNULL_END
