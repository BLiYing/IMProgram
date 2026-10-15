//  IMChatBannerStack.h
//  聊天页顶部三横幅栈（G0 置顶 / G1 公告 / G3 入群申请）的自包含协作对象。
//  从 IMChatViewController 抽出：本对象只负责三条 IMPinnedBannerView 的**视图/布局/高度→内容内边距/
//  非破坏性收起持久化**这套机械逻辑；点击后的导航（开置顶面板、开公告全文、进审批列表）
//  仍是聊天页的职责，经 delegate 回调回去。
//
//  三条自上而下叠放：申请 > 公告 > 置顶（优先级）。各自高度约束在隐藏时归 0；
//  总高变化经 delegate 通知聊天页同步 tableView.contentInset.top（消息内容被顶开）。

#import <UIKit/UIKit.h>

@class IMChatBannerStack;
@class IMPinnedMessage;

NS_ASSUME_NONNULL_BEGIN

@protocol IMChatBannerStackDelegate <NSObject>
/// 三横幅叠加总高变化：聊天页据此更新 tableView 顶部内边距。
- (void)bannerStackDidChangeHeight:(IMChatBannerStack *)stack;
/// 点置顶横幅（整条主体或右侧 ≡，两者等价）：聊天页打开置顶面板（IMPinnedPanelViewController）。
- (void)bannerStackDidTapPinnedList:(IMChatBannerStack *)stack;
/// 置顶集合变了（每次 pinnedItems 赋值都回调）：聊天页把新集合推给开着的置顶面板（实时刷新 / 空集合自动收起）。
- (void)bannerStackDidChangePinnedItems:(IMChatBannerStack *)stack;
/// 点公告横幅：聊天页开公告全文视图。
- (void)bannerStackDidTapAnnouncement:(IMChatBannerStack *)stack;
/// 点入群申请横幅：聊天页进审批列表。
- (void)bannerStackDidTapApproval:(IMChatBannerStack *)stack;
@end

@interface IMChatBannerStack : NSObject

/// 把三条横幅挂到 hostView 上，顶部贴 topAnchor（通常是安全区顶）。userID/convID 用于收起态持久化键。
/// delegate 在 init 传入并**先于任何内容 setter**绑定：内容 setter（pinnedItems/announcementText/
/// applyApprovalPending:）都以 notifyHeightChanged 收尾，若 delegate 尚未绑定，那一次顶开 tableView
/// 内边距的回调会被 nil 消息静默吞掉、首屏消息被横幅盖住直到下次横幅事件才自愈。收进 init 从结构上杜绝该顺序坑。
- (instancetype)initWithHostView:(UIView *)hostView
                       topAnchor:(NSLayoutYAxisAnchor *)topAnchor
                        delegate:(nullable id<IMChatBannerStackDelegate>)delegate
                         isGroup:(BOOL)isGroup
                          userID:(NSString *)userID
                          convID:(NSString *)convID NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak, nullable, readonly) id<IMChatBannerStackDelegate> delegate;

#pragma mark 置顶（G0）
/// 当前置顶集合（pinned_at 降序）。setter 重新应用横幅（恒显最新置顶一条，不轮转）并回调 bannerStackDidChangePinnedItems:。
@property (nonatomic, copy) NSArray<IMPinnedMessage *> *pinnedItems;
/// 置顶横幅视图。
@property (nonatomic, readonly) UIView *pinnedBannerView;

#pragma mark 公告（G1）
/// 群公告文本。setter 触发重应用（空=隐藏黄条）。
@property (nonatomic, copy, nullable) NSString *announcementText;

#pragma mark 入群申请（G3）
/// 应用待审批人数（聊天页已按「是否群主/管理员」折算，普通成员传 0）。
- (void)applyApprovalPending:(NSInteger)pending;

/// 三条横幅叠加后的总高（供聊天页设 tableView.contentInset.top）。
@property (nonatomic, readonly) CGFloat totalHeight;

@end

NS_ASSUME_NONNULL_END
