//  IMPopoverCard.h
//  自绘弹出卡片（替代原生 UIMenu 的位置不可控问题）：锚在按钮**正下方右对齐**、上→下 spring 弹出、
//  圆角用 continuous 与全局一致、点卡外/点项均关闭。会话详情「更多」与会话列表「+」共用。

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
/// 在 host 内、锚定 anchor 下方弹出卡片。视图层级自持有，关闭即释放。
+ (void)presentFromAnchor:(UIView *)anchor inHostView:(UIView *)host items:(NSArray<IMPopoverCardItem *> *)items;
@end

NS_ASSUME_NONNULL_END
