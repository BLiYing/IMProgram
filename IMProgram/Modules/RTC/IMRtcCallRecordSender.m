//  IMRtcCallRecordSender.m

#import "IMRtcCallRecordSender.h"
#import "IMCallRecord.h"
#import "IMDatabase.h"
#import "IMLog.h"
#import "IMMessageModel.h"
#import "IMProtocol.h"
#import "IMSocketManager+CallRecord.h"

/// 同一通电话的事件重复到达时，在途的那条只发一次（本地行 / 网络帧都不重复；落库幂等另有 client_msg_id 兜底）。
static NSMutableSet<NSString *> *inFlight(void) {
    static NSMutableSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet set]; });
    return s;
}

static NSString *stringValue(id v) { return [v isKindOfClass:NSString.class] ? v : @""; }

@implementation IMRtcCallRecordSender

+ (NSDictionary *)planForSummaryPayload:(NSDictionary *)p selfUID:(NSString *)selfUID {
    if (![stringValue(p[@"role"]) isEqualToString:@"caller"]) { return nil; }       // 只主叫发
    NSString *cid = stringValue(p[@"call_id"]);
    if (cid.length == 0 || selfUID.length == 0) { return nil; }
    BOOL isGroup = [p[@"is_group"] respondsToSelector:@selector(boolValue)] && [p[@"is_group"] boolValue];
    NSString *convID, *toUser;
    if (isGroup) {
        convID = stringValue(p[@"chat_group_id"]);
        toUser = @"";
    } else {
        toUser = stringValue(p[@"peer"]);
        convID = toUser.length > 0 ? IMConversationID(selfUID, toUser) : @"";
    }
    if (convID.length == 0) { return nil; }
    BOOL video = [stringValue(p[@"media_type"]) isEqualToString:@"video"];
    NSInteger sec = [p[@"duration_sec"] respondsToSelector:@selector(integerValue)] ? [p[@"duration_sec"] integerValue] : 0;
    NSString *content = IMCallRecordBuild(cid, video, stringValue(p[@"reason"]), sec, isGroup);
    if (content.length == 0) { return nil; }
    return @{ @"clientMsgID": [@"call-" stringByAppendingString:cid], @"convID": convID, @"toUser": toUser,
              @"content": content, @"isGroup": @(isGroup) };
}

+ (void)handleSummaryPayload:(NSDictionary *)payload selfUID:(NSString *)selfUID {
    NSDictionary *plan = [self planForSummaryPayload:payload selfUID:selfUID];
    if (!plan) { return; }
    NSString *cmid = plan[@"clientMsgID"];
    if ([inFlight() containsObject:cmid]) { return; }
    IMDatabaseAccountContext *ctx = IMDatabase.sharedDatabase.currentAccountContext;
    if (!ctx) { IMLogWarnWithTag(IMLogTagRTC, @"call_record_skip reason=no_account cmid=%@", cmid); return; }
    [inFlight() addObject:cmid];

    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = cmid; m.convID = plan[@"convID"]; m.to = plan[@"toUser"]; m.from = selfUID;
    m.content = plan[@"content"]; m.contentType = IMContentTypeCall;
    m.status = IMMessageStatusSending;
    m.timestamp = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    [IMDatabase.sharedDatabase performWithAccountContext:ctx block:^(IMDatabase *db) { [db saveMessage:m]; }];

    IMLogWithTag(IMLogTagRTC, @"call_record_send cmid=%@ conv=%@ content=%@", cmid, m.convID, m.content);
    [IMSocketManager.sharedManager sendCallRecordContent:m.content clientMsgID:cmid toConv:m.convID toUser:m.to
                                              completion:^(BOOL success, NSError *error, int64_t convSeq) {
        [inFlight() removeObject:cmid];
        if (success) {
            m.status = IMMessageStatusSent; m.convSeq = convSeq;
            [IMDatabase.sharedDatabase performWithAccountContext:ctx block:^(IMDatabase *db) { [db saveMessage:m]; }];
            [self announceSent:m];
            return;
        }
        // 只写日志、不弹任何提示（失败不影响通话；被拉黑 200102 尤其不能暴露）。
        IMLogWarnWithTag(IMLogTagRTC, @"call_record_failed cmid=%@ code=%ld %@", cmid, (long)error.code, error.localizedDescription);
        if (error.code == 200102) {
            [IMDatabase.sharedDatabase performWithAccountContext:ctx block:^(IMDatabase *db) { [db deleteMessage:m]; }];
        } else {
            m.status = IMMessageStatusFailed;
            [IMDatabase.sharedDatabase performWithAccountContext:ctx block:^(IMDatabase *db) { [db saveMessage:m]; }];
        }
    }];
}

/// 服务端不回显自己发的消息：刚发出的记录要让「正开着的这个会话」与会话列表都看到——走与收消息同一条出口。
+ (void)announceSent:(IMMessageModel *)m {
    IMSocketManager *sm = IMSocketManager.sharedManager;
    id<IMSocketManagerDelegate> d = sm.delegate;
    if ([d respondsToSelector:@selector(socketManager:didReceiveMessage:)]) { [d socketManager:sm didReceiveMessage:m]; }
    [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidReceiveMessageNotification object:sm
                                                    userInfo:@{ kIMConvIDKey: m.convID ?: @"" }];
}

@end
