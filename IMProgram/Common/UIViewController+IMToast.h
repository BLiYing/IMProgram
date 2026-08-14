//  UIViewController+IMToast.h
//  轻量吐司：底部居中圆角胶囊，弹性淡入淡出（~1.6s）。未实现的功能统一用 im_showComingSoon:。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (IMToast)

/// 短暂提示（底部居中，自动消失）。
- (void)im_showToast:(NSString *)text;

/// 在**当前可见的顶层控制器**上弹提示——用于"接收者可能不在屏上"的通知（如异步入群审批结果），
/// 避免把 toast 挂到被覆盖的后台 VC 上导致用户看不见。
+ (void)im_showGlobalToast:(NSString *)text;

/// 当前可见的顶层控制器（从前台 key window 钻透 presented / nav / tab）。
/// present/弹层必须挂**可见**宿主时用——挂到被覆盖的 VC 上会被 UIKit 以
/// "view is not in the window hierarchy" 静默拒绝（曾致查看器路径删除/转发无反应）。
+ (nullable UIViewController *)im_topVisibleViewController;

/// "<标题>（开发中）"——后端未就绪的功能统一走这里。
- (void)im_showComingSoon:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
