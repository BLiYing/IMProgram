//  IMTimeUtil.m

#import "IMTimeUtil.h"

int64_t IMNowMillis(void) {
    return (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
}
