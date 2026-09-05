#import <UIKit/UIKit.h>
#import "IMMessageCell.h"

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMChatRecordCell : IMMessageCell
/// 长按菜单高亮/收起动画的目标视图（=卡片本体）。
@property (nonatomic, strong, readonly) UIView *previewTargetView;
@property (nonatomic, copy, nullable) void (^onTap)(void);
// onAvatarTap 由 IMMessageCell 基类提供（点群聊对方头像 → 该成员资料页）。
/// 点被拒收系统行的恢复动作（当前仅非好友 200103 → 发送好友申请；其余拒收码无动作，不触发）。
@property (nonatomic, copy, nullable) void (^onNoteActionTap)(void);
/// senderName：群聊对方消息连续段首条的发送者昵称（卡片上方主色小字）；单聊/自己/非段首传 nil。
/// peerReadSeq：对端已读位点，决定卡片右下角显 ✓ 还是 ✓✓（大群传 kIMPeerReadSeqHidden 不显勾）。
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
                  senderName:(nullable NSString *)senderName
                  senderRole:(IMGroupRole)senderRole;
/// 群聊对方消息：留 30pt 头像列（gutter=YES → leading 12→48）；连续段末条（showAvatar）显示头像。
/// 与 IMBubbleCell / IMImageCell / IMAlbumCell / IMLinkCardCell 同签名，保持各类气泡左对齐一致。
- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;

// applyUnreadDivider: 由 IMMessageCell 基类提供。
@end

NS_ASSUME_NONNULL_END
