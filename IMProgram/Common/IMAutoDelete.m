//  IMAutoDelete.m

#import "IMAutoDelete.h"
#import "IMLocalization.h"

const int64_t IMAutoDeleteSecMinute2 = 120;
const int64_t IMAutoDeleteSecHour = 3600;
const int64_t IMAutoDeleteSecDay = 86400;
const int64_t IMAutoDeleteSecWeek = 604800;
const int64_t IMAutoDeleteSecMonth = 2592000;
const int64_t IMAutoDeleteSecYear = 31536000;

BOOL IMAutoDeleteIsValidSec(int64_t sec) {
    return sec == 0 || [IMAutoDeleteCustomTiers() containsObject:@(sec)];
}

BOOL IMAutoDeleteExpired(int64_t ts, int64_t sec, int64_t from, int64_t now) {
    return sec > 0 && ts >= from && ts + sec * 1000 <= now;
}

BOOL IMAutoDeleteWindow(int64_t sec, int64_t from, int64_t now, int64_t *lo, int64_t *hi) {
    if (sec <= 0) { return NO; }
    int64_t h = now - sec * 1000;
    if (h < from) { return NO; }
    if (lo) { *lo = from; }
    if (hi) { *hi = h; }
    return YES;
}

int64_t IMAutoDeleteFromAfterSystemMessage(int64_t sysTs, int64_t sec) {
    return sec > 0 ? sysTs + 1 : 0;
}

@implementation IMAutoDeleteConfig
+ (instancetype)configWithSec:(int64_t)sec from:(int64_t)from {
    IMAutoDeleteConfig *c = [self new];
    c->_sec = sec > 0 ? sec : 0;
    c->_from = c->_sec > 0 ? MAX((int64_t)0, from) : 0;
    return c;
}
- (BOOL)isActive { return _sec > 0; }
- (BOOL)isExpiredTimestamp:(int64_t)ts now:(int64_t)now { return IMAutoDeleteExpired(ts, _sec, _from, now); }
- (BOOL)isEqualToConfig:(IMAutoDeleteConfig *)o { return o && _sec == o.sec && _from == o.from; }
@end

IMAutoDeleteConfig *IMAutoDeleteConfigFromJSON(id secValue, id fromValue) {
    int64_t sec = IMAutoDeleteSecFromJSON(secValue);
    // 缺 from、或 from<=0 且 sec>0 都是脏数据（正常下发的 from=系统消息时间+1>0）：按关闭，避免从 1970 起追溯清空
    if (sec > 0 && (![fromValue isKindOfClass:NSNumber.class] || [fromValue longLongValue] <= 0)) { sec = 0; }
    return [IMAutoDeleteConfig configWithSec:sec from:sec > 0 ? [fromValue longLongValue] : 0];
}

NSArray<NSNumber *> *IMAutoDeleteTiers(void) {
    return @[@0, @(IMAutoDeleteSecMinute2), @(IMAutoDeleteSecDay), @(IMAutoDeleteSecWeek), @(IMAutoDeleteSecMonth)];
}

NSArray<NSNumber *> *IMAutoDeleteCustomTiers(void) {
    static NSArray<NSNumber *> *tiers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSNumber *> *a = [NSMutableArray arrayWithObjects:@(IMAutoDeleteSecMinute2), @(IMAutoDeleteSecHour), nil];
        for (int64_t d = 1; d <= 6; d++) { [a addObject:@(d * IMAutoDeleteSecDay)]; }
        for (int64_t w = 1; w <= 3; w++) { [a addObject:@(w * IMAutoDeleteSecWeek)]; }
        for (int64_t m = 1; m <= 6; m++) { [a addObject:@(m * IMAutoDeleteSecMonth)]; }
        [a addObject:@(IMAutoDeleteSecYear)];
        tiers = [a copy];
    });
    return tiers;
}

BOOL IMAutoDeleteIsCustomSelection(int64_t sec) {
    return sec > 0 && IMAutoDeleteIsValidSec(sec) && ![IMAutoDeleteTiers() containsObject:@(sec)];
}

NSString *IMAutoDeleteDurationText(int64_t sec) {
    if (sec <= 0) { return @""; }
    NSString *key; int64_t unit;
    if (sec % IMAutoDeleteSecYear == 0) { key = @"autodel.unit.year"; unit = IMAutoDeleteSecYear; }
    else if (sec % IMAutoDeleteSecMonth == 0) { key = @"autodel.unit.month"; unit = IMAutoDeleteSecMonth; }
    else if (sec % IMAutoDeleteSecWeek == 0) { key = @"autodel.unit.week"; unit = IMAutoDeleteSecWeek; }
    else if (sec % IMAutoDeleteSecDay == 0) { key = @"autodel.unit.day"; unit = IMAutoDeleteSecDay; }
    else if (sec % IMAutoDeleteSecHour == 0) { key = @"autodel.unit.hour"; unit = IMAutoDeleteSecHour; }
    else { key = @"autodel.unit.minute"; unit = 60; }
    return IMLocalizedFormat(key, (long)(sec / unit)); // stringsdict 复数键：参数是 long 个数
}

NSString *IMAutoDeletePeriodWord(int64_t sec) {
    return IMAutoDeleteIsValidSec(sec) ? IMAutoDeleteDurationText(sec) : @"";
}

NSString *IMAutoDeleteTierTitle(int64_t sec) {
    NSString *w = IMAutoDeletePeriodWord(sec);
    return w.length > 0 ? w : IMLocalized(@"common.off");
}

BOOL IMAutoDeleteNeedsConfirm(int64_t oldSec, int64_t newSec) {
    return newSec > 0 && newSec != oldSec;
}

int64_t IMAutoDeleteSecFromJSON(id value) {
    if (![value isKindOfClass:NSNumber.class]) { return 0; }
    int64_t v = [value longLongValue];
    return IMAutoDeleteIsValidSec(v) ? v : 0;
}
