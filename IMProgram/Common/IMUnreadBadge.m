#import "IMUnreadBadge.h"

NSString *IMCompactCount(NSInteger n) {
    if (n <= 0) { return @"0"; }
    if (n >= 1000000) {
        NSInteger rem = (n % 1000000) / 100000;
        return rem != 0 ? [NSString stringWithFormat:@"%ld.%ldM", (long)(n / 1000000), (long)rem]
                        : [NSString stringWithFormat:@"%ldM", (long)(n / 1000000)];
    }
    if (n >= 1000) {
        NSInteger rem = (n % 1000) / 100;
        return rem != 0 ? [NSString stringWithFormat:@"%ld.%ldK", (long)(n / 1000), (long)rem]
                        : [NSString stringWithFormat:@"%ldK", (long)(n / 1000)];
    }
    return [NSString stringWithFormat:@"%ld", (long)n];
}

NSString *IMUnreadBadgeText(NSInteger n, BOOL capped) {
    if (n <= 0) { return @""; }
    return capped ? [IMCompactCount(n) stringByAppendingString:@"+"] : IMCompactCount(n);
}
