#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 消息 cell 共享基类：收敛此前逐 cell 重复的两处机制——群头像列点击（onAvatarTap，微信式）
/// 与「未读消息」分割线。头像/分割线视图、点击插桩、分割线自身约束都在此创建；
/// 各子类只需把自身顶部内容改锚 `_unreadDivider.bottomAnchor`、把头像底对齐自身内容底。
///
/// 背景：头像列曾因逐 cell 手接、漏接某一种 cell 而整体错位（踩坑两次）；分割线也一度只有文本气泡有。
/// 统一到基类后，新增消息 cell 类型继承即自带这两者，不会再漏。
@interface IMMessageCell : UITableViewCell {
  @protected
    UILabel *_avatar;                          ///< 群聊对方头像（连续段末条显示）。子类补 leading/bottom/size 约束。
    UILabel *_unreadDivider;                   ///< 「未读消息」分割线。默认高 0（bottom==contentView.top，与无分割线布局等价）。
    NSLayoutConstraint *_unreadDividerHeight;  ///< 0=隐藏 / 28=显示。
}

/// 群聊对方头像点击 → 进该成员资料页（微信式）。头像隐藏时点击无效。
@property (nonatomic, copy, nullable) void (^onAvatarTap)(void);

/// 「未读消息」分割线开关：仅首条未读那行传 YES。
- (void)applyUnreadDivider:(BOOL)shows;

@end

NS_ASSUME_NONNULL_END
