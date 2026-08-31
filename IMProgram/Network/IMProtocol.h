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
extern NSString * const kIMTypeWatch; ///< 上报「当前要显示在线态的用户全集」（在线态订阅，见 PROTOCOL §5.5）
extern NSString * const kIMTypeSyncReq;
extern NSString * const kIMTypeSyncResp;
extern NSString * const kIMTypeFriend;
extern NSString * const kIMTypeGroup;
extern NSString * const kIMTypeMsgOp;
extern NSString * const kIMTypeConvUpdate; ///< 会话级设置变更（置顶/免打扰/标未读/删除会话，M4.5）
extern NSString * const kIMTypeCapabilitiesUpdate; ///< 账号级配置版本变更（自动下载策略，M4-7）：据 version 重拉 /download-settings
/// 超级群（2 万人量级）的轻量投递信号：一帧带一批「某会话最新到 conv_seq 了」，**不含正文**。
/// 超级群不推全文 new_msg——2 万人数千在线推全文约 50MB/s，算术上不成立。
/// 正文在打开会话时经 sync_req 拉。见 IMServer/docs/design/SUPERGROUP_DESIGN.md §5。
extern NSString * const kIMTypeConvBump;
extern NSString * const kIMTypeMsgHidden; ///< 「仅为我删除」多设备同步（任务2）：本人另一端删了某条 → 本端物理移除
extern NSString * const kIMTypeVoiceTranscript; ///< 语音转文字结果（服务端识别；只推给请求者，见 IMServer docs/design/VOICE_TRANSCRIBE_DESIGN.md §3.2）
extern NSString * const kIMTypeError;

#pragma mark - 消息操作 op（msg_op，M4）

extern NSString * const kIMMsgOpRecall; ///< 撤回
extern NSString * const kIMMsgOpEdit;   ///< 编辑
extern NSString * const kIMMsgOpPin;    ///< 聊天内置顶
extern NSString * const kIMMsgOpDelete; ///< 为所有人删除（任务2）：发送者本人或群主/管理员，无时间窗，收端物理移除

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
