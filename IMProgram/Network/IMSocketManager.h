//  IMSocketManager.h
//  IM 长连接核心：封装 WebSocket（底层用系统原生 NSURLSessionWebSocketTask），
//  负责 连接 / 心跳 / 指数退避重连 / 信封收发 / ACK 超时重发。
//  对齐 IMServer/docs/PROTOCOL.md。所有回调切回主线程。

#import <Foundation/Foundation.h>
#import "IMMediaAttributes.h"
#import "IMPresence.h"

@class IMSocketManager;
@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/// 收到任意会话的新消息时广播（主线程）。会话列表等非当前页可借此实时刷新（未读/最后一条），
/// 不占用单一 delegate 槽。userInfo[kIMConvIDKey] 为该消息的会话 id。
extern NSString * const IMSocketDidReceiveMessageNotification;
/// 收到好友关系变更帧（friend）时广播（主线程）：通讯录据此实时刷新"新的朋友"/好友列表，无需切页。
/// **不含 event=remark**（备注名多端同步）——那一类不重拉列表，直接更新 IMRemarkStore
/// 并由 IMRemarkStoreDidChangeNotification 通知各页，见 IMRemarkStore.h。
extern NSString * const IMSocketDidReceiveFriendEventNotification;
/// 收到群变更帧（group）时广播（主线程）：会话列表/群资料页据此刷新。
/// userInfo：kIMConvIDKey=群 conv_id、kIMGroupEventKey=事件、kIMGroupTargetKey=受影响方 uid（可空串）。
/// 收到 event=remove 且 target=自己 → 该群已把我移出（客户端应移出该会话）。
extern NSString * const IMSocketDidReceiveGroupEventNotification;
extern NSString * const kIMGroupEventKey;
extern NSString * const kIMGroupTargetKey;
extern NSString * const kIMGroupResultKey; ///< G3 join_result 的 approved|rejected（其余事件空串）
/// 收到已读回执（read）时广播（主线程）：会话列表据此刷新——对端已读→我发的变✓✓；本人多端已读→未读清零。
extern NSString * const IMSocketDidReceiveReadNotification;
/// 消息操作（撤回/编辑/置顶，M4）应用到某条消息时广播（主线程）：聊天页/会话列表据此就地刷新。
/// **契约：socket 层已解析 wire 语义并落库，userInfo 携带与库一致的字段终值，收端无脑逐字段应用**
/// （收端不得再解读 op/pinned 等协议细节——两处解析曾各带相反的兜底默认，是静默不同步的温床）。
/// userInfo：kIMConvIDKey=会话、kIMMsgOpTargetSeqKey=目标 conv_seq(NSNumber)；按操作各带：
/// kIMMsgOpRecalledAtKey(+kIMMsgOpRecalledByKey)=撤回时刻/操作者、kIMMsgOpEditedAtKey
/// (+kIMMsgOpContentKey)=编辑时刻/新文本、kIMMsgOpPinnedAtKey=置顶时刻(0=取消置顶)。
extern NSString * const IMSocketDidApplyMsgOpNotification;
extern NSString * const kIMMsgOpTargetSeqKey;
extern NSString * const kIMMsgOpContentKey;
extern NSString * const kIMMsgOpRecalledAtKey;
extern NSString * const kIMMsgOpRecalledByKey;
extern NSString * const kIMMsgOpEditedAtKey;
extern NSString * const kIMMsgOpPinnedAtKey;
/// 我发起的消息操作被拒（如撤回超时）时广播（主线程）：userInfo[@"message"]=服务端文案。
extern NSString * const IMSocketDidRejectMsgOpNotification;
/// 某条消息被物理移除（任务2：为所有人删除 op=delete / 仅为我删除 msg_hidden）时广播（主线程）：
/// 聊天页/详情文件列表据此移除该条（区别于撤回的"改状态显墓碑"）。userInfo：kIMConvIDKey、kIMMsgOpTargetSeqKey(NSNumber)。
extern NSString * const IMSocketDidRemoveMessageNotification;
/// 会话级设置变更（置顶/免打扰/标未读/删除会话/会话备注，M4.5+G1）时广播（主线程）：会话列表据此刷新（多端同步）。
/// userInfo[kIMConvIDKey]=会话 id；action=settings 时 userInfo[kIMConvRemarkKey]=会话备注全值（可空=无备注）。
/// 收端可重拉会话列表取权威状态，或直接读 kIMConvRemarkKey 就地刷新标题。
extern NSString * const IMSocketDidUpdateConversationNotification;
extern NSString * const kIMConvRemarkKey;
/// 连接状态变化时广播（主线程）：非 delegate 页（如会话列表）据此显示 连接中/未连接。userInfo[@"state"]=IMSocketState。
extern NSString * const IMSocketDidChangeStateNotification;
/// 会话被服务端吊销（多设备管理踢下线：WS 握手回 401=本机 sid 已被踢 / token 失效）时广播（主线程）。
/// 与"网络断开"严格区分：网络抖动只重连、不发此通知；此通知**只在鉴权被拒时发**，上层（SceneDelegate）
/// 据此清登录态并跳回登录页——否则 socket 会在 token 缓存 TTL 过后静默重登，"被踢"退化成 ≤10min 的临时抖动。
extern NSString * const IMSocketDidRevokeSessionNotification;
extern NSString * const kIMConvIDKey;
/// 收到 presence 帧（某用户在线态变化）时广播（主线程）：presence 只喂给单个 delegate（打开的聊天页），
/// 此通知让非 delegate 页（如会话列表）也能就地刷新在线绿点，无需重拉 /conversations。服务端只推上线，
/// 下线仍由 onlineUntil 到期本地降级（列表在下次 reload 时熄灭）。userInfo：kIMPresenceUserKey=uid、kIMPresenceKey=IMPresence*。
extern NSString * const IMSocketDidReceivePresenceNotification;
extern NSString * const kIMPresenceUserKey;
extern NSString * const kIMPresenceKey;

/// 收到 capabilities_update（账号级自动下载策略变更，M4-7）：IMDownloadSettingsStore 据此重拉 /download-settings 做多端同步。
extern NSString * const IMSocketDidReceiveCapabilitiesUpdateNotification;

/// 语音转文字结果到达（服务端识别完成）。userInfo: @"convID"(NSString), @"convSeq"(NSNumber),
/// @"status"(NSString: done/failed/pending), @"text"(NSString, 可空)。
extern NSString * const IMSocketDidReceiveVoiceTranscriptNotification;

/// 连接状态。
typedef NS_ENUM(NSInteger, IMSocketState) {
    IMSocketStateDisconnected = 0, ///< 未连接 / 已断开
    IMSocketStateConnecting,       ///< 连接中（含重连等待）
    IMSocketStateConnected,        ///< 已连接
};

/// 外部唤醒信号（网络恢复 / 回到前台）到来时该做什么。
///
/// **抽成纯函数是为了能单测**——这件事真正的坑不在"连一下"，而在**什么时候不该连**：
///  · 主动断开后（退出登录 / 被踢下线）不能连，否则"退出登录"会被自动重连撤销；
///  · 正在连接中不能再连，否则会掐掉正在握手的那条，反而更慢；
///  · 已连接时只**探活**（发一次 ping）不重连——重连等于白白断一次好连接；socket 若其实已死，
///    ping 写失败会走既有断线路径，那时 `_reconnectAttempts` 已因上次连接成功归零，1s 后即重连。
typedef NS_ENUM(NSInteger, IMSocketWakeAction) {
    IMSocketWakeActionNone = 0,  ///< 什么都不做
    IMSocketWakeActionReconnect, ///< 清零退避档并立即重连
    IMSocketWakeActionProbe,     ///< 立即发一次心跳探活
};

/// 见 IMSocketWakeAction。manualClose=主动断开（退出登录/被踢）。
FOUNDATION_EXPORT IMSocketWakeAction IMSocketWakeActionFor(IMSocketState state, BOOL manualClose);

/// 连接态副标题文案（放标题栏副标题，同「在线」位置，无括号）：已连接返回空串。
/// 聊天页与会话列表页共用，避免两处各写一份 switch 导致文案漂移。
NS_INLINE NSString *IMSocketStateSubtitle(IMSocketState state) {
    switch (state) {
        case IMSocketStateConnecting:   return @"连接中…";
        case IMSocketStateDisconnected: return @"未连接";
        case IMSocketStateConnected:    return @"";
    }
    return @"";
}

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
/// 某用户在线状态变化（主线程）。presence 只报**变化**，初始值须由 HTTP 快照提供
/// （会话列表 peer_presence / 资料卡 presence）；服务端不推下线，靠 presence.onlineUntil 到期本地降级。
- (void)socketManager:(IMSocketManager *)manager didChangePresenceForUser:(NSString *)user presence:(IMPresence *)presence;
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

/// **立即重连/探活**：由外部唤醒信号调用（网络恢复 `IMNetworkDidBecomeReachableNotification` 已在内部
/// 自动接上；回到前台由 SceneDelegate 调）。按 `IMSocketWakeActionFor` 决定动作，幂等、可随便多调。
/// 存在的理由：指数退避最长要等 30s，断网恢复后干等一档是能被用户直接看见的"卡住"。
/// reason 只进日志，便于排查是哪路信号触发的。
- (void)reconnectNowWithReason:(NSString *)reason;

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

/// @提及变体（M4-8，仅群聊）：mentions 为被 @ 的成员 uid，mentionAll=YES 表示 @所有人。
/// 服务端会按当时群成员集过滤/去重、并校验 @所有人 的群角色权限（非群主/管理员回 300204）。
- (NSString *)sendText:(NSString *)text
                toConv:(NSString *)convID
        replyToConvSeq:(int64_t)replyToConvSeq
              mentions:(nullable NSArray<NSString *> *)mentions
            mentionAll:(BOOL)mentionAll
            completion:(nullable IMSendCompletion)completion;

/// 转发变体（M4-3）：把 text 发到 convID（群=to 空/单聊=toUserID），带 forward_from 溯源。
- (NSString *)forwardText:(NSString *)text
                  toConv:(NSString *)convID
                  toUser:(NSString *)toUserID
             forwardFrom:(NSString *)forwardFrom
              completion:(nullable IMSendCompletion)completion;

/// 转发任意类型消息（#6）：保留 content_type（text/image/video/file），content 为原文本或已上传 URL，
/// 带 forward_from 溯源。避免把图片/视频当纯文本转走（否则收方不渲染、会话预览也丢 [图片]）。
- (NSString *)forwardContent:(NSString *)content
                contentType:(NSString *)contentType
                     toConv:(NSString *)convID
                toUser:(NSString *)toUserID
             forwardFrom:(NSString *)forwardFrom
                   fileName:(nullable NSString *)fileName
                   fileSize:(int64_t)fileSize
                 completion:(nullable IMSendCompletion)completion;

/// 转发（媒体元数据变体）：attributes 带原消息的封面/尺寸/时长——**转发必须带上**，
/// 否则收端只能按"未知"渲染（比例、时长角标全丢），且这些字段发送时即冻结、事后补不回来。
- (NSString *)forwardContent:(NSString *)content
                 contentType:(NSString *)contentType
                      toConv:(NSString *)convID
                      toUser:(NSString *)toUserID
                 forwardFrom:(NSString *)forwardFrom
                    fileName:(nullable NSString *)fileName
                    fileSize:(int64_t)fileSize
                  attributes:(nullable IMMediaAttributes *)attributes
                  completion:(nullable IMSendCompletion)completion;

/// 重发一条**已落库的失败消息**（ack 超时 / 连接中断那类；内容已就绪：正文或已上传的服务器 URL）。
/// 按原 `client_msg_id` 重建 send_msg 负载再发一次，并把模型上的引用/转发溯源/@提及/媒体元数据
/// （尺寸·时长·封面·thumb·waveform·caption）原样带回——漏一个字段收端就少一样东西。
///
/// **必须沿用原 client_msg_id**：服务端按 `(conv_id, client_msg_id)` 唯一索引幂等去重
/// （PROTOCOL §超时重发），于是"上次其实已存下、只是 ack 丢了"这种情况重发只会拿回同一条的 conv_seq；
/// 换新 ID 则会绕开去重索引，让对端收到两条。上传失败那类（服务器上根本没有这条）走
/// IMMediaSendService 重传，不走这里，见 `IMResendPolicyForMessage`。
///
/// 返回是否已入队（缺 client_msg_id / content 为空 → NO，此时 completion 不会被调用）。
- (BOOL)resendMessage:(IMMessageModel *)message
               toUser:(nullable NSString *)toUserID
           completion:(nullable IMSendCompletion)completion;

/// 上报「已读到 convSeq」：对端据此显示已读双勾，本人未读随之清零（仅 read 推进已读位点）。
- (void)markReadConv:(NSString *)convID upToConvSeq:(int64_t)convSeq;

/// 发送「正在输入」给会话对端（临时态，对端短暂显示后自动消失）。
- (void)sendTypingForConv:(NSString *)convID;

/// 上报「当前要显示在线态的用户全集」（全量替换语义，见 PROTOCOL §5.5）：服务端只把这些人的
/// presence 变化推给本连接，并对新增者回一帧 presence 快照。空数组=取消全部关注（如退出聊天页）。
/// 订阅是连接级易失态——**重连后须由调用方重发**（本页在 didChangeState 连上时重发）。
- (void)watchUsers:(NSArray<NSString *> *)userIDs;

/// 撤回自己在 convID 会话里 conv_seq=targetConvSeq 的消息（M4-1）。发出 msg_op；
/// 成功由服务端广播回 msg_op 帧应用（IMSocketDidApplyMsgOp 通知），失败（超窗等）发 IMSocketDidRejectMsgOp。
- (void)recallMessageInConv:(NSString *)convID targetConvSeq:(int64_t)targetConvSeq;

/// 编辑自己在 convID 会话里 conv_seq=targetConvSeq 的文本消息（M4-5）。成功由服务端广播回 msg_op 帧应用。
- (void)editMessageInConv:(NSString *)convID targetConvSeq:(int64_t)targetConvSeq content:(NSString *)content;

/// 聊天内置顶 / 取消置顶（G0）：发 msg_op op=pin；群内限群主/管理员（服务端权威，越权回 300006）。
/// 成功由服务端广播回 msg_op 帧应用（IMSocketDidApplyMsgOp 通知），被拒走 IMSocketDidRejectMsgOp。
- (void)pinMessageInConv:(NSString *)convID targetConvSeq:(int64_t)targetConvSeq pinned:(BOOL)pinned;

/// 为所有人删除（任务2）：发 msg_op op=delete。发送者本人或群主/管理员可删（后端校验，无时间窗）；
/// 成功由服务端广播回 msg_op 帧应用（物理移除本地并发 IMSocketDidRemoveMessageNotification）。被拒走 IMSocketDidRejectMsgOpNotification。
- (void)deleteMessageForEveryoneInConv:(NSString *)convID targetConvSeq:(int64_t)targetConvSeq;

/// 「仅为我删除」本地落地（任务2）：物理移除该条并广播 IMSocketDidRemoveMessageNotification。
/// 供 HTTP hide 成功后本端立即移除，以及收到 msg_hidden 帧 / 登录 catch-up 时移除。
- (void)removeLocalMessageInConv:(NSString *)convID targetConvSeq:(int64_t)targetConvSeq;

/// 「仅删除自己」的完整编排（任务2，聊天页/详情页共用，避免各 VC 重复 HTTP+移除）：
/// REST `POST /messages/hide` 成功 → 本端物理移除（并广播移除通知、多设备同步）；失败经 completion 回错误由调用方决定是否 toast。
/// convID 空或 convSeq<=0 直接空转（completion(nil)）。completion 在 HTTP 回调线程（IMHTTPService 保证主线程）。
- (void)hideMessageInConv:(NSString *)convID targetConvSeq:(int64_t)targetConvSeq
               completion:(nullable void (^)(NSError *_Nullable error))completion;

/// 发送富媒体（M4-6）：content=已上传 URL，contentType=image|video|file。群聊 toUser 传空。返回 client_msg_id。
- (NSString *)sendMedia:(NSString *)url
           contentType:(NSString *)contentType
                toConv:(NSString *)convID
                toUser:(NSString *)toUserID
            completion:(nullable IMSendCompletion)completion;

/// 发送文件消息，fileName 随消息持久化并同步到所有终端。
- (NSString *)sendFile:(NSString *)url
              fileName:(NSString *)fileName
              fileSize:(int64_t)fileSize
                toConv:(NSString *)convID
                toUser:(NSString *)toUserID
            completion:(nullable IMSendCompletion)completion;

/// 发送富媒体（相册变体，M4+）：groupID 非空时同批多图/视频共享，收发两端聚簇渲染宫格。
- (NSString *)sendMedia:(NSString *)url
           contentType:(NSString *)contentType
                toConv:(NSString *)convID
                toUser:(NSString *)toUserID
                groupID:(nullable NSString *)groupID
            completion:(nullable IMSendCompletion)completion;

/// 发送富媒体（相册+封面变体，M4+）：poster 非空=视频首帧封面 URL，随消息下发，收端（尤其 Web）直显免解码。
- (NSString *)sendMedia:(NSString *)url
           contentType:(NSString *)contentType
                toConv:(NSString *)convID
                toUser:(NSString *)toUserID
                groupID:(nullable NSString *)groupID
                 poster:(nullable NSString *)poster
            completion:(nullable IMSendCompletion)completion;

/// 发送富媒体（完整元数据变体，M4+，**其余重载最终都汇到这里**）：attributes 带相册分组、封面、
/// 像素宽高、视频时长与原始字节数（见 IMMediaAttributes / PROTOCOL §4.1），nil 等价于无元数据。
- (NSString *)sendMedia:(NSString *)url
            contentType:(NSString *)contentType
                 toConv:(NSString *)convID
                 toUser:(NSString *)toUserID
             attributes:(nullable IMMediaAttributes *)attributes
             completion:(nullable IMSendCompletion)completion;

/// 登记一个会话用于增量同步：每次（重）连成功后，自动从该会话已同步位点发 sync_req
/// 拉取离线/缺失的消息。
- (void)trackConversation:(NSString *)convID;

/// 同上，但用调用方提供的位点作为同步起点（取与内存值的较大者）。
/// 上层从 IMDatabase 取已存最大 conv_seq 传入，实现 App 重启后的断点续传。
- (void)trackConversation:(NSString *)convID syncedSeq:(int64_t)syncedSeq;

@end

NS_ASSUME_NONNULL_END
