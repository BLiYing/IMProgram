//  IMGroupBanListViewController.h
//  群黑名单页（G2）：列出被移出并永久/冷却拉黑的成员，滑动可解除。仅群主/管理员可达。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 用普通 UIViewController + UITableView（**不用 UITableViewController**）：被 push 时容器注入的
// 液态标题栏会因 UITableViewController 自管 scrollView 内边距而下移错位（见 UITableViewController-注入栏下移）。
@interface IMGroupBanListViewController : UIViewController

- (instancetype)initWithConvID:(NSString *)convID;

@end

NS_ASSUME_NONNULL_END
