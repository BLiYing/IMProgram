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

/// 系统消息的一个可渲染片段（对应后端 protocol.SysSegment）。
@interface IMSysSegment : NSObject
/// 非空 = 这段是某人的名字：按本地显示名重渲染 + 可点进资料页。空 = 固定文案，原样显示。
@property (nonatomic, copy, nullable) NSString *uid;
/// 服务端生成时的字面（公开昵称 / 固定文案）。**不含任何人的私有备注**——这条消息全群可见。
@property (nonatomic, copy) NSString *text;
/// 从 sys_segments 数组解析（脏数据安全）；无有效段返回 nil。
+ (nullable NSArray<IMSysSegment *> *)segmentsFromArray:(nullable NSArray *)array;
/// 序列化回数组（落 SQLite 用）。
+ (NSArray<NSDictionary *> *)arrayFromSegments:(nullable NSArray<IMSysSegment *> *)segments;

/// 名字段在**本机**的显示名，两处渲染（聊天页系统行 / 会话列表预览）唯一口径：
/// **是我自己 → 「我」**（对齐微信；否则「用户1002 将 用户3001 移出群聊」里那个 `用户1002` 就是自己，
/// 读着像在说别人）→ 我给他起的备注 → 他在本群的昵称 → 服务端生成时的字面。
/// selfUID 为空即跳过「我」替换（拿不到当前账号时宁可显真名）。
+ (NSString *)localNameForUID:(nullable NSString *)uid
                      selfUID:(nullable NSString *)selfUID
                groupNickname:(nullable NSString *)groupNickname
                     fallback:(nullable NSString *)fallback;
@end

@interface IMMessageModel : NSObject

@property (nonatomic, copy)   NSString *clientMsgID;   ///< 客户端 UUID，幂等去重锚点
@property (nonatomic, copy, nullable) NSString *serverMsgID; ///< 服务端分配，ack 后填充
@property (nonatomic, copy)   NSString *convID;       ///< 会话 id
@property (nonatomic, copy, nullable) NSString *from;        ///< 发送方 uid
/// 发送方昵称（仅群聊消息带，服务端冗余下发；空回退 uid）。随消息落库（IMDatabase from_nickname 列）。
@property (nonatomic, copy, nullable) NSString *fromNickname;
/// 发送方在本群角色（仅群聊、且 owner/admin 时带；成员表未加载/发送者已退群时的气泡徽标兜底）。
/// 随消息落库（IMDatabase from_role 列），重进/退群后历史消息仍显徽标；显示仍以成员表当前角色优先。
@property (nonatomic, copy, nullable) NSString *fromRole;
@property (nonatomic, copy, nullable) NSString *to;          ///< 接收方 uid
@property (nonatomic, copy)   NSString *contentType; ///< text|image|audio...
@property (nonatomic, copy)   NSString *content;     ///< 文本内容
@property (nonatomic, copy, nullable) NSString *fileName; ///< file 消息原始文件名
@property (nonatomic, assign) int64_t fileSize; ///< file 消息原始字节数；界面只格式化，不重新读取文件
@property (nonatomic, copy, nullable) NSString *caption; ///< 图文/视频文/文件文随附文本（Telegram 图说模型）：仅 image/video/file 有，渲染在媒体/文件卡下方
/// M4-8 被 @ 的成员 uid（仅群聊，服务端已按当时成员集过滤）。落库以便**转发时重发 mentions**（触发被@强提醒）；
/// 高亮渲染仍按「文本+群成员」派生（mentionMapFor*），不依赖此字段。
@property (nonatomic, copy, nullable) NSArray<NSString *> *mentions;
@property (nonatomic, assign) BOOL mentionAll; ///< @所有人（发送时服务端已校验角色）。转发**不**重发（目标群无权会整条拒发）

/// 系统消息（content_type=system）的结构化分段：把整句拆成「固定文案 / 某人的名字」若干段。
/// 服务端在生成时只能填公开昵称，故拿到 uid 后**本端**才能把名字换成我的备注、并挂点击跳资料页。
/// 空 = 历史系统消息（服务端当时没存分段）或非系统消息 → 回退按 content 整句渲染。
@property (nonatomic, copy, nullable) NSArray<IMSysSegment *> *sysSegments;
@property (nonatomic, assign) int64_t  convSeq;      ///< 会话内单调序号，ack/new_msg 后填充
@property (nonatomic, assign) int64_t  timestamp;    ///< 服务端时间（毫秒）
@property (nonatomic, assign) IMMessageStatus status;
/// 发送失败时的系统提示（如被拉黑拒收"消息已发出，但被对方拒收了"）。**随消息落库**（IMDatabase note 列），
/// 重进会话仍在；在该条气泡下方居中显示（微信式），不弹窗。
@property (nonatomic, copy, nullable) NSString *note;
/// note 对应的服务端错误码（如 200103 非好友），决定系统行是否附带可点击的恢复入口。
/// ⚠️ **瞬态、不落库**：仅本次运行内有效，重启后 note 文案仍在但链接消失；用户点该条重试会
/// 立即重新拿到拒收码并再次显示链接，故恢复路径不会永久丢失（有意的取舍，避免为此加 DB 列）。
@property (nonatomic, assign) NSInteger noteCode;

/// M4 消息操作派生状态（撤回/编辑/置顶），随消息落库、随 new_msg/sync 冗余下发。
@property (nonatomic, assign) int64_t recalledAt;  ///< >0=已撤回（渲染居中系统行，隐藏原气泡）
@property (nonatomic, assign) int64_t deletedAt;   ///< >0=为所有人删除（任务2）：收端物理移除、不入库，区别于 recall
@property (nonatomic, copy, nullable) NSString *recalledBy; ///< 撤回操作者 uid
@property (nonatomic, assign) int64_t editedAt;    ///< >0=已编辑（标"已编辑"，M4-5）
@property (nonatomic, assign) int64_t pinnedAt;    ///< >0=聊天内置顶（M4）
/// M4-2 引用回复：目标 conv_seq + 服务端冻结的降级快照（气泡顶部引用条）。
@property (nonatomic, assign) int64_t replyToConvSeq;
@property (nonatomic, copy, nullable) NSString *replySnapshot;
@property (nonatomic, copy, nullable) NSString *replyToFrom; ///< M4-x 被引用消息发送者 uid：群聊引用条显示发送者（本地解析昵称），单聊不显示
/// M4-3 转发溯源："转发自 X"显示名（发送时冻结）。
@property (nonatomic, copy, nullable) NSString *forwardFrom;
/// M4+ 相册分组：同批多图/视频共享的客户端生成 ID（空=普通消息）；聊天页据此聚簇渲染宫格。
@property (nonatomic, copy, nullable) NSString *groupID;
/// M4+ 视频封面：首帧图 URL（发送时生成上传，随消息回带）；收端直显封面免解码原视频（空=非视频/无封面）。
@property (nonatomic, copy, nullable) NSString *poster;
/// M4+ 媒体像素宽高（image/video，发送端量出，随消息回带）；0=未知 → 气泡回退方形占位、加载完再自适应。
@property (nonatomic, assign) NSInteger mediaW;
@property (nonatomic, assign) NSInteger mediaH;
/// M4+ 视频时长（**毫秒**，随消息回带）；0=未知/非视频 → 不显时长角标。
@property (nonatomic, assign) int64_t duration;
/// M4-7 图片/视频极小模糊预览（~20px 缩略 JPEG 的 data URI，随消息回带）；未下载/门控时放大+模糊显占位（空=回退中性占位）。
@property (nonatomic, copy, nullable) NSString *thumb;
/// 语音振幅指纹（voice, P0）：base64（原始字节 ≤120，每字节 0~100 振幅百分比），随消息回带。
/// 收端不下载音频即可画气泡波形；空=退化等高条纹（服务端已把非法/超长字段静默丢弃）。
@property (nonatomic, copy, nullable) NSString *waveform;
/// M4-5 翻译：译文（**内存临时态，不落库**；翻译后挂气泡下方）。
@property (nonatomic, copy, nullable) NSString *translation;

/// 由 new_msg 的 data 字典构造一条「收到」的消息。
+ (instancetype)receivedMessageWithNewMsgData:(NSDictionary *)data;

/// 本地落库归档用：模型 ↔ 字典（plist 安全：仅字符串/数字）。
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)messageFromDictionary:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
