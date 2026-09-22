//  IMTimeUtil.m

#import "IMTimeUtil.h"

int64_t IMNowMillis(void) {
    return (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
}

NSString *IMFormatVoiceDuration(int64_t millis) {
    NSInteger s = MAX(0, (NSInteger)(millis / 1000));
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
}

NSString *IMFormatRFC3339LocalDateTime(NSString *rfc3339) {
    if (rfc3339.length == 0) { return @""; }
    // 每次现造 formatter（不用 dispatch_once 缓存单例）：NSISO8601DateFormatter/NSDateFormatter
    // 都不是文档保证的线程安全类型，这个函数可能同时被聊天页渲染（主线程）与消息落库解析
    // （DB 队列线程）调用——与本文件其余函数、IMMediaUtil.IMFormatFileDateTime 同一取舍。
    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    iso.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [iso dateFromString:rfc3339];
    if (!date) {
        iso.formatOptions = NSISO8601DateFormatWithInternetDateTime; // 无小数秒兜底重试
        date = [iso dateFromString:rfc3339];
    }
    if (!date) { return @""; }
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd HH:mm";
    return [f stringFromDate:date] ?: @"";
}
