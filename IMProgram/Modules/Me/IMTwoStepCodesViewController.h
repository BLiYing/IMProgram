//  IMTwoStepCodesViewController.h
//  开启 / 重新生成之后的「恢复码」页：10 个码两列、复制全部、保存为文件、勾选「我已保存」才能「完成」。
//  恢复码只显示这一次 → 本页关闭侧滑 + 隐藏返回键，只有「完成」（iOS 规格，设计 §5.1「返回拦截」）。

#import "IMTwoStepFormViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMTwoStepCodesViewController : IMTwoStepFormViewController
/// regenerated=YES：来自「重新生成」（完成后的 toast 不同）。恢复码只留内存，页面销毁即丢。
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
               recoveryCodes:(NSArray<NSString *> *)codes regenerated:(BOOL)regenerated;
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
