//  IMDangerPageViewController.h
//  危险操作二级页的共用版式（警示头 + 后果卡 + 可插视图 + 错误行 + 红按钮）。
//  「注销账号」与「清除所有对话」共用，不复制分叉（CLEAR_ALL_CONVERSATIONS_DESIGN §2「复用组件」）。
//  取值（DELETE_ACCOUNT_DESIGN §3 草图）：警示圆 64pt systemRed 12% 底 + 30pt 三角图标；标题 20pt Semibold；
//  后果行 15pt、行间 8、卡片内边距 16、圆角 12；信息条 13pt accent / accentSoft 底 / 圆角 12 / 内边距 12；
//  错误行 13pt systemRed；红按钮高 50、圆角 12、17pt Semibold 白字，置灰 40% 透明。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMDangerPageViewController : UIViewController

@property (nonatomic, strong, readonly) UIScrollView *scrollView;
@property (nonatomic, strong, readonly) UIView *consequenceCard;
@property (nonatomic, strong, readonly) UILabel *errorLabel;
@property (nonatomic, strong, readonly) UIButton *submitButton;
/// 请求在途：按钮转圈并置灰。
@property (nonatomic, assign) BOOL busy;

#pragma mark 子类覆写点（viewDidLoad 时各取一次）
- (NSString *)dangerHeaderText;
- (NSArray<NSString *> *)dangerConsequenceTexts;
- (NSString *)dangerSubmitTitle;
- (nullable NSString *)dangerSubmitIdentifier;
/// 警示标题与后果卡之间的视图（默认无）。
- (NSArray<UIView *> *)dangerViewsAboveConsequences;
/// 后果卡与错误行之间的视图（默认无）。
- (NSArray<UIView *> *)dangerViewsBelowConsequences;
/// 红按钮是否可点（默认 !busy）。
- (BOOL)dangerSubmitEnabled;
/// 红按钮点击（默认空）。
- (void)dangerSubmitTapped;

#pragma mark 给子类用
- (UIView *)dangerInfoTipWithText:(NSString *)text;
- (void)pin:(UIView *)child into:(UIView *)parent inset:(CGFloat)inset;
- (void)refreshSubmitEnabled;
/// 空串 = 隐藏错误行。
- (void)showError:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
