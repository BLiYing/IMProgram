#import <UIKit/UIKit.h>
#import "IMGroupInfo.h"   // IMGroupRole（群主/管理员气泡徽标）

@class IMMessageModel;
@class IMMentionSpan;
@class IMUploadProgress;
@class IMDownloadProgress;

NS_ASSUME_NONNULL_BEGIN

/// 富文本里挂在 `@昵称` token 段上的成员 uid（点击跳资料页用）。@所有人 无 uid、不挂此属性。
extern NSString *const IMMentionUIDAttributeName;

/// 文本消息显示分档（阈值与 Web longtext.ts 一致）：
///   Short 全显；Long 折叠前若干行 + 点气泡展开/收起；Huge 摘要卡 → 全屏阅读器。
typedef NS_ENUM(NSInteger, IMBubbleTextTier) {
    IMBubbleTextTierShort = 0,
    IMBubbleTextTierLong,
    IMBubbleTextTierHuge,
};

@interface IMBubbleCell : UITableViewCell

/// 纯文本内容的显示分档（URL 由调用方另判，不走此分档）。VC 与 cell 共用同一判据。
+ (IMBubbleTextTier)textTierForContent:(nullable NSString *)content;

/// 字数标签「约 8,400 字」（千分位、按码点计）。摘要卡与全屏阅读器共用，避免重复实现。
+ (NSString *)charCountLabelForText:(nullable NSString *)text;

/// 按 `@昵称` token 切段高亮的富文本（命中 token 用 color+medium，其余用 base）。cell 与全屏阅读器共用。
/// `mentions` = 显示名 → uid（uid 空串＝仅高亮不可点，如 @所有人）；命中且 uid 非空时挂 IMMentionUIDAttributeName。
+ (NSAttributedString *)attributedContent:(nullable NSString *)text
                                     base:(NSDictionary *)base
                             mentionColor:(UIColor *)color
                                 mentions:(nullable NSDictionary<NSString *, NSString *> *)mentions;

/// 片段版（优先）：`spans` 是服务端下发的 @ token 位置（IMMentionSpan），**不需要任何群成员表**——
/// 超级群不下发成员表，`mentions` 那条路在那里对普通成员必然失效（2026-09-01）。
/// 与本文对不上的片段（编辑过的老消息、折叠截断的前缀、脏数据）逐段跳过；一段都对不上就
/// 自动回落到 `mentions`（按昵称扫文本）。协议见 IMServer/docs/PROTOCOL.md §4.1。
+ (NSAttributedString *)attributedContent:(nullable NSString *)text
                                     base:(NSDictionary *)base
                             mentionColor:(UIColor *)color
                                 mentions:(nullable NSDictionary<NSString *, NSString *> *)mentions
                                    spans:(nullable NSArray<IMMentionSpan *> *)spans;

/// 长按菜单高亮/收起动画的目标视图（=气泡本体）：系统默认会截整行全宽快照，露出难看的底色托盘。
@property (nonatomic, strong, readonly) UIView *previewTargetView;

/// 文件消息上传中的进度（nil=非上传态）。文件气泡左侧图标位据此变圆环状态机
///（排队✕ / 上传中⏸ / 已暂停↑ / 失败↻，与媒体气泡中心按钮同一套 glyph），第二行显进度文案。
/// 必须在 configure 之前设置：configure 一次性布好整条气泡。
@property (nonatomic, strong, nullable) IMUploadProgress *uploadProgress;

/// 文件消息**下载**态（收到的文件，M4-7；nil=不显下载态）。与 uploadProgress 互斥：
/// 自己发的用 uploadProgress，收到的用 downloadProgress。图标位据此变圆环状态机（未下载↓ / 下载中⏸ / 暂停↓ / 失败↻ / 就绪=文件图标）。
@property (nonatomic, strong, nullable) IMDownloadProgress *downloadProgress;

/// 中长文本（Long 档）是否已展开（宿主按消息记忆，configure 前设置）。Huge/Short 档忽略此值。
@property (nonatomic, assign) BOOL textExpanded;

/// 本条消息里需要高亮的 `@昵称` → uid 映射（宿主按当前群成员+文本推导，configure 前设置；nil=不高亮）。
/// @所有人 以空串 uid 存入（高亮但不可点）。
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *mentionMap;

/// 文件文 caption 的 `@昵称`→uid 高亮映射（宿主按 caption 文本+群成员推导，configure 前设置；nil=不高亮）。
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *captionMentionMap;

/// 正文 / caption 的 **@ 片段**（服务端下发，configure 前设置）。有它就按位置直接高亮，
/// 不查成员表——超级群里 mentionMap 必然是空的（成员表只含治理集）。
@property (nonatomic, copy, nullable) NSArray<IMMentionSpan *> *mentionSpans;
@property (nonatomic, copy, nullable) NSArray<IMMentionSpan *> *captionMentionSpans;

/// 会话内搜索命中词（搜索态由宿主传入，configure 前设置；nil/空=不高亮）。正文与文件文 caption 的所有
/// 大小写不敏感命中段染 accent 前景 + accentSoft 底（与全局搜索页/Web `<mark>` 同语义）。
@property (nonatomic, copy, nullable) NSString *searchHighlightKeyword;

/// 把 att 中 keyword 的所有大小写不敏感命中段染色（accent+accentSoft），返回新串；keyword 空原样返回。
/// IMImageCell 图说 caption 复用。
+ (NSAttributedString *)attributed:(NSAttributedString *)att highlighting:(nullable NSString *)keyword;

/// 通用 TextKit 反查：命中点（label 坐标系）落在挂了 IMMentionUIDAttributeName 的 `@昵称` token 上
/// 时返回 uid，否则 nil。供本 cell 正文/文件文 caption 与 IMImageCell 图说 caption 共用。
+ (nullable NSString *)mentionUIDInLabel:(UILabel *)label atPoint:(CGPoint)pointInLabel;

/// 同上，另回该名字 token 在串里的完整范围（供点击后高亮回执）。不需要范围就用上面那个。
+ (nullable NSString *)mentionUIDInLabel:(UILabel *)label
                                 atPoint:(CGPoint)pointInLabel
                                   range:(nullable NSRangePointer)outRange;

/// 点中名字后的**视觉回执**：把该范围的背景色短暂点亮再淡出（约 0.22s）。
///
/// 可点的名字（系统消息里的成员、气泡里的 @昵称）此前点下去毫无反应——要等资料页 push 出来
/// 才知道点中了，而没点中就完全没有反馈，用户只会以为"这里点不动"（2026-09-05 用户反馈）。
/// 做在 label 的富文本上而不是加子视图：名字可能跨行，子视图只能画一个矩形。
+ (void)flashMentionHighlightInLabel:(UILabel *)label range:(NSRange)range;

/// 命中点（cell 坐标系）落在某个 `@昵称` token 上时返回其成员 uid，否则 nil。TextKit 反查 `_text` 富文本属性。
- (nullable NSString *)mentionUIDAtPoint:(CGPoint)pointInCell;

/// 下载进度**就地更新**（M4-7）：宿主在高频 onProgress 回调里调用，只改第二行文案 + 图标位环/字形，
/// 不重配整行、不 reloadRows（避免每片一次 reload 卡死主线程）。
- (void)updateDownloadProgress:(nullable IMDownloadProgress *)progress;

/// 文件气泡左侧图标位被点按（上传中/失败态：暂停↔继续 / 重试 / 取消；下载态：下载 / 暂停↔继续 / 重试）。
/// 完成/就绪态图标不可点，点击整条气泡=打开文件（走 VC 的表级手势）。
@property (nonatomic, copy, nullable) void (^onFileControlTap)(void);
/// 点群聊对方头像 → 进该成员资料页（VC 在群聊对方气泡上挂载；单聊/自己不挂）。
@property (nonatomic, copy, nullable) void (^onAvatarTap)(void);

/// 发送失败红❗点击 → 重发该条（宿主按 IMResendPolicyForMessage 分派）。与 IMMessageCell 子类同名同语义
/// （本类不继承 IMMessageCell，故自持一份；红❗视图本身仍是共用的 IMFailBadgeView）。
@property (nonatomic, copy, nullable) void (^onRetryTap)(void);
/// 点拒收系统行的恢复入口（当前仅 200103 非好友 → 「发送好友申请」）。
/// 仅当 message.noteCode 命中可操作码时该行才可点，否则系统行是纯文案。
@property (nonatomic, copy, nullable) void (^onNoteActionTap)(void);

/// 文本气泡里的**首个 URL** 富预览卡片被点：宿主打开链接（与 IMLinkCardCell.onTap 同款）。
/// 卡片仅在 og 抓到 title/image 时可见；抓不到时保持隐藏、正文里的高亮 URL 仍可点（另一路 onTextURLTap）。
@property (nonatomic, copy, nullable) void (^onLinkTap)(NSString *url);

/// 文本气泡里的 preview 卡片从"未拉到"变"已渲染"→ 宿主刷行高（与 IMLinkCardCell.onContentSizeResolved 同款守卫）。
@property (nonatomic, copy, nullable) void (^onLinkPreviewResolved)(void);
- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                   dayHeader:(nullable NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider
                  senderName:(nullable NSString *)senderName
                  senderRole:(IMGroupRole)senderRole
               replyThumbURL:(nullable NSString *)replyThumbURL
              replyThumbData:(nullable NSString *)replyThumbData
           replyThumbIsVideo:(BOOL)replyThumbIsVideo
               replyFromName:(nullable NSString *)replyFromName;
- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
