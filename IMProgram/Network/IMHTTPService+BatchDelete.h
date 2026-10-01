//  IMHTTPService+BatchDelete.h
//  多选批量删除两档的 REST（PROTOCOL §6.7.1 / §6.7.2）：一次请求，服务端逐条回成败。
//  单独成 category：只被 IMSocketManager+BatchDelete 调用，与其它接口没有共享状态（CODING_STYLE §7 ②）。

#import "IMHTTPService.h"

NS_ASSUME_NONNULL_BEGIN

/// 批量删除的回调：results 为服务端 data.results（元素 `{conv_seq, ok, code?}`）；整单失败（断网/非成员/参数）时 error 非空。
typedef void (^IMBatchDeleteHTTPCompletion)(NSArray<NSDictionary *> *_Nullable results, NSError *_Nullable error);

@interface IMHTTPService (BatchDelete)

/// 「仅删除自己」批量：POST /api/v1/messages/hide {conv_id, conv_seqs}（≤100）。
/// 落 per-user 隐藏表；服务端另推一帧 msg_hidden（带 conv_seqs）同步本人其它设备。completion 在主线程。
- (void)hideMessagesWithToken:(NSString *)token
                       convID:(NSString *)convID
                     convSeqs:(NSArray<NSNumber *> *)convSeqs
                   completion:(IMBatchDeleteHTTPCompletion)completion;

/// 「为所有人删除」批量：POST /api/v1/messages/delete {conv_id, conv_seqs, client_msg_id}（≤100）。
/// 规则与单条 WS msg_op delete 同源；成功项服务端合成**一帧** msg_op{op:delete, targets} 广播（PROTOCOL §6.7.2）。completion 在主线程。
- (void)deleteMessagesForEveryoneWithToken:(NSString *)token
                                    convID:(NSString *)convID
                                  convSeqs:(NSArray<NSNumber *> *)convSeqs
                               clientMsgID:(NSString *)clientMsgID
                                completion:(IMBatchDeleteHTTPCompletion)completion;

@end

NS_ASSUME_NONNULL_END
