//  IMAutoDownloadCategoryViewController.h
//  自动下载「单类页」（③级，M4-7）：某网络下某类别（图片/视频/文件）的 单聊/群聊 开关 + 大小上限。
//  原生 InsetGrouped + UISwitch + UISlider，自动继承 Liquid Glass；改任一控件即 PUT 保存。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMDownloadNetworkKind) { IMDownloadNetworkCellular = 0, IMDownloadNetworkWifi = 1 };
typedef NS_ENUM(NSInteger, IMDownloadCategoryKind) { IMDownloadCategoryImage = 0, IMDownloadCategoryVideo = 1, IMDownloadCategoryFile = 2 };

/// UIViewController + 内嵌 InsetGrouped UITableView（**非 UITableViewController**，理由见网络页头注）。
@interface IMAutoDownloadCategoryViewController : UIViewController
- (instancetype)initWithNetwork:(IMDownloadNetworkKind)network category:(IMDownloadCategoryKind)category;
@end

NS_ASSUME_NONNULL_END
