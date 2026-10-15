//  IMPinnedMessage.h
//  会话置顶消息（G0）：`GET /api/v1/conversations/{id}/pinned` 的一项，顶部置顶横幅与置顶列表的渲染源。
//  顶层字段是横幅所需最小集；`message` 是服务端 2026-10-15 起附带的完整消息对象（与 new_msg 同形），
//  置顶面板用它走聊天页同一套气泡渲染（docs/design/PINNED_PANEL_DESIGN.md §4.0）。
//  纯逻辑（预览文案 / 发送者名）与 Web `src/pinned.ts` 保持一致（parity）。

#import <Foundation/Foundation.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMPinnedMessage : NSObject

@property (nonatomic, assign) int64_t convSeq;
@property (nonatomic, copy) NSString *serverMsgID;
@property (nonatomic, copy) NSString *from;
@property (nonatomic, copy, nullable) NSString *fromNickname; ///< 仅群聊下发（空则回退 uid）
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy, nullable) NSString *caption; ///< 图说随附文本：横幅/列表「有字显字」（媒体带 caption 时显文字）
@property (nonatomic, assign) int64_t timestamp;
@property (nonatomic, assign) int64_t pinnedAt;
/// 与 new_msg / 历史接口同形的完整消息（经 `receivedMessageWithNewMsgData:` 解析）；旧服务端不带 → nil。
@property (nonatomic, strong, nullable) IMMessageModel *message;

/// 从服务端 JSON 解析（脏数据安全：类型不符即回退默认值，绝不抛）。conv_seq 缺失/非正返回 nil。
+ (nullable instancetype)fromJSON:(nullable NSDictionary *)json;

/// 横幅/列表里的单行预览文案。非文本消息的 content 是 URL，直接显类型词
/// ——横幅只有一行高，塞 URL 既难读又会撑破布局。
- (NSString *)previewText;

/// 横幅上的发送者显示名：群聊优先群内昵称、回退 uid；单聊返回空串（不显发送者）。
- (NSString *)senderLabelForGroup:(BOOL)isGroup;

/// 兜底气泡模型（面板渲染顺序第③档：本地库没有、接口也没带完整对象）：文本保留原文，
/// 其余类型退成「类型词」纯文本气泡（如「[图片]」），绝不把 URL / JSON 铺进气泡。
- (IMMessageModel *)fallbackMessageModelInConv:(NSString *)convID;

@end

/// 集合里**最新置顶**的一条（pinned_at 最大；并列取靠前者）。横幅恒显这一条，不再轮转。空集合 nil。
FOUNDATION_EXPORT IMPinnedMessage *_Nullable IMPinnedLatestItem(NSArray<IMPinnedMessage *> *items);

NS_ASSUME_NONNULL_END
