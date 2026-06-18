//  UIViewController+IMToast.h
//  轻量吐司：底部居中圆角胶囊，弹性淡入淡出（~1.6s）。未实现的功能统一用 im_showComingSoon:。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (IMToast)

/// 短暂提示（底部居中，自动消失）。
- (void)im_showToast:(NSString *)text;

/// "<标题>（开发中）"——后端未就绪的功能统一走这里。
- (void)im_showComingSoon:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
