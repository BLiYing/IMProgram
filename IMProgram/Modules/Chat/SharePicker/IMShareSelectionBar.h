//  IMShareSelectionBar.h
//  分享选择页多选态的**底部已选栏**（SHARE_PICKER_UX_SKETCH ①④）：
//  左边横向已选头像条（复用建群页 IMSelectedChipStrip，点 ✕ 取消勾选），右边「发送(N)」。
//  什么都没选时显示「选择最多 9 个好友或群聊」+ 置灰发送；栏本身常驻，避免列表高度跳动。
//  主页与「我的好友」「我的群聊」两个子页各挂一条，读同一份 IMShareSelection。

#import <UIKit/UIKit.h>

@class IMShareSelection;
@class IMConversation;
@class IMSelectedChip;

NS_ASSUME_NONNULL_BEGIN

@interface IMShareSelectionBar : UIView

/// 栏的内容高度（不含底部安全区）。
@property (class, nonatomic, readonly) CGFloat contentHeight;

@property (nonatomic, copy, nullable) void (^onRemove)(NSString *convID);
@property (nonatomic, copy, nullable) void (^onSend)(void);

/// 按选中集重画。scrollToEnd=YES：刚勾了一项，滚到末尾让人看见它进来。
- (void)reloadWithSelection:(IMShareSelection *)selection scrollToEnd:(BOOL)scrollToEnd;

@end

/// 会话 → 已选格子（底部已选栏与确认面板网格共用：群用 avatarURL / seed=convID，单聊用 peerAvatarURL / seed=peer）。
FOUNDATION_EXPORT IMSelectedChip *IMShareChipForConversation(IMConversation *c);

NS_ASSUME_NONNULL_END
