//  IMPinnedBannerView.h
//  聊天页顶部「置顶消息」横幅（G0）：竖条 + 「📌 置顶消息 · N 条 · 发送者」+ 单行预览 + 右侧 ≡ + ✕。
//  恒显**最新置顶**一条、不轮转；点整条 / 点 ≡ = 打开置顶面板（PINNED_PANEL_DESIGN §1）。
//  群公告横幅（G1）落地后排在它上面，优先级 公告 > 置顶。

#import <UIKit/UIKit.h>

@class IMPinnedMessage;

NS_ASSUME_NONNULL_BEGIN

/// 横幅样式：置顶=蓝条 pin，公告=橙条 megaphone，入群申请=蓝条 person.badge.plus（仅群主/管理员，G3）。可同屏。
typedef NS_ENUM(NSInteger, IMBannerStyle) {
    IMBannerStylePinned = 0,
    IMBannerStyleAnnouncement,
    IMBannerStyleApproval,
};

@interface IMPinnedBannerView : UIView

/// 创建指定样式的横幅（默认 init 为置顶样式，兼容 G0 既有调用）。
- (instancetype)initWithStyle:(IMBannerStyle)style;

/// 点横幅主体（置顶样式 = 打开置顶面板；公告 / 申请样式见各自宿主）。
@property (nonatomic, copy, nullable) void (^onTap)(void);
/// 点右侧 ≡（打开置顶面板，与点主体等价）。置顶样式**恒显**（单条也显，作为「点我是列表」的提示）。
@property (nonatomic, copy, nullable) void (^onList)(void);
/// 点右侧关闭（✕）：**非破坏性收起本横幅**（不取消置顶、不撤下公告）。由聊天页据此隐藏该横幅。
@property (nonatomic, copy, nullable) void (^onClose)(void);

/// 公告样式专用：直接铺一段公告文本（无计数/发送者/列表键）。text 空=隐藏横幅。
- (void)applyAnnouncement:(nullable NSString *)text;

/// 入群申请样式专用（G3，仅群主/管理员）：显示「N 人申请加入本群 · 点击审批」。count<=0=隐藏。
- (void)applyApprovalCount:(NSInteger)count;

/// 刷新展示。item 为 nil 时自身 hidden=YES（调用方据此收起高度）。
/// total>1 时 kicker 带「· N 条」、竖条上亮下暗；isGroup 决定是否显示发送者名。
- (void)applyItem:(nullable IMPinnedMessage *)item
            total:(NSInteger)total
          isGroup:(BOOL)isGroup;

/// 横幅固定高度（供聊天页调整 tableView 顶部内边距）。
+ (CGFloat)bannerHeight;

@end

NS_ASSUME_NONNULL_END
