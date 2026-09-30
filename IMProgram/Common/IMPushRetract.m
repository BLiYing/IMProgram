//  IMPushRetract.m

#import "IMPushRetract.h"
#import <UserNotifications/UserNotifications.h>
#import "IMLog.h"

BOOL IMPushUserInfoMatchesMessage(NSDictionary *userInfo, NSString *convID, int64_t convSeq) {
    if (convID.length == 0 || convSeq <= 0) { return NO; }
    id conv = userInfo[@"conv_id"];
    id seq = userInfo[@"conv_seq"];
    if (![conv isKindOfClass:NSString.class] || ![seq isKindOfClass:NSNumber.class]) { return NO; }
    return [(NSString *)conv isEqualToString:convID] && [(NSNumber *)seq longLongValue] == convSeq;
}

void IMPushRetractDeliveredNotification(NSString *convID, int64_t convSeq) {
    if (convID.length == 0 || convSeq <= 0) { return; }
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        for (UNNotification *n in notifications) {
            if (IMPushUserInfoMatchesMessage(n.request.content.userInfo, convID, convSeq)) {
                [ids addObject:n.request.identifier];
            }
        }
        if (ids.count == 0) { return; }
        [center removeDeliveredNotificationsWithIdentifiers:ids];
        IMLogPush(@"push_notification_retracted conv_id=%@ conv_seq=%lld count=%lu",
                  convID, convSeq, (unsigned long)ids.count);
    }];
}
