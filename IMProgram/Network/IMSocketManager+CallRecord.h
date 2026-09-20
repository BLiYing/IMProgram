//  IMSocketManager+CallRecord.h
//  通话记录消息（content_type=call）的发送：与 forwardContent: 的区别只有一个——**client_msg_id 由调用方给定**
//  （"call-"+call_id），服务端按 (conv_id, client_msg_id) 唯一索引去重：主叫两台设备都收到结束事件、断线重发都只落一条。

#import "IMSocketManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMSocketManager (CallRecord)
/// 发一条通话记录。群聊 toUser 传空。返回 clientMsgID（原样）。completion 在 ack / 最终失败时于主线程回调。
- (NSString *)sendCallRecordContent:(NSString *)content
                        clientMsgID:(NSString *)clientMsgID
                             toConv:(NSString *)convID
                             toUser:(NSString *)toUserID
                         completion:(nullable IMSendCompletion)completion;
@end

NS_ASSUME_NONNULL_END
