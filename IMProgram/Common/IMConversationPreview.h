//  IMConversationPreview.h
//  会话「最后一条消息」的媒体类摘要（纯函数，可测）：image/video/file/chat_record/location/
//  contact/call/voice → 占位或结构化文案；文本/未识别类型返回 nil，调用方回退原文。
//  从 IMConversationListViewController 的 cell 配置里抽出，供会话列表与应用内横幅（NOTIFICATIONS_P1_DESIGN
//  §1.2「摘要复用会话列表最后一条预览的格式化函数，不另写一套」）共用同一份判定，不重复维护两处占位文案表。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// contentType 对应的媒体摘要：
/// - image/video/file 有 caption 时直接显 caption（图说「有字显字」）；
/// - chat_record/location 固定占位；
/// - contact 走 IMContactCardPreview；
/// - call 走 IMCallRecordRender（missedCall 输出「未接来电」红字判据，可传 NULL 不要）；
/// - voice 显 `[语音] m:ss`；
/// - 其余（含纯文本 "text"、未识别类型）返回 nil，调用方回退 content 原文。
///
/// mine/isGroup 只用于 call 记录渲染（「我方是否未错过」与群系统条文案）。durationMs 仅 voice 用。
FOUNDATION_EXPORT NSString *_Nullable IMConversationMediaPreview(NSString *_Nullable contentType,
                                                                  NSString *_Nullable caption,
                                                                  NSString *_Nullable content,
                                                                  int64_t durationMs,
                                                                  BOOL mine,
                                                                  BOOL isGroup,
                                                                  BOOL *_Nullable missedCall);

NS_ASSUME_NONNULL_END
