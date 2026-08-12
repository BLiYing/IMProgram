//  IMPinnedMessage.h
//  会话置顶消息（G0）：`GET /api/v1/conversations/{id}/pinned` 的一项，顶部置顶横幅与置顶列表的渲染源。
//  字段是横幅所需最小集——点它跳到聊天里那条消息本体，不在这里重建富渲染。
//  纯逻辑（预览文案 / 发送者名）与 Web `src/pinned.ts` 保持一致（parity）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPinnedMessage : NSObject

@property (nonatomic, assign) int64_t convSeq;
@property (nonatomic, copy) NSString *serverMsgID;
@property (nonatomic, copy) NSString *from;
@property (nonatomic, copy, nullable) NSString *fromNickname; ///< 仅群聊下发（空则回退 uid）
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, assign) int64_t timestamp;
@property (nonatomic, assign) int64_t pinnedAt;

/// 从服务端 JSON 解析（脏数据安全：类型不符即回退默认值，绝不抛）。conv_seq 缺失/非正返回 nil。
+ (nullable instancetype)fromJSON:(nullable NSDictionary *)json;

/// 横幅/列表里的单行预览文案。非文本消息的 content 是 URL，直接显类型词
/// ——横幅只有一行高，塞 URL 既难读又会撑破布局。
- (NSString *)previewText;

/// 横幅上的发送者显示名：群聊优先群内昵称、回退 uid；单聊返回空串（不显发送者）。
- (NSString *)senderLabelForGroup:(BOOL)isGroup;

@end

NS_ASSUME_NONNULL_END
