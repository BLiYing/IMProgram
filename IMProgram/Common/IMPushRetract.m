//  IMPushRetract.m

#import "IMPushRetract.h"
#import <UserNotifications/UserNotifications.h>
#import "IMLog.h"

/// userInfo 里的 conv_id / conv_seq；类型不对或缺失返回 NO。
static BOOL IMPushUserInfoTarget(NSDictionary *userInfo, NSString **convID, int64_t *convSeq) {
    id conv = userInfo[@"conv_id"];
    id seq = userInfo[@"conv_seq"];
    if (![conv isKindOfClass:NSString.class] || ![seq isKindOfClass:NSNumber.class]) { return NO; }
    *convID = conv;
    *convSeq = [(NSNumber *)seq longLongValue];
    return YES;
}

BOOL IMPushUserInfoMatchesMessage(NSDictionary *userInfo, NSString *convID, int64_t convSeq) {
    if (convID.length == 0 || convSeq <= 0) { return NO; }
    NSString *conv = nil;
    int64_t seq = 0;
    if (!IMPushUserInfoTarget(userInfo, &conv, &seq)) { return NO; }
    return [conv isEqualToString:convID] && seq == convSeq;
}

BOOL IMPushUserInfoReadThrough(NSDictionary *userInfo, NSString *convID, int64_t upTo) {
    if (convID.length == 0 || upTo <= 0) { return NO; }
    NSString *conv = nil;
    int64_t seq = 0;
    if (!IMPushUserInfoTarget(userInfo, &conv, &seq)) { return NO; }
    return [conv isEqualToString:convID] && seq > 0 && seq <= upTo;
}

BOOL IMPushUserInfoMatchesAnyMessage(NSDictionary *userInfo, NSString *convID, NSSet<NSNumber *> *convSeqs) {
    if (convID.length == 0 || convSeqs.count == 0) { return NO; }
    NSString *conv = nil;
    int64_t seq = 0;
    if (!IMPushUserInfoTarget(userInfo, &conv, &seq)) { return NO; }
    return [conv isEqualToString:convID] && [convSeqs containsObject:@(seq)];
}

BOOL IMPushReadClearFromPayload(NSDictionary *userInfo, NSString **convID, int64_t *upTo) {
    id conv = userInfo[@"conv_id"];
    id seq = userInfo[@"clear_up_to"];
    if (![conv isKindOfClass:NSString.class] || [(NSString *)conv length] == 0
        || ![seq isKindOfClass:NSNumber.class] || [(NSNumber *)seq longLongValue] <= 0) {
        return NO;
    }
    *convID = conv;
    *upTo = [(NSNumber *)seq longLongValue];
    return YES;
}

/// 删掉通知中心里 match 为真的通知；event 用于日志区分两种来源。
static void IMPushRemoveDelivered(BOOL (^match)(NSDictionary *userInfo), NSString *event,
                                  NSString *convID, int64_t seq, void (^completion)(void)) {
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        for (UNNotification *n in notifications) {
            if (match(n.request.content.userInfo)) { [ids addObject:n.request.identifier]; }
        }
        if (ids.count > 0) {
            [center removeDeliveredNotificationsWithIdentifiers:ids];
            IMLogPush(@"%@ conv_id=%@ conv_seq=%lld count=%lu", event, convID, seq, (unsigned long)ids.count);
        }
        if (completion) { completion(); }
    }];
}

void IMPushRetractDeliveredNotification(NSString *convID, int64_t convSeq) {
    if (convID.length == 0 || convSeq <= 0) { return; }
    IMPushRemoveDelivered(^BOOL(NSDictionary *userInfo) {
        return IMPushUserInfoMatchesMessage(userInfo, convID, convSeq);
    }, @"push_notification_retracted", convID, convSeq, nil);
}

void IMPushRetractDeliveredNotifications(NSString *convID, NSArray<NSNumber *> *convSeqs) {
    if (convID.length == 0 || convSeqs.count == 0) { return; }
    NSSet<NSNumber *> *seqSet = [NSSet setWithArray:convSeqs];
    IMPushRemoveDelivered(^BOOL(NSDictionary *userInfo) {
        return IMPushUserInfoMatchesAnyMessage(userInfo, convID, seqSet);
    }, @"push_notifications_retracted_batch", convID, (int64_t)convSeqs.count, nil);
}

void IMPushClearDeliveredNotificationsReadThrough(NSString *convID, int64_t upTo, void (^completion)(void)) {
    if (convID.length == 0 || upTo <= 0) {
        if (completion) { completion(); }
        return;
    }
    IMPushRemoveDelivered(^BOOL(NSDictionary *userInfo) {
        return IMPushUserInfoReadThrough(userInfo, convID, upTo);
    }, @"push_notifications_read_cleared", convID, upTo, completion);
}
