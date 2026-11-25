//  IMAppStoreViewController.h
//  应用商店（WORKBENCH_DESIGN §3.2，交互稿 I-3）：这家公司上架且启用的全部应用，按分组分段；
//  每行「添加」/「已添加」（乐观更新，失败回滚 + toast）；点行本身 = 打开应用。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 不用 UITableViewController：其根视图就是表格，统一液态标题栏注入到页面 view 后会随表格滚动、布局错位（2026-11-25 实测）。
@interface IMAppStoreViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host unitID:(NSString *)unitID;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)c NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
