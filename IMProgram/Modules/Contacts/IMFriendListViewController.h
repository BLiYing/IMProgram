//  IMFriendListViewController.h
//  「我的好友」页（通讯录首页入口行 push）：好友 A–Z 分组 + 右侧索引 + 左滑删除 / 拉黑，点行进资料页。
//
//  2026-11-13 通讯录首页改版（../IMServer/docs/design/ORG_DIRECTORY_DESIGN.md §7）：好友列表原先直接铺在
//  通讯录首页入口行下面，整体搬到本页；首页只留入口行 + 「最近联系」。本页自己拉好友并监听好友事件 /
//  本机好友关系变更 / 备注变更。

#import <UIKit/UIKit.h>

@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

@interface IMFriendListViewController : UIViewController

/// seedFriends：首屏用的好友名单（通讯录首页手上已有的 accepted，免得 push 时在主线程再读整张好友表）；
/// 传 nil 时读本地好友快照打底。之后照常拉权威名单覆盖。
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                 seedFriends:(nullable NSArray<IMUserCard *> *)seedFriends;

@end

NS_ASSUME_NONNULL_END
