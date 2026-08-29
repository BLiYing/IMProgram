#import <UIKit/UIKit.h>
#import "IMGroupInfo.h"

@class IMMessageModel;

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
    UIView  *_senderRoleBadge;                 ///< 群主/管理员角色徽标（胶囊，默认隐藏），锚在发送者昵称右侧同一行。
    UILabel *_senderRoleLabel;                 ///< 徽标文字（「群主」/「管理员」）。
}

/// 群聊对方头像点击 → 进该成员资料页（微信式）。头像隐藏时点击无效。
@property (nonatomic, copy, nullable) void (^onAvatarTap)(void);

/// 「未读消息」分割线开关：仅首条未读那行传 YES。
- (void)applyUnreadDivider:(BOOL)shows;

/// 安装群聊发送者角色徽标：在给定昵称 label 右侧同一行挂一个胶囊徽标（默认隐藏），
/// 并给昵称加「最多约 12 个中文字」的尾部截断宽度。各消息 cell 在 init 造好自己的昵称 label 后调用一次。
/// 徽标样式/文案/截断规则收敛于此，避免逐 cell 重复（群主=主色调 tint、管理员=次要灰，与 Web 语义对齐）。
- (void)installSenderRoleBadgeForNameLabel:(UILabel *)nameLabel;

/// 配置发送者昵称行：设昵称文本（已截断）+ 按角色显示「群主/管理员」徽标（普通成员或空名隐藏徽标）。
/// nameLabel 的显示/隐藏与顶部约束切换仍由各 cell 自理，本方法只管文字与徽标。
- (void)applySenderName:(nullable NSString *)name
                   role:(IMGroupRole)role
            toNameLabel:(UILabel *)nameLabel;

/// 气泡右下角「时间 + 状态勾」富文本：时间(灰)；自己的消息追加 已送达 ✓(灰) / 已读 ✓✓(绿) /
/// 「发送中…」/「未发送 ✗」(红)。原在 IMBubbleCell 私有，个人名片卡片气泡也要同一套排法，
/// 上提到基类的**类方法**（纯函数式，只读入参与 IMTheme，不碰实例状态）。
/// 类方法而非实例方法，是因为 IMBubbleCell **不继承本类**（它是独立的 UITableViewCell），
/// 但同样要用这段排法——做成类方法两边共用一份，不必为此改 IMBubbleCell 的继承。
/// **注意**：failed 态只出文字，**没有**可点重发的红❗——那套只有语音 cell（onRetryTap）有。
+ (NSAttributedString *)attributedMetaForMessage:(IMMessageModel *)message
                                            mine:(BOOL)mine
                                     peerReadSeq:(int64_t)peerReadSeq;

/// 发送者昵称截断规则（各类气泡共用，含文本气泡的富文本首行）：最多约 12 个中文字，
/// 超出按「书写字符簇」计数尾部截断并加省略号。空串原样返回。
+ (NSString *)clampSenderName:(nullable NSString *)name;

@end

NS_ASSUME_NONNULL_END
