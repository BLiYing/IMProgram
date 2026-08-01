//  IMPopoverCard.h
//  Telegram 式锚点上下文菜单：磨砂圆角卡片、图标、分隔线与危险操作语义。

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
/// 在 host 内锚定 anchor 展示 Telegram 式上下文菜单。
+ (void)presentFromAnchor:(UIView *)anchor inHostView:(UIView *)host items:(NSArray<IMPopoverCardItem *> *)items;
/// 导航栏按钮入口；使用导航栏右上按钮的屏幕位置作为锚点。
+ (void)presentFromBarButtonItem:(UIBarButtonItem *)barButtonItem
                      inHostView:(UIView *)host
                           items:(NSArray<IMPopoverCardItem *> *)items;
@end

NS_ASSUME_NONNULL_END
