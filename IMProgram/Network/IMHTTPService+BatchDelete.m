//  IMHTTPService+BatchDelete.m

#import "IMHTTPService+BatchDelete.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"

@implementation IMHTTPService (BatchDelete)

- (void)hideMessagesWithToken:(NSString *)token
                       convID:(NSString *)convID
                     convSeqs:(NSArray<NSNumber *> *)convSeqs
                   completion:(IMBatchDeleteHTTPCompletion)completion {
    NSDictionary *body = @{ @"conv_id": convID ?: @"", @"conv_seqs": convSeqs ?: @[] };
    [self postBatchDelete:@"/api/v1/messages/hide" token:token body:body completion:completion];
}

- (void)deleteMessagesForEveryoneWithToken:(NSString *)token
                                    convID:(NSString *)convID
                                  convSeqs:(NSArray<NSNumber *> *)convSeqs
                               clientMsgID:(NSString *)clientMsgID
                                completion:(IMBatchDeleteHTTPCompletion)completion {
    NSDictionary *body = @{ @"conv_id": convID ?: @"", @"conv_seqs": convSeqs ?: @[], @"client_msg_id": clientMsgID ?: @"" };
    [self postBatchDelete:@"/api/v1/messages/delete" token:token body:body completion:completion];
}

- (void)postBatchDelete:(NSString *)path token:(NSString *)token body:(NSDictionary *)body
             completion:(IMBatchDeleteHTTPCompletion)completion {
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"POST" token:token body:body];
    [self runDataRequest:req fallback:IMLocalized(@"net.fallback.delete_failed") completion:^(NSDictionary *data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSArray *results = [data[@"results"] isKindOfClass:NSArray.class] ? data[@"results"] : @[];
        completion(results, nil);
    }];
}

@end
