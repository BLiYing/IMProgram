#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 发送被拒的系统行（微信式）：气泡/缩略图下方居中灰字，不弹窗。
/// 命中「可恢复」错误码时再补一行强调色动作短语并开启整行点击（当前仅 200103 非好友 → 发送好友申请）。
///
/// 三类气泡共用：文本/文件（IMBubbleCell）、单图/视频（IMImageCell）、相册宫格（IMAlbumCell）。
/// 抽出来的原因：早期只有 IMBubbleCell 渲染 note，导致图片/视频被拒时既无文案也无恢复入口
/// （模型里 note 有值，但媒体 cell 压根没有承载它的视图）。
@interface IMRejectNoteView : UIView

/// 配置内容。note 为空 → `hasContent` = NO，视图自动隐藏（调用方据此切回「内容贴底」约束）。
/// code 为服务端业务码（200102 被拉黑 / 200103 非好友 / 300004 禁言 …），决定是否给恢复入口。
- (void)configureWithNote:(nullable NSString *)note code:(NSInteger)code;

/// 当前是否有系统行内容（调用方据此切换底部约束组）。
@property (nonatomic, readonly) BOOL hasContent;

/// 点动作短语。仅可恢复码有效；不可恢复时整行不可点，本回调不会触发。
@property (nonatomic, copy, nullable) void (^onActionTap)(void);

@end

NS_ASSUME_NONNULL_END
