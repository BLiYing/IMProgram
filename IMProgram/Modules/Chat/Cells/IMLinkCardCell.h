#import <UIKit/UIKit.h>
#import "IMMessageCell.h"

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMLinkCardCell : IMMessageCell
/// 进程内 OG 预览缓存（NSString url → NSDictionary 预览负载）。**跨 cell 共享**：
/// 文本气泡里首个 URL 的 IMLinkPreviewView 也从这里取，同一 URL 全站只抓一次。
+ (NSCache<NSString *, NSDictionary *> *)previewCache;

/// 长按菜单高亮/收起、引用跳转闪烁的目标视图（=网址文本+OG 卡片整体，与 Web 一致一起高亮）。
@property (nonatomic, strong, readonly) UIView *previewTargetView;
@property (nonatomic, copy, nullable) void (^onTap)(NSString *url);
/// OG 预览异步到达、卡片展开改变了行高 → 回调聊天页刷一次行高（否则内容被压进旧行高，滚动后才正常）。
@property (nonatomic, copy, nullable) void (^onContentSizeResolved)(void);
/// peerReadSeq：气泡右下角「时间 + ✓/✓✓」要用（与 IMChatRecordCell / IMContactCardCell 同签名）。
/// 此前本 cell 没有这个参数、也没有时间——纯链接消息收发两端都看不出是什么时候的（2026-09-15 用户报）。
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                  senderName:(nullable NSString *)senderName
                  senderRole:(IMGroupRole)senderRole;
// onAvatarTap / applyUnreadDivider: 由 IMMessageCell 基类提供。

/// 群聊对方消息的头像列 + 昵称（与 IMBubbleCell/IMImageCell 同签名）：gutter=YES 时左移 30pt 头像列对齐。
- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
