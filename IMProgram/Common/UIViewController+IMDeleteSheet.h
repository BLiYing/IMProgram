//  UIViewController+IMDeleteSheet.h
//  两档删除确认 sheet（聊天页/详情页媒体查看器「更多」共用）：IMPopoverCard 为扁平列表，两档用 action sheet 承载。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (IMDeleteSheet)

/// 弹「仅删除自己 / 为所有人删除 / 取消」action sheet，从 self 弹出（调用方选好可见宿主再调）；
/// iPad popover 锚点兜底为 view 居中。调用方自行先判权限——不可全员删时不应走到这里。
- (void)im_presentDeleteChoiceSheetWithSelfOnly:(void (^)(void))selfOnly
                                       everyone:(void (^)(void))everyone;

@end

NS_ASSUME_NONNULL_END
