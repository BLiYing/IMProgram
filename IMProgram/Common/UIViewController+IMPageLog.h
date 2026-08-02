//  UIViewController+IMPageLog.h
//  统一页面日志：全局 hook viewDidAppear:，仅打印 IM 自有页面。
//  无需任何 VC 继承基类——+load 时 swizzle 一次（Release 下静默）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 页面日志白名单。必须在读取 title/navigationItem 等控制器属性之前调用。
FOUNDATION_EXPORT BOOL IMShouldLogPageClassName(NSString *className);

@interface UIViewController (IMPageLog)
@end

NS_ASSUME_NONNULL_END
