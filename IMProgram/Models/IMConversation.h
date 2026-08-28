//  IMConversation.h
//  会话列表项，对应后端 conversation.Summary（GET /api/v1/conversations）。

#import <Foundation/Foundation.h>

@class IMPresence;

NS_ASSUME_NONNULL_BEGIN

@interface IMConversation : NSObject

@property (nonatomic, copy) NSString *convID;
@property (nonatomic, assign) BOOL isGroup;            // YES=群聊（用 name/avatarURL/memberCount），NO=单聊（用 peer*）
@property (nonatomic, copy, nullable) NSString *name;         // 群名（仅群聊）
@property (nonatomic, copy, nullable) NSString *avatarURL;    // 群头像（仅群聊，空回退群名首字母圈）
@property (nonatomic, assign) NSInteger memberCount;   // 群成员数（仅群聊）
@property (nonatomic, assign) NSInteger pendingCount;  // 待审入群申请数（仅群聊且我是群主/管理员，供列表红点，G3）
@property (nonatomic, copy) NSString *peer;            // 单聊对端 uid（群聊为空）
@property (nonatomic, copy, nullable) NSString *peerNickname;  // 对端昵称（显示名/首字母，空回退 uid）
@property (nonatomic, copy, nullable) NSString *peerAvatarURL; // 对端头像（data:/http，空回退首字母圈）
/// 我给对端起的好友备注名（仅单聊；仅自己可见，显示优先级高于 peerNickname）。对应后端 peer_remark。
/// 权威值同时进 IMRemarkStore（跨页统一取显示名的地方），这里保留一份是为了列表能直接渲染。
@property (nonatomic, copy, nullable) NSString *peerRemark;
@property (nonatomic, strong, nullable) IMPresence *peerPresence; // 单聊对端在线态快照（列表绿点；群聊为 nil，在线与否按 onlineUntil 实时判）
@property (nonatomic, copy, nullable) NSString *lastContent;
@property (nonatomic, copy, nullable) NSString *lastFrom;
@property (nonatomic, copy, nullable) NSString *lastFromNickname; // 最后发送者昵称（仅群聊：列表预览"昵称: 内容"）
@property (nonatomic, assign) BOOL lastRecalled;      // 最后一条是撤回消息（预览显示"撤回了一条消息"，M4-1）
@property (nonatomic, copy, nullable) NSString *lastContentType; // 最后一条内容类型（image/video/file → 预览[图片]等，M4-6）
@property (nonatomic, copy, nullable) NSString *lastCaption;     // 最后一条的图说 caption（Telegram 模型）：列表预览「有字显字」，空则回退 [图片] 等
@property (nonatomic, assign) int64_t lastDuration;              // 最后一条语音/视频时长毫秒：voice 列表预览显 [语音] m:ss；video/other 0
@property (nonatomic, assign) int64_t latestConvSeq;
@property (nonatomic, assign) int64_t readSeq;         // 本人已读位点（首条未读 = conv_seq > readSeq）
@property (nonatomic, assign) int64_t peerReadSeq;     // 单聊对端已读位点（判断"我发的最后一条"是否已读；群聊 0）
@property (nonatomic, assign) int64_t groupReadSeq;    // 群聊全员已读位点=min(其他成员已读位点)；单聊 0。判断群消息是否"全员已读"→绿双勾（非实时，随列表/sync 刷新）
@property (nonatomic, assign) int64_t timestamp;       // 最后一条时间（毫秒）
@property (nonatomic, assign) NSInteger unread;        // 未读数（服务端 cap 999）
// M4.5 会话级设置（每用户私有；服务端 conv_update 帧多端同步）：
@property (nonatomic, assign) int64_t pinnedAt;        // 置顶时间（0=未置顶；服务端已按置顶优先排序）
@property (nonatomic, assign) BOOL muted;              // 免打扰（弱提示）
@property (nonatomic, assign) BOOL markedUnread;       // 手动标为未读（红点，不计数）
@property (nonatomic, copy, nullable) NSString *remark; // 会话备注（G1，仅本人可见、多端同步）：非空即替代 name/群名显示
/// 未读区间内有人 @我（含 @所有人），仅群聊（M4-8）。列表显「[有人@我]」红字前缀，
/// 且**穿透免打扰**：免打扰群命中时未读数仍显红底、照常计入角标。读过那条 @ 后服务端自动转 NO。
@property (nonatomic, assign) BOOL mentionUnread;

/// 列表/转发页/搜索页统一显示名：
/// 群聊 = 会话备注 > 群名 > 「群聊」；单聊 = 会话备注 > 好友备注 > 对端昵称 > 对端 uid。
/// 会话备注（G1，PUT …/remark）与好友备注（POST /friends/remark）是两件事：前者只改"这个会话"
/// 的标题（群聊也能用），后者跟人走（通讯录/选人页也变）。同时存在时按会话备注为准——它更"就近"。
@property (nonatomic, readonly) NSString *displayName;

/// 从 data.conversations 数组解析（脏数据安全）。
+ (NSArray<IMConversation *> *)conversationsFromArray:(nullable NSArray *)array;

@end

NS_ASSUME_NONNULL_END
