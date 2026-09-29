//  IMMuteState.m

#import "IMMuteState.h"
#import "IMLocalization.h"

BOOL IMIsMutedNow(BOOL muted, int64_t muteUntilMs, int64_t nowMs) {
    if (!muted) { return NO; }
    return muteUntilMs == 0 || nowMs < muteUntilMs;
}

static int64_t const kIMDayMs = 86400000LL;

/// 向下取整除法（负数安全；本函数里的操作数在真实时间戳下恒为非负，防御性写法不为它专门测）。
static int64_t IMFloorDiv(int64_t a, int64_t b) {
    int64_t q = a / b;
    if ((a % b != 0) && ((a < 0) != (b < 0))) { q -= 1; }
    return q;
}

@implementation IMMuteUntilLabel
- (instancetype)initWithKind:(IMMuteUntilKind)kind time:(nullable NSString *)time month:(NSInteger)month day:(NSInteger)day {
    if ((self = [super init])) {
        _kind = kind;
        _time = [time copy];
        _month = month;
        _day = day;
    }
    return self;
}
@end

/// "HH:mm" 由 dayLocalMs（已加时区偏移的绝对毫秒）对一天取余推出，不经日历库——与下面按毫秒
/// 分桶的 day index 算法同一套数学，避免 NSCalendar 的 DST 规则把两者算出不一致的答案。
static NSString *IMTimeOfDayString(int64_t localMs) {
    int64_t remainder = ((localMs % kIMDayMs) + kIMDayMs) % kIMDayMs;
    NSInteger hour = (NSInteger)(remainder / 3600000);
    NSInteger minute = (NSInteger)((remainder % 3600000) / 60000);
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)hour, (long)minute];
}

IMMuteUntilLabel *IMMuteUntilLabelMake(int64_t muteUntilMs, int64_t nowMs, NSTimeZone *timeZone) {
    if (muteUntilMs == 0) {
        return [[IMMuteUntilLabel alloc] initWithKind:IMMuteUntilKindForever time:nil month:0 day:0];
    }
    int64_t offsetMs = (int64_t)(timeZone.secondsFromGMT) * 1000;
    int64_t localNow = nowMs + offsetMs;
    int64_t localUntil = muteUntilMs + offsetMs;
    int64_t dayNow = IMFloorDiv(localNow, kIMDayMs);
    int64_t dayUntil = IMFloorDiv(localUntil, kIMDayMs);
    int64_t dayDiff = dayUntil - dayNow;

    if (dayDiff == 0) {
        return [[IMMuteUntilLabel alloc] initWithKind:IMMuteUntilKindToday time:IMTimeOfDayString(localUntil) month:0 day:0];
    }
    if (dayDiff == 1) {
        return [[IMMuteUntilLabel alloc] initWithKind:IMMuteUntilKindTomorrow time:IMTimeOfDayString(localUntil) month:0 day:0];
    }
    // 更晚（或异常的 dayDiff<0，理论上调用方只在 IMIsMutedNow 为真时调用不会发生）：读日历日的月/日。
    // 用固定 UTC 日历把"已加时区偏移的绝对毫秒"当成 UTC 瞬间读字段——这与上面按毫秒分桶的 day index
    // 算法是同一套数学（都相当于"先平移再当 UTC 处理"），二者不会因 NSCalendar 的 DST 规则而对不上。
    static NSCalendar *utcCalendar;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        utcCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        utcCalendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    });
    NSDate *asUTCInstant = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)localUntil / 1000.0];
    NSDateComponents *comps = [utcCalendar components:(NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:asUTCInstant];
    return [[IMMuteUntilLabel alloc] initWithKind:IMMuteUntilKindDate time:nil month:comps.month day:comps.day];
}

NSString *IMMuteUntilSuffixText(int64_t muteUntilMs, int64_t nowMs, NSTimeZone *timeZone) {
    NSTimeZone *tz = timeZone ?: NSTimeZone.systemTimeZone;
    IMMuteUntilLabel *label = IMMuteUntilLabelMake(muteUntilMs, nowMs, tz);
    switch (label.kind) {
        case IMMuteUntilKindToday:
            return IMLocalizedFormat(@"notif.mute.until_today", label.time);
        case IMMuteUntilKindTomorrow:
            return IMLocalizedFormat(@"notif.mute.until_tomorrow", label.time);
        case IMMuteUntilKindDate: {
            // "至 {date}"：本地化月日格式（zh "M月d日" / en "M/d" 由系统模板决定），不是硬编码分隔符。
            NSDateFormatter *df = [NSDateFormatter new];
            df.timeZone = tz;
            df.locale = IMLocalization.shared.locale;
            [df setLocalizedDateFormatFromTemplate:@"Md"];
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)muteUntilMs / 1000.0];
            NSString *dateStr = [df stringFromDate:date];
            if (dateStr.length == 0) { dateStr = [NSString stringWithFormat:@"%ld/%ld", (long)label.month, (long)label.day]; }
            return IMLocalizedFormat(@"notif.mute.until_date", dateStr);
        }
        case IMMuteUntilKindForever:
            return @""; // 调用方应先判 muteUntilMs==0，不应落到这里
    }
    return @"";
}

NSString *IMMuteDetailValueText(BOOL isMutedNow, int64_t muteUntilMs, int64_t nowMs) {
    if (!isMutedNow) { return IMLocalized(@"common.off"); }
    if (muteUntilMs == 0) { return IMLocalized(@"common.permanent"); }
    return IMMuteUntilSuffixText(muteUntilMs, nowMs, nil);
}

NSString *IMMuteExceptionSubtitle(int64_t muteUntilMs, int64_t nowMs, BOOL mentionUnread) {
    if (muteUntilMs == 0) {
        return IMLocalized(mentionUnread ? @"notif.exceptions.muted_mention" : @"notif.exceptions.muted");
    }
    NSString *suffix = IMMuteUntilSuffixText(muteUntilMs, nowMs, nil);
    return IMLocalizedFormat(mentionUnread ? @"notif.exceptions.muted_until_mention" : @"notif.exceptions.muted_until", suffix);
}
