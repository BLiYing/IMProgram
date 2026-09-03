//  IMMediaUtil.h
//  媒体/链接相关的小工具（聊天页、收藏页、聊天记录详情等共用，避免重复实现）。

#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

/// 相对 URL（/uploads/xxx）补成绝对地址（协议取自 IMServerEndpoint）；`data:` 原样返回；空→空串。
///
/// **绝对 URL 只接受本服务器**（host 判据见 `IMServerEndpoint.isOwnHost:forAbsoluteURL:`），
/// 外站一律返回空串。原因：消息 `content` 与 `avatar_url` 都是**发送方可控**且服务端原样存转的字段，
/// 而图片默认自动下载（IMDownloadPolicy 对 image 无条件放行）——放行任意主机 = 对方发一条消息、
/// 或仅仅把头像设成 `http://attacker/beacon.png` 再出现在你的搜索结果里，你的客户端就会**零点击**
/// 发出一个 GET，泄露 IP、粗粒度位置与精确的「已查看」时刻，并把攻击者控制的字节喂给 ImageIO。
/// 需要放外站图的**唯一**合法场景是链接预览 OG 图，走下面 IMLinkPreviewImageURL 显式豁免。
FOUNDATION_EXPORT NSString *IMMediaFullURL(NSString *_Nullable content, NSString *_Nullable host);

/// 链接预览（OG）图片地址——**唯一**允许外站绝对 URL 的入口，仅供 IMLinkCardCell / IMLinkPreviewView。
/// 相对路径仍按自家 host 补全（服务端自家邀请卡返回 /avatars/…）。
/// 新增调用点前先想清楚：这个函数会让远端指定的主机拿到本机 IP 与访问时刻。
FOUNDATION_EXPORT NSString *IMLinkPreviewImageURL(NSString *_Nullable content, NSString *_Nullable host);

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

/// 文本里第一个 http(s) URL（用于文本气泡挂 preview 卡）；无 → nil。与 Web `firstURLInText` 同款。
/// 末尾常见标点 .,;:!?)]}' 不吃进 URL，避免"看这个 https://foo.com。"把句号带上。
FOUNDATION_EXPORT NSString *_Nullable IMFirstURLInText(NSString *_Nullable text);

/// 文本内所有 http(s) URL 的字符范围（NSValue<NSRange>）→ 供 attributedString 逐段染色。
/// 与 IMFirstURLInText 同一正则，返回顺序 = 出现顺序。空/nil 文本 → 空数组。
FOUNDATION_EXPORT NSArray<NSValue *> *IMURLRangesInText(NSString *_Nullable text);

/// 合并转发卡片（chat_record JSON）的引用/预览快照：`[聊天记录] <标题>`。
/// 兼容存量截断快照（旧引用把 JSON 截 60 字入库，解析不出时正则抠 "t":"…" 标题）；全失败回落 `[聊天记录]`。
FOUNDATION_EXPORT NSString *IMChatRecordSnippet(NSString *_Nullable recordJSON);

/// 字符串是否像 chat_record 的 JSON（或其截断残段）→ 渲染端把存量脏快照就地救成 `[聊天记录] 标题`。
FOUNDATION_EXPORT BOOL IMLooksLikeChatRecordJSON(NSString *_Nullable s);

/// 合并转发记录里「一条条目」的预览文案：image→[图片]、video→[视频]、file→[文件] 名、
/// 嵌套 chat_record→`[聊天记录] 子标题`、其余→原文。三处（气泡卡片 / 详情 mini 卡片 / 详情行）
/// 共用同一 token 映射，避免各持 static 再分叉（此前 cell 与详情页已两份）。item 非法时返回空串。
FOUNDATION_EXPORT NSString *IMRecordItemPreview(NSDictionary *_Nullable item);

/// 合并转发条目的「发送者身份键」——记录详情页据此判「连续同一人」（只显一次头像与昵称）。
/// 优先 `u`（发送者键，同名不同人才分得开）；老记录没有 `u` 就退回显示名 `n`。
/// 两个前缀（`u:` / `n:`）保证键与昵称不会互相误撞。与 Web `recordSenderKey` 同口径。
/// **只做相等比较**——`u` 的取值语义见 IMRecordSenderKeysForUIDs，不得解析、不得当接口参数。
FOUNDATION_EXPORT NSString *IMRecordSenderKey(NSDictionary *_Nullable item);

/// 打包合并转发卡片时，为一组发送者 uid 算出**卡片内匿名序号**（真 uid → `s1`/`s2`/…，按首次出现顺序）。
///
/// 为什么条目里不发真 uid（2026-08-31 收口）：`GET /users/{id}` 只校验「持有合法 token」、不校验请求方
/// 与目标的关系——随机 10 位内部 ID 的**不可枚举**就是这个接口唯一的防线（见后端
/// `internal/account/userid.go` 头部注释）。把群成员的真 uid 打包发给一个不在群里的收件人，等于绕过它：
/// 对方照着拉一遍就能多拿到 @句柄 / 标签 / 注册时间，还得到一个长期可复查的稳定句柄、可挨个发好友申请。
///
/// `u` 原本的两个用途都不需要真 uid：判「连续同一人」只要卡片内可区分；查头像本就有 `a` 快照兜底
/// （`a` 还比读端查本地缓存更准——读端未必缓存过这个陌生人）。
/// **存量卡片里的 `u` 仍是真 uid**，故读端一律只做相等比较。空串/nil 的 uid 不占号。
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *IMRecordSenderKeysForUIDs(NSArray<NSString *> *_Nullable uids);

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
