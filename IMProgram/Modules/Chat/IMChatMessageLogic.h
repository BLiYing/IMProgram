//  IMChatMessageLogic.h
//  聊天消息的文件级纯逻辑（无 UI、无状态）：@提及 token 判定、未读计数口径、引用占位快照。
//  从 IMChatViewController.m 抽出，便于单测直接引头（原为前置声明）与跨端契约对齐。

#import <Foundation/Foundation.h>

@class IMMessageModel;
@class IMMentionSpan;

NS_ASSUME_NONNULL_BEGIN

/// 文本里是否存在一个**完整的** `@名字` token（M4-8）。
///
/// 必须按 token 边界判定、不能用裸 containsString:：昵称互为前缀时（「小美」/「小美丽」），
/// `@小美丽 开会` 会把根本没被提及的「小美」也算进 mentions，让他收到一条穿透免打扰的错误强提醒。
/// 判定规则：token 后面必须紧跟**空白或字符串结尾**。与 Web `containsMentionToken` 同一套。
FOUNDATION_EXPORT BOOL IMChatTextContainsMentionToken(NSString *_Nullable text, NSString *_Nullable displayName);

/// 扫描文本里的 `@名字` token，产出 **@ 片段**（发送侧用；协议见 IMServer/docs/PROTOCOL.md §4.1）。
///
/// token 边界与 `IMChatTextContainsMentionToken` 完全同规则（后接空白或结尾；长名优先，
/// 防 `@小美` 误命中 `@小美丽`），与 Web 的 `resolveMentionSpans` 逐条对齐。
///
/// `nameToUID` 是「显示名 → uid」。同名多人只能记住一个 uid——这是**片段**的固有限制
/// （一段文本只能链向一个人）；`mentions`（谁收到强提醒）不受影响，仍按每个候选独立判定。
/// uid 传空串表示 `@所有人`。
FOUNDATION_EXPORT NSArray<IMMentionSpan *> *IMChatScanMentionSpans(NSString *_Nullable text,
                                                                   NSDictionary<NSString *, NSString *> *_Nullable nameToUID);

/// 过滤出**与这段文本对得上**的片段（渲染侧用）。
///
/// 判据与服务端 `normalizeMentionSpans` / Web `segmentMentionsBySpans` 同一条：不越界、
/// 该位置确是 `@`、彼此不重叠。对不上就跳过——编辑过的老消息、折叠截断的前缀、脏数据都会走到这，
/// 全跳完调用方就回落到按昵称扫文本的老路。**两边都不信任偏移**。
FOUNDATION_EXPORT NSArray<IMMentionSpan *> *IMChatValidMentionSpans(NSString *_Nullable text,
                                                                    NSArray<IMMentionSpan *> *_Nullable spans);

/// 该 content_type 是否计入未读——**与服务端 conversation.unreadCount 同口径**（M4-8）：
/// `msg_op` 事件行（撤回/编辑/置顶）是操作、`system` 系统消息（改名/入群/禁言）是群内留痕，
/// 两者都不是"有人跟我说话了"，均不计未读。未读分割线与 ↓N 的定位必须照此排除，
/// 否则分割线会落在不计数的行上、与角标数字对不上。
FOUNDATION_EXPORT BOOL IMContentTypeCountsAsUnread(NSString *_Nullable contentType);

/// 会话的**对外可见名**——会被写进发出去的消息内容（当前：合并转发 chat_record 的标题 `t` 与
/// 单聊条目名 `n`）的场合必须用它，**绝不能用聊天页标题**。
///
/// 为什么单列一个口径：聊天页标题走的是"备注优先"（好友备注 / 会话备注 G1），而这两种备注都
/// **仅本人可见**。把标题塞进合并转发 JSON，等于把"我给他起的私房名"随消息发给了收件人——
/// 收件人看到的卡片会写着「老王 的聊天记录」。故对外一律回落到双方都认的公开名：
/// 群聊=真实群名，单聊=对端昵称；都缺则 uid / 「聊天」。
FOUNDATION_EXPORT NSString *IMConversationPublicName(BOOL isGroup,
                                                     NSString *_Nullable groupName,
                                                     NSString *_Nullable peerNickname,
                                                     NSString *_Nullable peerID);

/// 合并转发卡片标题 `t` 的**唯一生成口径**（与 Web `chatRecordTitle` 逐字对齐）。
///
/// 群聊一律固定串「群聊的聊天记录」，**绝不写真实群名**：收件人往往不在那个群里，群名本身就是信息
/// （「XX 病友群」），而 `t` 会被冻结进消息内容、还能被收件人再次转发，泄露没有回收路径。微信同款。
/// 单聊写双方名字——只写对方的话，收件人看不出这是「对方和谁」的对话。
///
/// 名字用**公开名**（昵称），不能用聊天页标题：备注（好友备注 / 会话备注 G1）仅本人可见，
/// 写进去等于把「我给他起的私房名」发出去（见 IMConversationPublicName）。
/// 缺名逐级降级到「聊天记录」，**绝不落到 10 位内部 ID**（内部 ID 不上屏是全局纪律）。
FOUNDATION_EXPORT NSString *IMChatRecordTitle(BOOL isGroup,
                                              NSString *_Nullable peerPublicName,
                                              NSString *_Nullable myPublicName);

/// 发送失败消息的重发路径。**红❗ 是否可点、点了走哪条路，全端唯一判据**——
/// 各 cell 的红❗显隐与聊天页的重发分派都读它，别在 cell 里各判各的（头像列曾因此漏接两次）。
typedef NS_ENUM(NSInteger, IMResendPolicy) {
    /// 不可重发：非本人 / 非失败态 / 已拿到 conv_seq / 被服务端明确拒收。
    IMResendPolicyNone = 0,
    /// 上传失败：媒体从没到过服务器（content 仍是 `im-pending://` 本地引用，或压根没落盘）。
    /// 从本地副本重传后再发，**换新 client_msg_id**——服务端根本没这条，不存在重复风险。
    IMResendPolicyRetryUpload,
    /// send_msg 失败（ack 超时 / 连接中断）：内容已就绪（正文或已上传的服务器 URL）。
    /// 必须按**原 client_msg_id** 重发，靠服务端 `(conv_id, client_msg_id)` 唯一索引幂等去重——
    /// 换新 ID 会在"服务端其实已存下、只是 ack 丢了"时让对端收到两条（PROTOCOL §超时重发）。
    IMResendPolicySameID,
};

/// 判定一条消息的重发路径。mine = 是否本人发送（调用方按 `m.from == 自己 uid` 传）。
///
/// **被拒收判据用 `note` 而不是 `noteCode`**：noteCode 是瞬态、不落库的（见 IMMessageModel），
/// 重进会话后被拉黑/被禁言那条的 noteCode 归 0、note 文案还在。若按 noteCode 判，
/// 这些"重发必然再次失败"的消息在重启后会重新变成可点，点了只是白等一轮超时。
FOUNDATION_EXPORT IMResendPolicy IMResendPolicyForMessage(IMMessageModel *_Nullable message, BOOL mine);

NS_ASSUME_NONNULL_END
