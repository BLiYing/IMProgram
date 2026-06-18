//  IMAnimator.h
//  原生可复用动效 + 触感反馈（Telegram 风：弹性出现 / 点按回弹 / 轻触感 / 选择切换）。
//  统一封装，避免各页面散写 spring 参数与 feedback generator。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAnimator : NSObject

/// 出现时缩放 0.8→1 的弹性动画（如吐司）。
+ (void)springPopIn:(UIView *)view;

/// 点按回弹：快速缩小再弹回（行/按钮点击反馈）。
+ (void)tapBounce:(UIView *)view;

/// 轻量触感（菜单动作触发时）。
+ (void)lightImpact;

/// 选择切换触感（设置行点击 / 列表选择时）。
+ (void)selectionChanged;

@end

NS_ASSUME_NONNULL_END
