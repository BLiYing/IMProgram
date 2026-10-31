//  IMTwoStepFormViewController.h
//  两步验证各二级页的共用骨架：InsetGrouped 表 + 底部主按钮 + 13pt 红字 + 键盘顶起（沿用 IMChangePasswordViewController 版式）。
//  取值（TWO_STEP_VERIFICATION_DESIGN §5.1）：行高 ≥44；主按钮高 50 圆角 12 systemBlue 白 17 Semibold、不可用 alpha 0.5、左右各 16；
//  红字 13pt systemRed 左右 32 距顶 6；说明 / footer 13pt secondaryLabel 左右 32。
//  push 出去的页面不用 UITableViewController（注入的液态标题栏会被系统下移一截，CODING_STYLE §9）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 一行 = 一个自带约束的内容视图（高度由内容 / 约束决定）；onTap 非空时该行可点（带系统高亮）。
@interface IMTwoStepRow : NSObject
@property (nonatomic, strong) UIView *view;
@property (nonatomic, copy, nullable) void (^onTap)(void);
@property (nonatomic, assign) BOOL showsChevron;
/// YES = 行不画卡片底（透明背景，用于“纯文字链”行，如邮箱验证码页的「重新发送 / 更换邮箱」）。
@property (nonatomic, assign) BOOL transparent;
+ (instancetype)rowWithView:(UIView *)view onTap:(nullable void (^)(void))onTap;
@end

@interface IMTwoStepSection : NSObject
@property (nonatomic, copy, nullable) NSString *header;
@property (nonatomic, copy, nullable) NSString *footer;
/// footer 文字颜色；nil = secondaryLabel（红字错误行紧贴上一组时用 systemRed）。
@property (nonatomic, strong, nullable) UIColor *footerColor;
@property (nonatomic, copy) NSArray<IMTwoStepRow *> *rows;
+ (instancetype)sectionWithRows:(NSArray<IMTwoStepRow *> *)rows footer:(nullable NSString *)footer;
@end

@interface IMTwoStepFormViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
@property (nonatomic, copy, readonly) NSString *host;
@property (nonatomic, copy, readonly) NSString *userID;
@property (nonatomic, strong, readonly) UITableView *tableView;
@property (nonatomic, strong, readonly) UIButton *primaryButton;
@property (nonatomic, strong, readonly) UILabel *errorLabel;
/// 请求在途：主按钮转圈 + 置灰；同时锁住返回键 / 侧滑（避免请求中离开丢结果——恢复码只出现一次）。
@property (nonatomic, assign) BOOL busy;

#pragma mark 子类覆写点
- (NSString *)pageTitle;
- (NSArray<IMTwoStepSection *> *)buildSections;
/// 表头内容（头图等）；默认无。
- (nullable UIView *)headerContentView;
/// 主按钮标题；nil = 不显示主按钮。
- (nullable NSString *)primaryTitle;
- (UIColor *)primaryColor;
- (BOOL)primaryEnabled;
- (void)primaryTapped;
/// YES = 整页不可返回（保存恢复码页：隐藏返回键 + 关侧滑，只有「完成」）。
- (BOOL)locksBackNavigation;
/// 是否整个流程的根页（状态 / 介绍页）；完成 / 失效后 pop 回它。
- (BOOL)isFlowRoot;

#pragma mark 给子类用
- (void)reloadSections;
- (void)refreshPrimary;
/// 主按钮点击入口（在途 / 不可用时忽略，否则转 primaryTapped）；键盘 Return 键也走它。
- (void)primaryButtonTapped;
/// 空串 / nil = 隐藏错误行。
- (void)showError:(nullable NSString *)text;
/// 给某一行内容加 / 清 1pt systemRed 错误边框（nil = 全清）。
- (void)markErrorView:(nullable UIView *)view;
/// 取一枚可用 token（缓存命中则不发请求）；失败在红字里提示。
- (void)withToken:(void (^)(NSString *token))block;
/// 同上，但取 token 失败时交给调用方（自己复位在途状态 / 决定怎么提示）。
- (void)withToken:(void (^)(NSString *token))block failure:(nullable void (^)(NSError *_Nullable error))failure;
/// 回到流程根页并在其上弹 toast（根页进入时会重新拉状态）。找不到根页就 pop 一层。
- (void)popToFlowRootWithToast:(nullable NSString *)toast;
/// 把滚动内容里主按钮滚到键盘上方可见（键盘弹起 / 输入框聚焦后调用）。
- (void)scrollPrimaryButtonIntoView;

@end

NS_ASSUME_NONNULL_END
