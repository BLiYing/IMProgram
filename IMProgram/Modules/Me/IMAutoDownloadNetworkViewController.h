//  IMAutoDownloadNetworkViewController.h
//  自动下载「网络页」（②级，M4-7）：某网络（移动数据 / Wi-Fi）的 总开关 + 低/中/高 快捷档 + 图片/视频/文件入口。

#import <UIKit/UIKit.h>
#import "IMAutoDownloadCategoryViewController.h" // IMDownloadNetworkKind

NS_ASSUME_NONNULL_BEGIN

@interface IMAutoDownloadNetworkViewController : UITableViewController
- (instancetype)initWithNetwork:(IMDownloadNetworkKind)network;
@end

NS_ASSUME_NONNULL_END
