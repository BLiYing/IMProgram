#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMChatRecordCell : UITableViewCell
/// 长按菜单高亮/收起动画的目标视图（=卡片本体）。
@property (nonatomic, strong, readonly) UIView *previewTargetView;
@property (nonatomic, copy, nullable) void (^onTap)(void);
/// 点群聊对方头像 → 进该成员资料页（VC 在群聊对方卡片上挂载；单聊/自己不挂）。
@property (nonatomic, copy, nullable) void (^onAvatarTap)(void);
/// 点被拒收系统行的恢复动作（当前仅非好友 200103 → 发送好友申请；其余拒收码无动作，不触发）。
@property (nonatomic, copy, nullable) void (^onNoteActionTap)(void);
/// senderName：群聊对方消息连续段首条的发送者昵称（卡片上方主色小字）；单聊/自己/非段首传 nil。
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine
                  senderName:(nullable NSString *)senderName;
/// 群聊对方消息：留 30pt 头像列（gutter=YES → leading 12→48）；连续段末条（showAvatar）显示头像。
/// 与 IMBubbleCell / IMImageCell / IMAlbumCell / IMLinkCardCell 同签名，保持各类气泡左对齐一致。
- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
