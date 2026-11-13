//  IMContactsViewController.h
//  通讯录 Tab 首页：页顶搜索入口 + 入口行（群聊 / 新的朋友 / 我的好友）+ 「最近联系」（最近 5 个单聊，点行进聊天）。
//  右上角 + 进找人页。好友 A–Z 列表在 IMFriendListViewController（「我的好友」入口）；
//  本页仍负责拉好友名单：入口行的好友数、「新的朋友」徽标与 Tab 角标都靠它。
//  设计：../IMServer/docs/design/ORG_DIRECTORY_DESIGN.md §7。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 切入通讯录时是否要拉权威好友列表（节流判据，纯函数便于单测）。
/// 从未拉成功过（lastRefreshAt<=0）必拉——本地好友缓存只由通讯录首页与「我的好友」页写入，不拉就永远是空的；
/// 已有请求在途不重复发；距上次成功不足 interval 秒不拉；now 早于 lastRefreshAt（时钟异常）按过期处理，别卡死。
/// 好友事件 / 重连 / 本机增删拉黑触发的刷新不走这道节流。「我的好友」页复用同一判据。
extern BOOL IMContactsShouldRefreshOnAppear(BOOL inFlight, CFTimeInterval lastRefreshAt,
                                            CFTimeInterval now, CFTimeInterval interval);

@interface IMContactsViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
