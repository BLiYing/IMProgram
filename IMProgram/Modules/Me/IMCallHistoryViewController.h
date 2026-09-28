//  IMCallHistoryViewController.h
//  设置 ▸ 最近通话：只读通话历史列表（设计：IMServer docs/design/CALL_HISTORY_DESIGN.md / 配套 UX 稿）。
//  数据来自 im-rtc SDK `fetchCallHistory`（经 IMRtcCall 桥接），不经过 IMServer。
//  按日期分组倒序展示；顶部「全部/未接」分段（v1 端上过滤）；上拉自动翻页；`callEnd` 事件触发重拉首页；
//  点单聊行按原类型直接回拨；点群聊行跳转群会话。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMCallHistoryViewController : UIViewController

/// 与本工程其它「我」页二级列表（IMDeviceListViewController 等）同一签名：host 用于跳群聊会话，
/// userID 既是导航参数也是「我的 uid」（未接判定 / 身份解析的 selfUID）。
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
