//  IMDeviceListViewController.h
//  已登录设备（多设备管理，QR P2，sketch §02）：设置「已登录设备」行 push 进来。
//  以登录会话(session)为行：本机置顶标「当前」，其余点进详情可逐台退出；底部「退出其他所有设备」。
//  纯 UIViewController + UITableView（不用 UITableViewController，否则容器注入的液态标题栏会错位）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMDeviceListViewController : UIViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
@end

NS_ASSUME_NONNULL_END
