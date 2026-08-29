//  IMContactCardCell.h
//  个人名片消息气泡（content_type=contact）：240pt 定宽卡片，点击进对方资料页。
//  与 IMChatRecordCell / IMLinkCardCell 同族、同签名——签名不一致会漏掉群聊头像列与未读分割线。

#import <UIKit/UIKit.h>
#import "IMMessageCell.h"

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMContactCardCell : IMMessageCell
/// 长按菜单高亮/收起动画的目标视图（=卡片本体）。
@property (nonatomic, strong, readonly) UIView *previewTargetView;
/// 点卡片 → 名片里那个人的资料页。
@property (nonatomic, copy, nullable) void (^onTap)(void);
// onAvatarTap 由 IMMessageCell 基类提供（点群聊对方头像 → 该成员资料页）。

/// displayName：**收方本地**显示名（备注 > 快照昵称 > uid），由调用方按 IMRemarkStore 解析后传入
/// ——cell 不自己查 store，保持与其它 cell 「显示名由 VC 解析」的一致分工。
/// senderName：群聊对方消息连续段首条的发送者昵称；单聊/自己/非段首传 nil。
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine
                 displayName:(nullable NSString *)displayName
                 peerReadSeq:(int64_t)peerReadSeq
                  senderName:(nullable NSString *)senderName
                  senderRole:(IMGroupRole)senderRole;

/// 群聊对方消息：留 30pt 头像列（gutter=YES → leading 12→48）；连续段末条（showAvatar）显示头像。
- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
