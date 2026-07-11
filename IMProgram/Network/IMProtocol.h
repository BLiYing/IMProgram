//  IMProtocol.h
//  客户端与服务端共用契约的常量与工具，对齐 IMServer/docs/PROTOCOL.md。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 信封类型常量

extern NSString * const kIMTypePing;
extern NSString * const kIMTypePong;
extern NSString * const kIMTypeAuth;
extern NSString * const kIMTypeSendMsg;
extern NSString * const kIMTypeAck;
extern NSString * const kIMTypeNewMsg;
extern NSString * const kIMTypeReceipt;
extern NSString * const kIMTypeTyping;
extern NSString * const kIMTypePresence;
extern NSString * const kIMTypeSyncReq;
extern NSString * const kIMTypeSyncResp;
extern NSString * const kIMTypeFriend;
extern NSString * const kIMTypeGroup;
extern NSString * const kIMTypeMsgOp;
extern NSString * const kIMTypeError;

#pragma mark - 消息操作 op（msg_op，M4）

extern NSString * const kIMMsgOpRecall; ///< 撤回
extern NSString * const kIMMsgOpEdit;   ///< 编辑
extern NSString * const kIMMsgOpPin;    ///< 聊天内置顶

/// 撤回可见时间窗（毫秒，微信式 2min，与后端 Hub.recallWindow 对齐；服务端为准）。
FOUNDATION_EXPORT const int64_t kIMRecallWindowMs;

#pragma mark - 信封字段 Key

extern NSString * const kIMKeyType;
extern NSString * const kIMKeySeq;
extern NSString * const kIMKeyData;

#pragma mark - 工具

/// 计算会话 id：两个 uid 规范排序，保证收发双方一致（对齐协议示例 u_{a}_u_{b}）。
FOUNDATION_EXPORT NSString *IMConversationID(NSString *uidA, NSString *uidB);

NS_ASSUME_NONNULL_END
