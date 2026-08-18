//  IMMediaUtil.h
//  媒体/链接相关的小工具（聊天页、收藏页、聊天记录详情等共用，避免重复实现）。

#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/// 相对 URL（/uploads/xxx）补 host 成绝对地址；已是 http/data: 的原样返回；空→空串。
FOUNDATION_EXPORT NSString *IMMediaFullURL(NSString *_Nullable content, NSString *_Nullable host);

/// 媒体消息在「引用/预览」场景的简短占位（本地生成，用于输入预览条与本端即时快照）：
/// 图片/视频/文件→`[图片]`/`[视频]`/`[文件] 名`，聊天记录→标题，文本→截断。
/// 与 IMRecordItemPreview / IMLocalizeReplySnippet 同族，统一在此维护，避免各页分叉。
FOUNDATION_EXPORT NSString *IMReplySnippet(IMMessageModel *m);

/// 从文件消息 URL 取原始显示文件名：存储名格式 <随机>__<原名>.<ext>，取 "__" 之后并百分号解码。
FOUNDATION_EXPORT NSString *IMMediaFileName(NSString *_Nullable content);

/// 把协议/SQLite 中的原始字节数格式化为 KB / MB / GB（1024 进制，最多一位小数）；无有效大小返回空串。
FOUNDATION_EXPORT NSString *IMFormatFileSize(int64_t bytes);

/// 把协议/SQLite 中的毫秒时间戳格式化为本地时间 yyyy-MM-dd HH:mm；无有效时间返回空串。
FOUNDATION_EXPORT NSString *IMFormatFileDateTime(int64_t timestampMillis);

/// 整条内容是否就是一个 http(s) 链接（无空白）→ 用于 URL 消息渲染判定。
FOUNDATION_EXPORT BOOL IMMediaLooksLikeURL(NSString *_Nullable s);

/// 合并转发卡片（chat_record JSON）的引用/预览快照：`[聊天记录] <标题>`。
/// 兼容存量截断快照（旧引用把 JSON 截 60 字入库，解析不出时正则抠 "t":"…" 标题）；全失败回落 `[聊天记录]`。
FOUNDATION_EXPORT NSString *IMChatRecordSnippet(NSString *_Nullable recordJSON);

/// 字符串是否像 chat_record 的 JSON（或其截断残段）→ 渲染端把存量脏快照就地救成 `[聊天记录] 标题`。
FOUNDATION_EXPORT BOOL IMLooksLikeChatRecordJSON(NSString *_Nullable s);

/// 合并转发记录里「一条条目」的预览文案：image→[图片]、video→[视频]、file→[文件] 名、
/// 嵌套 chat_record→`[聊天记录] 子标题`、其余→原文。三处（气泡卡片 / 详情 mini 卡片 / 详情行）
/// 共用同一 token 映射，避免各持 static 再分叉（此前 cell 与详情页已两份）。item 非法时返回空串。
FOUNDATION_EXPORT NSString *IMRecordItemPreview(NSDictionary *_Nullable item);

/// 解析合并转发记录 JSON → 标题(*outTitle) + 前 maxLines 条「发送者: 预览」(*outLines)。
/// maxLines<=0 时只取标题、outLines 置空；out 参数均可传 NULL。解析失败标题回落「聊天记录」。
FOUNDATION_EXPORT void IMSummarizeRecord(NSString *_Nullable json,
                                         NSString *_Nullable *_Nullable outTitle,
                                         NSArray<NSString *> *_Nullable *_Nullable outLines,
                                         NSInteger maxLines);

/// 按文件扩展名返回跨端统一类型标识；未覆盖的扩展名回退 unknown。
FOUNDATION_EXPORT NSString *IMFileTypeIdentifierForName(NSString *_Nullable name);

/// 返回指定 pointSize 的原色“折角文件卡”图标；聊天/文件选择/详情/收藏共用同一映射。
FOUNDATION_EXPORT UIImage *IMFileTypeIconForName(NSString *_Nullable name, CGFloat pointSize);

/// 引用降级快照的跨端 token 本地化：[image]/[video]/[file]（含 `[file] <名>` 带文件名）→ 中文；
/// [chat_record]/存量 JSON 就地救援；已本地化输入幂等原样。两个气泡 cell 共用（此前各持 static 已分叉）。
FOUNDATION_EXPORT NSString *IMLocalizeReplySnippet(NSString *_Nullable snap);

/// 从引用快照解析文件名：接受 wire 形 `[file] <名>` 与本端存量本地化形 `[文件] <名>`；非文件快照返回 nil。
/// 一次解析供显示与 IMFileTypeIconForName 共用，避免对本地化字符串再做 magic offset 反解。
FOUNDATION_EXPORT NSString *_Nullable IMReplySnippetFileName(NSString *_Nullable snap);

NS_ASSUME_NONNULL_END
