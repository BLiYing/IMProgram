#import <UIKit/UIKit.h>
#import "IMGroupInfo.h"
#import "IMFailBadgeView.h"  // 失败红❗（各消息 cell 共用同一款；子类要拿它的 anchor 补约束）

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
    IMFailBadgeView *_failBadge;               ///< 发送失败红❗（点击重发）。子类只补两条定位约束，见下。
    NSLayoutConstraint *_failBadgeAnchor;      ///< 子类登记的"贴到自己内容区左侧"约束：仅失败时激活，避免恒占位挤压内容。
}

/// 群聊对方头像点击 → 进该成员资料页（微信式）。头像隐藏时点击无效。
@property (nonatomic, copy, nullable) void (^onAvatarTap)(void);

/// 发送失败红❗点击 → 重发该条（宿主按 IMResendPolicyForMessage 分派）。
/// 只有「本人发送 && 可重发」时红❗才吃点击；被拒收的消息红❗照显但不可点。
@property (nonatomic, copy, nullable) void (^onRetryTap)(void);

/// 登记红❗的定位约束（子类在 init 里造好、**不要**自己激活）：
/// 通常是 `[_failBadge.trailingAnchor constraintEqualToAnchor:<自己内容区>.leadingAnchor constant:-6]`，
/// 另需自行激活一条 centerY 对齐约束（红❗垂直居中于内容区，与内容高度无关，可常驻激活）。
/// 背景：头像列与未读分割线都曾因"逐 cell 手接、漏接某一种"整体错位（踩坑两次），失败红❗此前也漏了
/// 名片/链接卡/合并转发三种 —— 故一并收进基类，新 cell 继承即自带。
- (void)installFailBadgeAnchor:(NSLayoutConstraint *)anchor;

/// 按消息状态显示/隐藏红❗并决定它可不可点（判据单一来源：IMResendPolicyForMessage）。
/// 各 cell 在 configure 里调一次即可，不要自己判 status。
- (void)applyFailBadgeForMessage:(IMMessageModel *)message mine:(BOOL)mine;

/// 相册宫格专用：一条"消息"是一整组成员，显隐/可点要按**整组**算（哪一格失败由格内 "!" 表达），
/// 故由调用方算好再传进来。普通 cell 一律用上面那个按消息判的版本。
- (void)applyFailBadgeShows:(BOOL)shows tappable:(BOOL)tappable;

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
/// **注意**：failed 态在气泡内只出文字（"未发送 ✗"）；可点重发的红❗是**气泡外**另一件东西，
/// 由基类的 `_failBadge` / `applyFailBadgeForMessage:mine:` 统一承载（IMBubbleCell 自持一份同款）。
+ (NSAttributedString *)attributedMetaForMessage:(IMMessageModel *)message
                                            mine:(BOOL)mine
                                     peerReadSeq:(int64_t)peerReadSeq;

/// 发送者昵称截断规则（各类气泡共用，含文本气泡的富文本首行）：最多约 12 个中文字，
/// 超出按「书写字符簇」计数尾部截断并加省略号。空串原样返回。
+ (NSString *)clampSenderName:(nullable NSString *)name;

@end

NS_ASSUME_NONNULL_END
