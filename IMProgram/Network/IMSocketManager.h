//  IMSocketManager.h
//  IM 长连接核心：封装 WebSocket（底层用系统原生 NSURLSessionWebSocketTask），
//  负责 连接 / 心跳 / 指数退避重连 / 信封收发 / ACK 超时重发。
//  对齐 IMServer/docs/PROTOCOL.md。所有回调切回主线程。

#import <Foundation/Foundation.h>

@class IMSocketManager;
@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/// 收到任意会话的新消息时广播（主线程）。会话列表等非当前页可借此实时刷新（未读/最后一条），
/// 不占用单一 delegate 槽。userInfo[kIMConvIDKey] 为该消息的会话 id。
extern NSString * const IMSocketDidReceiveMessageNotification;
/// 收到好友关系变更帧（friend）时广播（主线程）：通讯录据此实时刷新"新的朋友"/好友列表，无需切页。
extern NSString * const IMSocketDidReceiveFriendEventNotification;
/// 收到群变更帧（group）时广播（主线程）：会话列表/群资料页据此刷新。
/// userInfo：kIMConvIDKey=群 conv_id、kIMGroupEventKey=事件、kIMGroupTargetKey=受影响方 uid（可空串）。
/// 收到 event=remove 且 target=自己 → 该群已把我移出（客户端应移出该会话）。
extern NSString * const IMSocketDidReceiveGroupEventNotification;
extern NSString * const kIMGroupEventKey;
extern NSString * const kIMGroupTargetKey;
/// 收到已读回执（read）时广播（主线程）：会话列表据此刷新——对端已读→我发的变✓✓；本人多端已读→未读清零。
extern NSString * const IMSocketDidReceiveReadNotification;
/// 消息操作（撤回/编辑/置顶，M4）应用到某条消息时广播（主线程）：聊天页/会话列表据此就地刷新。
/// userInfo：kIMConvIDKey=会话、kIMMsgOpTargetSeqKey=目标 conv_seq(NSNumber)、kIMMsgOpKey=op、kIMMsgOpContentKey=编辑新文本(可空)。
extern NSString * const IMSocketDidApplyMsgOpNotification;
extern NSString * const kIMMsgOpTargetSeqKey;
extern NSString * const kIMMsgOpKey;
extern NSString * const kIMMsgOpContentKey;
/// 我发起的消息操作被拒（如撤回超时）时广播（主线程）：userInfo[@"message"]=服务端文案。
extern NSString * const IMSocketDidRejectMsgOpNotification;
/// 连接状态变化时广播（主线程）：非 delegate 页（如会话列表）据此显示 连接中/未连接。userInfo[@"state"]=IMSocketState。
extern NSString * const IMSocketDidChangeStateNotification;
extern NSString * const kIMConvIDKey;

/// 连接状态。
typedef NS_ENUM(NSInteger, IMSocketState) {
    IMSocketStateDisconnected = 0, ///< 未连接 / 已断开
    IMSocketStateConnecting,       ///< 连接中（含重连等待）
    IMSocketStateConnected,        ///< 已连接
};

/// 发送结果回调：success=YES 表示收到 ack；否则 error 给出原因。
typedef void (^IMSendCompletion)(BOOL success, NSError * _Nullable error, int64_t convSeq);

@protocol IMSocketManagerDelegate <NSObject>
@optional
/// 连接状态变化（主线程）。
- (void)socketManager:(IMSocketManager *)manager didChangeState:(IMSocketState)state;
/// 收到对方的新消息 new_msg（主线程）。
- (void)socketManager:(IMSocketManager *)manager didReceiveMessage:(IMMessageModel *)message;
/// 收到对端已读回执：from 已读到 upToConvSeq（用于「已读」双勾）（主线程）。
- (void)socketManager:(IMSocketManager *)manager didReadConv:(NSString *)convID by:(NSString *)from upToConvSeq:(int64_t)convSeq;
/// 对端「正在输入」（主线程）。
- (void)socketManager:(IMSocketManager *)manager didTypingInConv:(NSString *)convID by:(NSString *)from;
/// 某用户在线状态变化（主线程）。
- (void)socketManager:(IMSocketManager *)manager didChangePresenceForUser:(NSString *)user online:(BOOL)online;
@end

@interface IMSocketManager : NSObject

@property (nonatomic, weak, nullable) id<IMSocketManagerDelegate> delegate;
@property (nonatomic, assign, readonly) IMSocketState state;
@property (nonatomic, copy, readonly, nullable) NSString *userID;

+ (instancetype)sharedManager;

/// 连接到指定主机（如 @"localhost:8080" 或 @"im.example.com"）。
/// 当前以 ?uid= 接入（骨架），后续替换为 JWT token。
- (void)connectToHost:(NSString *)host userID:(NSString *)userID;

/// 主动断开，停止自动重连。
- (void)disconnect;

/// 发送一条文本消息（单聊：conv_id 由双方 uid 规范排序生成）。返回本条的 client_msg_id（也用于幂等去重）。
/// completion 在收到 ack 或最终失败时于主线程回调。
- (NSString *)sendText:(NSString *)text
               toUser:(NSString *)toUserID
           completion:(nullable IMSendCompletion)completion;

/// 发送一条文本消息到指定会话（群聊：conv_id=群 topic_id，to 留空，服务端按 conv_id 查成员写扩散）。
/// 返回本条的 client_msg_id。completion 在收到 ack 或最终失败时于主线程回调。
- (NSString *)sendText:(NSString *)text
                toConv:(NSString *)convID
            completion:(nullable IMSendCompletion)completion;

/// 引用回复变体（M4-2）：replyToConvSeq>0 时带引用（只发目标 conv_seq，快照由服务端冻结下发）。
- (NSString *)sendText:(NSString *)text
                toUser:(NSString *)toUserID
        replyToConvSeq:(int64_t)replyToConvSeq
            completion:(nullable IMSendCompletion)completion;
- (NSString *)sendText:(NSString *)text
                toConv:(NSString *)convID
        replyToConvSeq:(int64_t)replyToConvSeq
            completion:(nullable IMSendCompletion)completion;

/// 转发变体（M4-3）：把 text 发到 convID（群=to 空/单聊=toUserID），带 forward_from 溯源。
- (NSString *)forwardText:(NSString *)text
                  toConv:(NSString *)convID
                  toUser:(NSString *)toUserID
             forwardFrom:(NSString *)forwardFrom
              completion:(nullable IMSendCompletion)completion;

/// 上报「已读到 convSeq」：对端据此显示已读双勾，本人未读随之清零（仅 read 推进已读位点）。
- (void)markReadConv:(NSString *)convID upToConvSeq:(int64_t)convSeq;

/// 发送「正在输入」给会话对端（临时态，对端短暂显示后自动消失）。
- (void)sendTypingForConv:(NSString *)convID;

/// 撤回自己在 convID 会话里 conv_seq=targetConvSeq 的消息（M4-1）。发出 msg_op；
/// 成功由服务端广播回 msg_op 帧应用（IMSocketDidApplyMsgOp 通知），失败（超窗等）发 IMSocketDidRejectMsgOp。
- (void)recallMessageInConv:(NSString *)convID targetConvSeq:(int64_t)targetConvSeq;

/// 编辑自己在 convID 会话里 conv_seq=targetConvSeq 的文本消息（M4-5）。成功由服务端广播回 msg_op 帧应用。
- (void)editMessageInConv:(NSString *)convID targetConvSeq:(int64_t)targetConvSeq content:(NSString *)content;

/// 登记一个会话用于增量同步：每次（重）连成功后，自动从该会话已同步位点发 sync_req
/// 拉取离线/缺失的消息。
- (void)trackConversation:(NSString *)convID;

/// 同上，但用调用方提供的位点作为同步起点（取与内存值的较大者）。
/// 上层从 IMDatabase 取已存最大 conv_seq 传入，实现 App 重启后的断点续传。
- (void)trackConversation:(NSString *)convID syncedSeq:(int64_t)syncedSeq;

@end

NS_ASSUME_NONNULL_END
