//  UIViewController+IMToast.h
//  轻量吐司：底部居中圆角胶囊，弹性淡入淡出（~1.6s）。未实现的功能统一用 im_showComingSoon:。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 吐司去重（纯函数）：与上一次（*lastText / *lastAt）同一句且相隔不足 window 秒 → NO（不弹）；
/// 否则 YES 并把本次记进 *lastText / *lastAt。用途：一批作业同时失败（如进聊天页自动续传多条、上传已被暂停）
/// 时只弹一次。window 取短（≈1 秒）：用户自己点重试的间隔通常更长，不会被吞掉。
FOUNDATION_EXPORT BOOL IMToastDedup(NSString *text, CFTimeInterval now, NSString *__strong _Nullable *_Nonnull lastText,
                                    CFTimeInterval *lastAt, CFTimeInterval window);

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
