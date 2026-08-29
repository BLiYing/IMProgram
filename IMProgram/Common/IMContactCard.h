//  IMContactCard.h
//  个人名片消息（content_type=contact）的 content 解析 / 构造 / 预览（纯逻辑，可单测）。
//  content 是极小的 JSON 快照 {"u","n","a"}——uid / 发送时冻结的昵称 / 头像 URL。
//  协议见 docs/PROTOCOL.md §4.1，设计见 docs/CONTACT_CARD_DESIGN.md。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// contact 消息的 content_type 常量（与后端 store.ContentTypeContact 一致）。
FOUNDATION_EXPORT NSString * const IMContentTypeContact;

/// 解析后的名片快照。
@interface IMContactCard : NSObject
@property (nonatomic, copy) NSString *userID;               ///< u（必有，解析成功即非空）
@property (nonatomic, copy, nullable) NSString *nickname;   ///< n（发送时冻结的**真实昵称**，非备注）
@property (nonatomic, copy, nullable) NSString *avatarURL;  ///< a（可空 → 回退首字母圈）
@end

/// 解析 contact 消息的 content JSON。**非法 JSON / 缺 u → 返回 nil**：
/// 调用方据此降级（气泡显一行灰字不可点；详情页/收藏页**直接不收录**——列表里不该出现点不动的空行）。
FOUNDATION_EXPORT IMContactCard *_Nullable IMContactCardParse(NSString *_Nullable content);

/// 构造 contact 消息的 content JSON；userID 为空返回 nil。
/// ⚠️ nickname 必须传**真实昵称**（`IMUserCard.nickname`），**绝不能传 `displayName`**——
/// displayName 会优先返回我给对方起的备注，发出去就是泄露"我给你起的外号"（见设计文档 §2.4）。
FOUNDATION_EXPORT NSString *_Nullable IMContactCardBuild(NSString *_Nullable userID,
                                                         NSString *_Nullable nickname,
                                                         NSString *_Nullable avatarURL);

/// 会话列表 / 置顶横幅 / 合并转发条目的预览文案：`[个人名片] 小明`。
/// 无昵称回落 uid；解析失败回落裸 `[个人名片]`（不崩、不漏 JSON 原文）。
FOUNDATION_EXPORT NSString *IMContactCardPreview(NSString *_Nullable content);

NS_ASSUME_NONNULL_END
