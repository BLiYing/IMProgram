//  IMSocketManager+BatchDelete.h
//  多选批量删除两档的编排（PROTOCOL §6.7.1 / §6.7.2）：一次 REST 请求 → 服务端逐条回成败 →
//  成功的本地物理移除（逐条发 IMSocketDidRemoveMessageNotification，与单条删除同一条通知）→ 回失败条数。
//  与 im-web `imSdk.hideMessages` / `deleteMessagesForEveryone`、im-android 对应实现同口径。

#import "IMSocketManager.h"

NS_ASSUME_NONNULL_BEGIN

/// 把服务端 results 对回请求的 seqs，返回**成功的**那些（保持请求顺序）。results 缺项 / 缺字段 / 形状不对一律算失败——
/// 宁可多报一条失败，也不把没删掉的当删掉了。失败条数 = seqs.count - 返回值.count。与 im-web `summarizeBatch` 同口径。
FOUNDATION_EXPORT NSArray<NSNumber *> *IMBatchOKSeqs(NSArray<NSNumber *> *seqs, id _Nullable results);

/// msg_hidden 帧里要移除的 seq：批量帧优先读 conv_seqs，单条帧（老服务端 / 单条隐藏）退回 conv_seq。与 im-web `hiddenSeqsOf` 同口径。
FOUNDATION_EXPORT NSArray<NSNumber *> *IMMsgHiddenSeqs(NSDictionary *payload);

/// 批量移除时 IMSocketDidRemoveMessageNotification 的 userInfo 额外带这个键：本次移除的全部 conv_seq（NSArray<NSNumber *>）。
/// 批量只发**一次**通知（kIMMsgOpTargetSeqKey 仍给首条），观察者一次删完、只刷新一次。
FOUNDATION_EXPORT NSString * const kIMMsgOpTargetSeqsKey;

/// 从移除通知的 userInfo 取本次移除的全部 seq：优先 kIMMsgOpTargetSeqsKey（批量），缺省退回 kIMMsgOpTargetSeqKey（单条）。
FOUNDATION_EXPORT NSArray<NSNumber *> *IMRemovedMessageSeqs(NSDictionary *_Nullable userInfo);

/// 批量「为所有人删除」的实时广播帧（PROTOCOL §6.7.2）：一次批量只来一帧 msg_op{op:delete, targets:[…]}，
/// 返回要删的 target_conv_seq（按帧内顺序）。不是批量帧（没有 targets / 不是 delete）返回 nil，按单条 msg_op 处理。
/// 与 im-web `batchDeleteTargetsOf` 同口径。
FOUNDATION_EXPORT NSArray<NSNumber *> *_Nullable IMMsgOpBatchDeleteSeqs(NSDictionary *payload);

/// 回调在主线程：failed=没删成的条数（整单失败时=全部）。
typedef void (^IMBatchDeleteCompletion)(NSUInteger failed);

@interface IMSocketManager (BatchDelete)

/// 多选「仅删除自己」：批量 hide，成功的本端立即移除（服务端另推 msg_hidden 同步本人其它设备，本端再收到是幂等的）。
- (void)hideMessagesInConv:(NSString *)convID
                  convSeqs:(NSArray<NSNumber *> *)convSeqs
                completion:(nullable IMBatchDeleteCompletion)completion;

/// 多选「为所有人删除」：批量 delete，成功的本端立即移除——走 REST，WS 断着也删得掉，不必等广播帧
/// （服务端另给全体成员广播**一帧** msg_op{op:delete, targets}，本端再收到是幂等的）。
- (void)deleteMessagesForEveryoneInConv:(NSString *)convID
                               convSeqs:(NSArray<NSNumber *> *)convSeqs
                             completion:(nullable IMBatchDeleteCompletion)completion;

/// 批量物理移除（**仅在 socket 队列调用**）：逐条删本地行，真删掉的合成**一次**移除通知（主线程）。
/// 批量删除 REST 成功项、批量删除广播帧、msg_hidden 批量帧共用。
- (void)removeLocalMessagesOnQueueInConv:(NSString *)convID seqs:(NSArray<NSNumber *> *)seqs;

/// 收帧分发处调用（仅在 socket 队列）：是批量删除广播帧就整批处理并返回 YES，否则返回 NO 交给单条 applyMsgOpPayload:。
- (BOOL)applyBatchDeleteFrameOnQueue:(NSDictionary *)payload;

@end

NS_ASSUME_NONNULL_END
