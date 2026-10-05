//  IMSettingsRouter.h
//  设置项搜索命中后的「按路径逐级建页」：把 IMSettingsSearchEntry.route 里的页面 id 变成真实 VC 栈
//  （等同用户从「我」页一级一级手点进去）。页面 id 清单与 IMSettingsSearchRegistry 一一对应。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSettingsRouter : NSObject

/// 页面 id 是否被识别（登记表与路由表漂移的护栏，单测用）。
+ (BOOL)canBuildPageID:(NSString *)pageID;

/// 按 route 逐级建页，返回 push 序列（不含「我」页本身）。含无法建成页面的 id（如纯动作 shareMyCard）或未知 id 时返回 nil。
+ (nullable NSArray<UIViewController *> *)viewControllersForRoute:(NSArray<NSString *> *)route
                                                             host:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
