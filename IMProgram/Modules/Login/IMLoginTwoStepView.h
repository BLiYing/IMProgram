//  IMLoginTwoStepView.h
//  登录二步页（同一个登录页内切换，不新开页面）：6 位动态码（输满自动提交）/ 恢复码（文本框 + 登录按钮），
//  文字链互相切换，「返回」丢弃 ticket 回密码页。规则全部来自 Common/IMTwoStep（纯函数）。
//  取值（TWO_STEP_VERIFICATION_DESIGN §5.1）：与登录页同一个 UIStackView（间距 12、左右 24、字段高 44）；
//  6 位框 28pt 等宽 Semibold 字距 8 居中，数字键盘 + oneTimeCode；恢复码框关闭自动大写 / 纠正 / 拼写检查。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMLoginTwoStepView : UIView

/// 提交：code 已清洗（动态码）/ 已归一化（恢复码）。
@property (nonatomic, copy, nullable) void (^onSubmit)(NSString *code, BOOL recovery);
@property (nonatomic, copy, nullable) void (^onBack)(void);
/// 请求在途：输入框 / 按钮禁用（防重复提交），按钮转圈；在途时「返回」也禁用（避免丢掉已成功的登录）。
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign, readonly) BOOL recoveryMode;
@property (nonatomic, strong, readonly) UITextField *codeField;
@property (nonatomic, strong, readonly) UITextField *recoveryField;
@property (nonatomic, strong, readonly) UIButton *submitButton;

/// 空串 / nil = 隐藏。
- (void)showError:(nullable NSString *)message;
/// 回到「动态码」模式并清空所有输入（新 ticket 进入时用）。
- (void)resetForNewTicket;
/// 清空 6 位框并重新聚焦（错码后）。
- (void)clearCodeAndRefocus;
- (void)focusInput;

@end

NS_ASSUME_NONNULL_END
