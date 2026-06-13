//  IMSocketManager.h
//  IM 长连接核心：封装 WebSocket（底层用系统原生 NSURLSessionWebSocketTask），
//  负责 连接 / 心跳 / 指数退避重连 / 信封收发 / ACK 超时重发。
//  对齐 IMServer/docs/PROTOCOL.md。所有回调切回主线程。

#import <Foundation/Foundation.h>

@class IMSocketManager;
@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

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

/// 登记一个会话用于增量同步：每次（重）连成功后，自动从该会话已同步位点发 sync_req
/// 拉取离线/缺失的消息。骨架阶段位点记在内存（重启即从 0 起），后续接 IMDatabase 持久化。
- (void)trackConversation:(NSString *)convID;

@end

NS_ASSUME_NONNULL_END
