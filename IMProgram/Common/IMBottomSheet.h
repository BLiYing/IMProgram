//  IMBottomSheet.h
//  可复用底部操作面板（图文按钮 + 取消 + 蒙层 + 点空白消失）。
//  用于媒体查看器「更多」等场景；UIAlertController 只有纯文本行，故自绘（不引第三方）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 面板中的一项：SF Symbol 图标 + 标题 + 点击回调。
@interface IMBottomSheetItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbol;   ///< SF Symbol 名
@property (nonatomic, copy) dispatch_block_t handler;
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(dispatch_block_t)handler;
@end

@interface IMBottomSheet : NSObject

/// 在 host 视图上展示面板：半透明蒙层 + 底部白板（图文按钮横排、可换行）+「取消」。
/// 点任一项/取消/空白 → 面板消失（选项另触发其 handler）。
+ (void)showInView:(UIView *)host items:(NSArray<IMBottomSheetItem *> *)items;

@end

NS_ASSUME_NONNULL_END
