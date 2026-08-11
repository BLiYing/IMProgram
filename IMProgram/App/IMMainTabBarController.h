//  IMMainTabBarController.h
//  登录后的主界面骨架：底部 Tab（会话 / 我）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMainTabBarController : UITabBarController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

/// 液态标题栏在状态栏之下占用的高度。三处必须同值：容器据此撑大被注入页的顶部安全区、
/// 容器传给栏用于还原真实状态栏高度、自持栏页面（详情/「我」）的栏底约束。
FOUNDATION_EXPORT CGFloat const kIMLiquidBarHeight;

@interface UIViewController (IMNavigationBar)

/// 请求刷新本页的液态标题栏（标题/副标题/左右按钮及其启用态）。
///
/// 标题栏由导航容器按本页 `navigationItem` 渲染，而 `navigationItem` 的改动不会自动通知容器——
/// 页面在**改完 title / 左右 barButtonItem / 其 enabled 后**必须调一次本方法，否则栏上仍是旧内容
/// （典型症状：异步回调里装的按钮永远不出现、置灰后重新启用的按钮永远点不动）。
///
/// 取代此前「`[self.navigationController.view setNeedsLayout]` 顺带触发同步」的隐式写法：
/// 那个写法在转场进行中会被布局早退吞掉，且完全看不出意图。本方法直接同步、不依赖布局时机。
/// 页面不在 `IMMainNavigationController` 内（如被普通 UINavigationController present）时安全空转。
- (void)im_refreshNavigationBar;

/// 任务2：设置本页返回按钮上的全局未读总数徽标（0 或返回键隐藏时不显示）。非注入栏页面安全空转。
- (void)im_setBackBadgeCount:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END
