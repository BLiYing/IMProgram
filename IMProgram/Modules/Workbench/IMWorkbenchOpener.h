//  IMWorkbenchOpener.h
//  打开工作台应用 / 轮播链接（WORKBENCH_DESIGN §3.2）：工作台首页、应用商店、轮播图三处共用。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMWorkbenchOpener : NSObject

/// 打开应用：向服务端要打开地址（带一次性票据）→ 校验地址 → 内置浏览器打开。
/// 失败不打开、toast；应用已下架（400141）时另调 onUnavailable（调用方据此重拉工作台）。
+ (void)openAppID:(NSString *)appID name:(NSString *)name unitID:(NSString *)unitID
             from:(UIViewController *)host onUnavailable:(nullable void (^)(void))onUnavailable;

/// 打开轮播图的链接：只开 https / 本机内网 http，不合规的不响应。
+ (void)openLink:(NSString *)link from:(UIViewController *)host;

@end

NS_ASSUME_NONNULL_END
