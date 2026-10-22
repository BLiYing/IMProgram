//  IMActionListSheet.h
//  自绘底部弹层列表（标题 + 居中选项 + 取消行），对齐 Android `ActionSheet`。
//
//  为什么不用 UIAlertController(ActionSheet)：系统菜单在 iOS 26（悬浮玻璃）与 iOS 18（分组卡片）
//  外观不同，同一页面在两个系统上长得不一样，也和 Android 对不齐；自绘一份三处同形（免打扰时长菜单先用）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMActionListItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL destructive;   ///< 红字
@property (nonatomic, assign) BOOL selected;      ///< 行尾打 ✓（单选列表，如自动删除自定义时间）；默认 NO
@property (nonatomic, copy) void (^handler)(void);
+ (instancetype)itemWithTitle:(NSString *)title destructive:(BOOL)destructive handler:(void (^)(void))handler;
+ (instancetype)itemWithTitle:(NSString *)title selected:(BOOL)selected handler:(void (^)(void))handler;
@end

@interface IMActionListSheet : UIViewController

/// 选项区高度超过屏高 60% 时在卡片内滚动（标题与「取消」行固定），首次出现滚到 ✓ 行。
/// 从 host 弹出。点遮罩 / 「取消」收起且不回调；点选项先收起再回调（避免回调里再 present 撞上转场）。
+ (void)presentFrom:(UIViewController *)host title:(nullable NSString *)title items:(NSArray<IMActionListItem *> *)items;

@end

NS_ASSUME_NONNULL_END
