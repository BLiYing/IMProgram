//  IMGroupAdminListViewController.h
//  群管理页 →「管理员」二级页：群主（只读一行）+ 管理员列表（左滑撤销）+「添加管理员」（仅群主）。
//  在此之前，全仓没有任何一处能回答"这个群现在有几个管理员、分别是谁"——只能滚成员列表数徽标。
//  设计见 IMServer/docs/design/GROUP_ADMIN_TRANSFER_DESIGN.md §3.2 / §3.3。

#import <UIKit/UIKit.h>

@class IMGroupInfo;

NS_ASSUME_NONNULL_BEGIN

// 用普通 UIViewController + UITableView（**不用 UITableViewController**）：被 push 时容器注入的
// 液态标题栏会因 UITableViewController 自管 scrollView 内边距而下移错位。
@interface IMGroupAdminListViewController : UIViewController

/// group：群资料快照（成员表 + my_role，本页据此判定显隐）。本页每次出现都会自己重拉一遍。
/// onChanged：角色变更成功后回调，上一页据此刷新计数。
- (instancetype)initWithHost:(NSString *)host
                      userID:(NSString *)userID
                      convID:(NSString *)convID
                       group:(IMGroupInfo *)group
                   onChanged:(nullable void (^)(void))onChanged;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
