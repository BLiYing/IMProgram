//  IMDataStorageViewController.h
//  设置 › 数据和存储（①级主页，M4-7）：存储用量（清缓存）+ 使用移动数据 / 使用 Wi-Fi 入口 + 重置。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// UIViewController + 内嵌 InsetGrouped UITableView（**非 UITableViewController**）：
/// 注入式液态标题栏加进 vc.view 的子视图，若 vc.view 即可滚动 tableView，栏会随内容滚走。
@interface IMDataStorageViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
