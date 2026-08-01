//  IMBottomSheet.h
//  可复用系统 action sheet 操作面板。
//  用于媒体查看器「更多」等场景；实现统一转交 UIKit action sheet，iOS 26 自动使用 Liquid Glass。

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

/// 在 host 视图上展示系统面板；点任一项或取消后由 UIKit 负责消失（选项另触发其 handler）。
+ (void)showInView:(UIView *)host items:(NSArray<IMBottomSheetItem *> *)items;

@end

NS_ASSUME_NONNULL_END
