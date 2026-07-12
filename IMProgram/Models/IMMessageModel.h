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
/// 发送方昵称（仅群聊消息带，服务端冗余下发；空回退 uid）。随消息落库（IMDatabase from_nickname 列）。
@property (nonatomic, copy, nullable) NSString *fromNickname;
@property (nonatomic, copy, nullable) NSString *to;          ///< 接收方 uid
@property (nonatomic, copy)   NSString *contentType; ///< text|image|audio...
@property (nonatomic, copy)   NSString *content;     ///< 文本内容
@property (nonatomic, assign) int64_t  convSeq;      ///< 会话内单调序号，ack/new_msg 后填充
@property (nonatomic, assign) int64_t  timestamp;    ///< 服务端时间（毫秒）
@property (nonatomic, assign) IMMessageStatus status;
/// 发送失败时的系统提示（如被拉黑拒收"消息已发出，但被对方拒收了"）。**随消息落库**（IMDatabase note 列），
/// 重进会话仍在；在该条气泡下方居中显示（微信式），不弹窗。
@property (nonatomic, copy, nullable) NSString *note;

/// M4 消息操作派生状态（撤回/编辑/置顶），随消息落库、随 new_msg/sync 冗余下发。
@property (nonatomic, assign) int64_t recalledAt;  ///< >0=已撤回（渲染居中系统行，隐藏原气泡）
@property (nonatomic, copy, nullable) NSString *recalledBy; ///< 撤回操作者 uid
@property (nonatomic, assign) int64_t editedAt;    ///< >0=已编辑（标"已编辑"，M4-5）
@property (nonatomic, assign) int64_t pinnedAt;    ///< >0=聊天内置顶（M4）
/// M4-2 引用回复：目标 conv_seq + 服务端冻结的降级快照（气泡顶部引用条）。
@property (nonatomic, assign) int64_t replyToConvSeq;
@property (nonatomic, copy, nullable) NSString *replySnapshot;
/// M4-3 转发溯源："转发自 X"显示名（发送时冻结）。
@property (nonatomic, copy, nullable) NSString *forwardFrom;
/// M4+ 相册分组：同批多图/视频共享的客户端生成 ID（空=普通消息）；聊天页据此聚簇渲染宫格。
@property (nonatomic, copy, nullable) NSString *groupID;
/// M4-5 翻译：译文（**内存临时态，不落库**；翻译后挂气泡下方）。
@property (nonatomic, copy, nullable) NSString *translation;

/// 由 new_msg 的 data 字典构造一条「收到」的消息。
+ (instancetype)receivedMessageWithNewMsgData:(NSDictionary *)data;

/// 本地落库归档用：模型 ↔ 字典（plist 安全：仅字符串/数字）。
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)messageFromDictionary:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
