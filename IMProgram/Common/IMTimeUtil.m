//  IMTimeUtil.m

#import "IMTimeUtil.h"

int64_t IMNowMillis(void) {
    return (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
}

NSString *IMFormatVoiceDuration(int64_t millis) {
    NSInteger s = MAX(0, (NSInteger)(millis / 1000));
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
}
