//  IMSocketManager+BatchDelete.m

#import "IMSocketManager+BatchDelete.h"
#import "IMSocketManager+Private.h"
#import "IMDatabase.h"
#import "IMHTTPService+BatchDelete.h"
#import "IMLog.h"
#import "IMPushRetract.h"
#import "IMProtocol.h"

NSArray<NSNumber *> *IMBatchOKSeqs(NSArray<NSNumber *> *seqs, id results) {
    NSMutableSet<NSNumber *> *ok = [NSMutableSet set];
    if ([results isKindOfClass:NSArray.class]) {
        for (id r in (NSArray *)results) {
            if (![r isKindOfClass:NSDictionary.class]) { continue; }
            id seq = r[@"conv_seq"], flag = r[@"ok"];
            if ([seq isKindOfClass:NSNumber.class] && [flag isKindOfClass:NSNumber.class] && [flag boolValue]) {
                [ok addObject:@([seq longLongValue])];
            }
        }
    }
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:seqs.count];
    for (NSNumber *s in seqs) {
        if ([ok containsObject:@(s.longLongValue)]) { [out addObject:s]; }
    }
    return out;
}

NSArray<NSNumber *> *IMMsgHiddenSeqs(NSDictionary *payload) {
    NSMutableArray<NSNumber *> *out = [NSMutableArray array];
    id many = payload[@"conv_seqs"];
    if ([many isKindOfClass:NSArray.class]) {
        for (id s in (NSArray *)many) {
            if ([s isKindOfClass:NSNumber.class] && [s longLongValue] > 0) { [out addObject:@([s longLongValue])]; }
        }
        return out;
    }
    int64_t one = [payload[@"conv_seq"] longLongValue];
    if (one > 0) { [out addObject:@(one)]; }
    return out;
}

NSString * const kIMMsgOpTargetSeqsKey = @"msgOpTargetSeqs";

NSArray<NSNumber *> *IMRemovedMessageSeqs(NSDictionary *userInfo) {
    id many = userInfo[kIMMsgOpTargetSeqsKey];
    if ([many isKindOfClass:NSArray.class]) { return many; }
    int64_t one = [userInfo[kIMMsgOpTargetSeqKey] longLongValue];
    return one > 0 ? @[ @(one) ] : @[];
}

NSArray<NSNumber *> *IMMsgOpBatchDeleteSeqs(NSDictionary *payload) {
    id targets = payload[@"targets"];
    if (![payload[@"op"] isEqual:kIMMsgOpDelete] || ![targets isKindOfClass:NSArray.class]) { return nil; }
    NSMutableArray<NSNumber *> *out = [NSMutableArray array];
    for (id t in (NSArray *)targets) {
        if (![t isKindOfClass:NSDictionary.class]) { continue; }
        int64_t seq = [t[@"target_conv_seq"] longLongValue];
        if (seq > 0) { [out addObject:@(seq)]; }
    }
    return out;
}

@implementation IMSocketManager (BatchDelete)

- (void)removeLocalMessagesOnQueueInConv:(NSString *)convID seqs:(NSArray<NSNumber *> *)seqs {
    if (convID.length == 0 || seqs.count == 0) { return; }
    NSMutableArray<NSNumber *> *removed = [NSMutableArray arrayWithCapacity:seqs.count];
    [self performDatabaseOperation:^(IMDatabase *database) {
        for (NSNumber *s in seqs) {
            if ([database deleteLocalMessageForConv:convID convSeq:s.longLongValue advancingSyncedConvSeq:0]) { [removed addObject:s]; }
        }
    }];
    // 同单条：只有真删掉了行才通知（catch-up 重删早已不存在的行不能触发列表 reload，见 removeLocalMessageOnQueueInConv:）。
    if (removed.count == 0) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:IMSocketDidRemoveMessageNotification object:self
            userInfo:@{ kIMConvIDKey: convID, kIMMsgOpTargetSeqKey: removed.firstObject, kIMMsgOpTargetSeqsKey: [removed copy] }];
    });
}

- (BOOL)applyBatchDeleteFrameOnQueue:(NSDictionary *)payload {
    NSArray<NSNumber *> *seqs = IMMsgOpBatchDeleteSeqs(payload);
    if (!seqs) { return NO; }
    NSString *convID = [payload[@"conv_id"] isKindOfClass:NSString.class] ? payload[@"conv_id"] : @"";
    if (convID.length == 0) { return YES; }
    // 与单条 applyMsgOpPayload: 同：被删的若还挂在通知中心里，一并收回。
    for (NSNumber *s in seqs) { IMPushRetractDeliveredNotification(convID, s.longLongValue); }
    [self removeLocalMessagesOnQueueInConv:convID seqs:seqs];
    return YES;
}

- (void)hideMessagesInConv:(NSString *)convID
                  convSeqs:(NSArray<NSNumber *> *)convSeqs
                completion:(IMBatchDeleteCompletion)completion {
    if (convID.length == 0 || convSeqs.count == 0) { if (completion) { completion(0); } return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService hideMessagesWithToken:IMHTTPService.sharedService.currentToken ?: @""
                                                convID:convID convSeqs:convSeqs
                                            completion:^(NSArray<NSDictionary *> *results, NSError *error) {
        [ws finishBatchDelete:@"hide" convID:convID convSeqs:convSeqs results:results error:error completion:completion];
    }];
}

- (void)deleteMessagesForEveryoneInConv:(NSString *)convID
                               convSeqs:(NSArray<NSNumber *> *)convSeqs
                             completion:(IMBatchDeleteCompletion)completion {
    if (convID.length == 0 || convSeqs.count == 0) { if (completion) { completion(0); } return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService deleteMessagesForEveryoneWithToken:IMHTTPService.sharedService.currentToken ?: @""
                                                             convID:convID convSeqs:convSeqs
                                                        clientMsgID:NSUUID.UUID.UUIDString
                                                         completion:^(NSArray<NSDictionary *> *results, NSError *error) {
        [ws finishBatchDelete:@"delete" convID:convID convSeqs:convSeqs results:results error:error completion:completion];
    }];
}

/// 两档共用的收尾：成功项切到 socket 队列整批移除（removeLocalMessagesOnQueueInConv:seqs:，只发一次移除通知），回失败条数。
- (void)finishBatchDelete:(NSString *)kind convID:(NSString *)convID convSeqs:(NSArray<NSNumber *> *)convSeqs
                  results:(NSArray<NSDictionary *> *)results error:(NSError *)error
               completion:(IMBatchDeleteCompletion)completion {
    NSArray<NSNumber *> *okSeqs = error ? @[] : IMBatchOKSeqs(convSeqs, results);
    if ([kind isEqualToString:@"delete"]) {
        // 与广播帧同：为所有人删除的那条若还挂在通知中心，一并收回（WS 断着时广播帧要等 sync 才到）。
        for (NSNumber *s in okSeqs) { IMPushRetractDeliveredNotification(convID, s.longLongValue); }
    }
    if (okSeqs.count > 0) {
        dispatch_async(self->_queue, ^{ [self removeLocalMessagesOnQueueInConv:convID seqs:okSeqs]; });
    }
    NSUInteger failed = convSeqs.count - okSeqs.count;
    if (error || failed > 0) {
        IMLogWarnWithTag(IMLogTagSocket, @"batch_delete_partial kind=%@ conv_id=%@ count=%lu failed=%lu error=%@",
                    kind, convID, (unsigned long)convSeqs.count, (unsigned long)failed, error.localizedDescription ?: @"");
    }
    if (completion) { completion(failed); }
}

@end
