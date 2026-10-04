//  IMPushCall.m

#import "IMPushCall.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import <UserNotifications/UserNotifications.h>

NSString *const IMPushCallCategory = @"IM_CALL";
NSString *const IMPushCallActionAccept = @"IM_CALL_ACCEPT";
NSString *const IMPushCallActionReject = @"IM_CALL_REJECT";

/// 过了最长振铃时长，同一个 call_id 的来电不可能再来。
static const int64_t IMPushCallPendingTTLMS = 120000;

NSString *IMPushCallIDFromUserInfo(NSDictionary *userInfo) {
    id callID = userInfo[@"call_id"];
    if (![callID isKindOfClass:NSString.class] || [(NSString *)callID length] == 0) { return nil; }
    return callID;
}

void IMPushCallRegisterCategory(void) {
    // 两个按钮都 Foreground：拒绝也得拉起 App——App 在后台时没有通话连接，发不出拒绝。
    UNNotificationAction *reject = [UNNotificationAction actionWithIdentifier:IMPushCallActionReject
                                                                        title:IMLocalized(@"common.reject")
                                                                      options:UNNotificationActionOptionForeground];
    UNNotificationAction *accept = [UNNotificationAction actionWithIdentifier:IMPushCallActionAccept
                                                                        title:IMLocalized(@"push.call.action_answer")
                                                                      options:UNNotificationActionOptionForeground];
    UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:IMPushCallCategory
                                                                              actions:@[reject, accept]
                                                                    intentIdentifiers:@[]
                                                                              options:UNNotificationCategoryOptionNone];
    // set 会整组覆盖：先取已有的，换掉同名那个再写回，别把别处注册的类别冲掉。
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getNotificationCategoriesWithCompletionHandler:^(NSSet<UNNotificationCategory *> *existing) {
        NSMutableSet<UNNotificationCategory *> *merged = [NSMutableSet setWithObject:category];
        for (UNNotificationCategory *c in existing) {
            if (![c.identifier isEqualToString:IMPushCallCategory]) { [merged addObject:c]; }
        }
        [center setNotificationCategories:merged];
    }];
}

void IMPushCallRemoveDeliveredNotifications(NSString *callID) {
    if (callID.length == 0) { return; }
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        for (UNNotification *n in notifications) {
            if ([IMPushCallIDFromUserInfo(n.request.content.userInfo) isEqualToString:callID]) {
                [ids addObject:n.request.identifier];
            }
        }
        if (ids.count > 0) {
            [center removeDeliveredNotificationsWithIdentifiers:ids];
            IMLogPush(@"push_call_notification_removed call_id=%@ count=%lu", callID, (unsigned long)ids.count);
        }
    }];
}

@implementation IMPushCallPendingAction {
    NSString *_callID;
    BOOL _accept;
    int64_t _atMS;
}

+ (instancetype)shared {
    static IMPushCallPendingAction *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMPushCallPendingAction new]; });
    return s;
}

- (void)requestCallID:(NSString *)callID accept:(BOOL)accept nowMS:(int64_t)nowMS {
    if (callID.length == 0) { return; }
    @synchronized (self) {
        _callID = [callID copy];
        _accept = accept;
        _atMS = nowMS;
    }
}

- (NSNumber *)consumeCallID:(NSString *)callID nowMS:(int64_t)nowMS {
    @synchronized (self) {
        if (_callID == nil) { return nil; }
        if (nowMS - _atMS > IMPushCallPendingTTLMS) {
            _callID = nil;
            return nil;
        }
        if (![_callID isEqualToString:callID]) { return nil; }
        _callID = nil;
        return @(_accept);
    }
}

@end
