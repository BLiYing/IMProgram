//  IMAutoDelete.h
//  自动删除消息（IMServer/docs/design/AUTO_DELETE_DESIGN.md）的纯判定函数与档位表。
//  口径三端一字不差，向量 IMServer/docs/conformance/auto_delete.json（IMAutoDeleteTests 读它）；改口径先改向量。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 档位白名单（秒）：0=关 / 1 天 / 1 周 / 1 个月（30 天）。
FOUNDATION_EXPORT const int64_t IMAutoDeleteSecDay, IMAutoDeleteSecWeek, IMAutoDeleteSecMonth;

/// 是否合法档位（0/86400/604800/2592000）。
FOUNDATION_EXPORT BOOL IMAutoDeleteIsValidSec(int64_t sec);

/// 过期判定（设计稿 §2）：sec > 0 且 ts + sec*1000 <= now（含等号）。sec<=0 恒不过期。毫秒。
FOUNDATION_EXPORT BOOL IMAutoDeleteExpired(int64_t ts, int64_t sec, int64_t now);

/// 时间下界：sec>0 ? max(0, now - sec*1000) : 0。`ts <= floorTs`（且 floorTs>0 时）即过期。
FOUNDATION_EXPORT int64_t IMAutoDeleteFloorTs(int64_t sec, int64_t now);

/// 全部档位（顺序即选择页顺序）：@[@0, @86400, @604800, @2592000]。
FOUNDATION_EXPORT NSArray<NSNumber *> *IMAutoDeleteTiers(void);

/// 档位名：关闭 / 1 天 / 1 周 / 1 个月（走 i18n）。非白名单值按「关闭」处理。
FOUNDATION_EXPORT NSString *IMAutoDeleteTierTitle(int64_t sec);

/// 确认框里 {period} 用的短语（autodel.day/week/month）；关/非法返回空串。
FOUNDATION_EXPORT NSString *IMAutoDeletePeriodWord(int64_t sec);

/// 会话级改档位要不要先弹 destructive 确认：new>0 且（旧=关 或 new<旧）。放宽/关闭直接保存。
FOUNDATION_EXPORT BOOL IMAutoDeleteNeedsConfirm(int64_t oldSec, int64_t newSec);

/// 把服务端回来的任意 JSON 值收成档位秒（非数字/非白名单 = 0）。
FOUNDATION_EXPORT int64_t IMAutoDeleteSecFromJSON(id _Nullable value);

NS_ASSUME_NONNULL_END
