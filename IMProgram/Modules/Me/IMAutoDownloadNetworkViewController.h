//  IMAutoDownloadNetworkViewController.h
//  自动下载「网络页」（②级，M4-7）：某网络（移动数据 / Wi-Fi）的 总开关 + 低/中/高 快捷档 + 图片/视频/文件入口。

#import <UIKit/UIKit.h>
#import "IMAutoDownloadCategoryViewController.h" // IMDownloadNetworkKind

NS_ASSUME_NONNULL_BEGIN

/// UIViewController + 内嵌 InsetGrouped UITableView（**非 UITableViewController**）：
/// 注入式液态标题栏是把栏加进 vc.view 的子视图，若 vc.view 就是可滚动的 tableView，栏会随内容滚走。
/// 故与 IMGroupInfoViewController 等页一致，用普通 VC 承载独立 tableView。
@interface IMAutoDownloadNetworkViewController : UIViewController
- (instancetype)initWithNetwork:(IMDownloadNetworkKind)network;
@end

NS_ASSUME_NONNULL_END
