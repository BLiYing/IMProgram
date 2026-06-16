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

/// 发送一条文本消息。返回本条的 client_msg_id（也用于幂等去重）。
/// completion 在收到 ack 或最终失败时于主线程回调。
- (NSString *)sendText:(NSString *)text
               toUser:(NSString *)toUserID
           completion:(nullable IMSendCompletion)completion;

/// 上报「已读到 convSeq」：对端据此显示已读双勾，本人未读随之清零（仅 read 推进已读位点）。
- (void)markReadConv:(NSString *)convID upToConvSeq:(int64_t)convSeq;

/// 发送「正在输入」给会话对端（临时态，对端短暂显示后自动消失）。
- (void)sendTypingForConv:(NSString *)convID;

/// 登记一个会话用于增量同步：每次（重）连成功后，自动从该会话已同步位点发 sync_req
/// 拉取离线/缺失的消息。
- (void)trackConversation:(NSString *)convID;

/// 同上，但用调用方提供的位点作为同步起点（取与内存值的较大者）。
/// 上层从 IMDatabase 取已存最大 conv_seq 传入，实现 App 重启后的断点续传。
- (void)trackConversation:(NSString *)convID syncedSeq:(int64_t)syncedSeq;

@end

NS_ASSUME_NONNULL_END
