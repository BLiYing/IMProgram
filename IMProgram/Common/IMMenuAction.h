//  IMMenuAction.h
//  数据驱动的菜单动作模型：一个动作 = 一条 IMMenuAction，渲染层（UIMenu / UISwipeAction）
//  统一从 NSArray<IMMenuAction *> 生成。新增菜单项 = 往数组里 append 一条，不改渲染代码。
//  与 Web 端 menu registry 对齐（actionId 为两端共用标识）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMenuAction : NSObject

@property (nonatomic, copy)   NSString *actionId;                  ///< 稳定标识，跨端对齐用
@property (nonatomic, copy)   NSString *title;                     ///< 显示文案
@property (nonatomic, copy, nullable) NSString *systemImageName;   ///< SF Symbol 名（可空）
@property (nonatomic, assign) BOOL destructive;                    ///< 破坏性（红色）
@property (nonatomic, copy, nullable) void (^handler)(void);       ///< 触发回调

/// 普通动作。
+ (instancetype)actionWithId:(NSString *)actionId
                       title:(NSString *)title
                       image:(nullable NSString *)systemImageName
                     handler:(nullable void (^)(void))handler;

/// 破坏性动作（destructive=YES）。
+ (instancetype)destructiveActionWithId:(NSString *)actionId
                                  title:(NSString *)title
                                  image:(nullable NSString *)systemImageName
                                handler:(nullable void (^)(void))handler;

/// 一组动作 → UIMenu（每条 → UIAction：图标 / 破坏性 / handler）。调用方只传"可见"的动作。
+ (UIMenu *)menuWithActions:(NSArray<IMMenuAction *> *)actions;

@end

NS_ASSUME_NONNULL_END
