//  IMPopoverCard.h
//  兼容旧调用方的系统菜单入口：内部使用 UIKit action sheet/popover，iOS 26 自动获得 Liquid Glass。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPopoverCardItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbol;        ///< SF Symbol 名
@property (nonatomic, assign) BOOL destructive;      ///< 红色项
@property (nonatomic, copy) void (^handler)(void);
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol
                  destructive:(BOOL)destructive handler:(void (^)(void))handler;
@end

@interface IMPopoverCard : NSObject
/// 同一 host 内是否已有弹出卡片。用于避免导航栏按钮连续点击叠出多个菜单。
+ (BOOL)isPresentingInHostView:(UIView *)host;
/// 在 host 内锚定 anchor 展示系统 action sheet/popover；关闭和动画由 UIKit 管理。
+ (void)presentFromAnchor:(UIView *)anchor inHostView:(UIView *)host items:(NSArray<IMPopoverCardItem *> *)items;
/// 导航栏按钮必须使用 UIBarButtonItem 作为 iPad popover 锚点，不能把它强转成 UIView。
+ (void)presentFromBarButtonItem:(UIBarButtonItem *)barButtonItem
                      inHostView:(UIView *)host
                           items:(NSArray<IMPopoverCardItem *> *)items;
@end

NS_ASSUME_NONNULL_END
