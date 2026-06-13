//  IMMessageModel.h
//  单条消息模型。对应协议 new_msg / ack 字段，附带本地发送状态。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 本地消息状态机。
typedef NS_ENUM(NSInteger, IMMessageStatus) {
    IMMessageStatusSending = 0,  ///< 已发出，等待 ack
    IMMessageStatusSent,         ///< 收到 ack，服务端已确认
    IMMessageStatusFailed,       ///< ack 超时且重发耗尽
    IMMessageStatusReceived,     ///< 对方发来的消息（new_msg）
};

@interface IMMessageModel : NSObject

@property (nonatomic, copy)   NSString *clientMsgID;   ///< 客户端 UUID，幂等去重锚点
@property (nonatomic, copy, nullable) NSString *serverMsgID; ///< 服务端分配，ack 后填充
@property (nonatomic, copy)   NSString *convID;       ///< 会话 id
@property (nonatomic, copy, nullable) NSString *from;        ///< 发送方 uid
@property (nonatomic, copy, nullable) NSString *to;          ///< 接收方 uid
@property (nonatomic, copy)   NSString *contentType; ///< text|image|audio...
@property (nonatomic, copy)   NSString *content;     ///< 文本内容
@property (nonatomic, assign) int64_t  convSeq;      ///< 会话内单调序号，ack/new_msg 后填充
@property (nonatomic, assign) int64_t  timestamp;    ///< 服务端时间（毫秒）
@property (nonatomic, assign) IMMessageStatus status;

/// 由 new_msg 的 data 字典构造一条「收到」的消息。
+ (instancetype)receivedMessageWithNewMsgData:(NSDictionary *)data;

@end

NS_ASSUME_NONNULL_END
