//  IMAutoDelete.m

#import "IMAutoDelete.h"
#import "IMLocalization.h"

const int64_t IMAutoDeleteSecDay = 86400;
const int64_t IMAutoDeleteSecWeek = 604800;
const int64_t IMAutoDeleteSecMonth = 2592000;

BOOL IMAutoDeleteIsValidSec(int64_t sec) {
    return sec == 0 || sec == IMAutoDeleteSecDay || sec == IMAutoDeleteSecWeek || sec == IMAutoDeleteSecMonth;
}

BOOL IMAutoDeleteExpired(int64_t ts, int64_t sec, int64_t now) {
    return sec > 0 && ts + sec * 1000 <= now;
}

int64_t IMAutoDeleteFloorTs(int64_t sec, int64_t now) {
    return sec > 0 ? MAX((int64_t)0, now - sec * 1000) : 0;
}

NSArray<NSNumber *> *IMAutoDeleteTiers(void) {
    return @[@0, @(IMAutoDeleteSecDay), @(IMAutoDeleteSecWeek), @(IMAutoDeleteSecMonth)];
}

NSString *IMAutoDeletePeriodWord(int64_t sec) {
    switch (sec) {
        case 86400: return IMLocalized(@"autodel.day");
        case 604800: return IMLocalized(@"autodel.week");
        case 2592000: return IMLocalized(@"autodel.month");
        default: return @"";
    }
}

NSString *IMAutoDeleteTierTitle(int64_t sec) {
    NSString *w = IMAutoDeletePeriodWord(sec);
    return w.length > 0 ? w : IMLocalized(@"common.off");
}

BOOL IMAutoDeleteNeedsConfirm(int64_t oldSec, int64_t newSec) {
    return newSec > 0 && (oldSec <= 0 || newSec < oldSec);
}

int64_t IMAutoDeleteSecFromJSON(id value) {
    if (![value isKindOfClass:NSNumber.class]) { return 0; }
    int64_t v = [value longLongValue];
    return IMAutoDeleteIsValidSec(v) ? v : 0;
}
