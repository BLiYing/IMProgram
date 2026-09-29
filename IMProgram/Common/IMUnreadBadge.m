#import "IMUnreadBadge.h"
#import "IMConversation.h"
#import "IMMuteState.h"
#import "IMTimeUtil.h"

NSInteger IMTabUnreadCount(NSArray<IMConversation *> *conversations, BOOL includeMuted) {
    NSInteger n = 0;
    int64_t now = IMNowMillis();
    for (IMConversation *c in conversations) {
        BOOL isMutedNow = IMIsMutedNow(c.muted, c.muteUntil, now); // 定时免打扰到期后照常计入未读数
        if (!isMutedNow || includeMuted) { n += c.unread; }
        else if (c.mentionUnread) { n += 1; }
    }
    return n;
}

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
