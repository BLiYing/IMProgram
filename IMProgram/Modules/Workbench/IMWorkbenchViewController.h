//  IMWorkbenchViewController.h
//  底部 Tab「工作台」（WORKBENCH_DESIGN §3，交互稿 I-1 / I-2 / I-4 / I-6）：轮播 + 按分组的「我的应用」宫格；
//  标题右侧「应用商店」；客户绑了多家公司时点标题切换（选择记本机，按用户）。进入 / 下拉 / 切换公司时拉一次。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMWorkbenchViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)c NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
