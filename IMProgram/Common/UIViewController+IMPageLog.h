//  UIViewController+IMPageLog.h
//  统一页面日志：全局 hook viewDidAppear:，页面出现时打印当前控制器。
//  无需任何 VC 继承基类——+load 时 swizzle 一次，所有页面自动打点（Release 下静默）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (IMPageLog)
@end

NS_ASSUME_NONNULL_END
