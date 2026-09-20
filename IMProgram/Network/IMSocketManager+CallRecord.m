//  IMSocketManager+CallRecord.m

#import "IMSocketManager+CallRecord.h"
#import "IMSocketManager+Private.h"

@implementation IMSocketManager (CallRecord)

- (NSString *)sendCallRecordContent:(NSString *)content clientMsgID:(NSString *)clientMsgID
                             toConv:(NSString *)convID toUser:(NSString *)toUserID
                         completion:(IMSendCompletion)completion {
    NSDictionary *payload = @{
        @"client_msg_id": clientMsgID,
        @"conv_id":       convID ?: @"",
        @"to":            toUserID ?: @"",
        @"content_type":  @"call",
        @"content":       content ?: @"",
    };
    dispatch_async(_queue, ^{
        [self enqueueSendWithClientMsgID:clientMsgID payload:payload completion:completion];
    });
    return clientMsgID;
}

@end
