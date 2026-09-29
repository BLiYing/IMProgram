//  IMInAppBannerContent.h
//  应用内横幅（NOTIFICATIONS_P1_DESIGN §1.2）标题/正文的纯函数拼装，与视图/动画完全解耦、可离线单测。
//
//  标题 = 会话显示名（与会话列表同一来源，私聊备注>昵称、群聊会话备注>群名）；
//  正文 = 该类型「消息预览」关 → 固定 notif.preview.hidden；开 → 私聊显消息摘要，群聊显
//  「发送者：摘要」。摘要复用 IMConversationMediaPreview（IMConversationPreview.h），不另写一套。
//  头像仍走会话列表同款 UILabel+IMAvatar 组件渲染（系统通知会话照样出应用图标）——本类只负责
//  算出 avatarURL/avatarSeed/avatarDisplayName 这三个入参，渲染逻辑留给调用方（视图层）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMInAppBannerContent : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *body;
@property (nonatomic, copy, nullable) NSString *avatarURL;
@property (nonatomic, copy) NSString *avatarSeed;
@property (nonatomic, copy) NSString *avatarDisplayName;
@end

/// 纯函数：拼出横幅标题/正文。
/// - title：会话显示名（调用方已按 IMConversation.displayName 取好）。
/// - isGroup：群聊正文带「发送者：」前缀，私聊不带。
/// - avatarURL/avatarSeed：直接透传给 UILabel+IMAvatar（系统通知会话 seed=IMSystemUserID 时组件自动出应用图标）。
/// - previewEnabled：该类型（私聊/群聊）「消息预览」开关；关闭时 body 固定 notif.preview.hidden，
///   不再看 contentType/caption/content（P0 既有语义：只藏内容，不藏「有新消息」这件事）。
/// - contentType/caption/content/durationMs：这条消息的字段，喂给 IMConversationMediaPreview。
/// - senderDisplayName：仅群聊用（发送者显示名，调用方已按备注>昵称口径解析好）。
FOUNDATION_EXPORT IMInAppBannerContent *IMInAppBannerContentBuild(NSString *title,
                                                                   BOOL isGroup,
                                                                   NSString *_Nullable avatarURL,
                                                                   NSString *avatarSeed,
                                                                   BOOL previewEnabled,
                                                                   NSString *_Nullable contentType,
                                                                   NSString *_Nullable caption,
                                                                   NSString *_Nullable content,
                                                                   int64_t durationMs,
                                                                   NSString *_Nullable senderDisplayName);

NS_ASSUME_NONNULL_END
