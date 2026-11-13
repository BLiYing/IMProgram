//  IMLoginViewController+Private.h
//  登录页的共享内部接口：类扩展（存储属性）+ 分文件 category 的方法登记（CODING_STYLE §7 ②）。
//  - IMLoginViewController.m：布局、页签 / 模式、密码登录 / 用户名注册 / 免密、两步验证、子页切换、键盘。
//  - IMLoginViewController+Phone.m：public-config、验证码登录即注册、完善资料、忘记密码、冷静期凭票恢复（PHONE_AUTH_DESIGN §4 §5 §7.3）。
//  - IMLoginViewController+Endpoint.m：长按 Logo 改地址、底部《服务条款》《隐私政策》链接。
//  **存储属性一律放类扩展 `()`，别写进 category `(Xxx)`**（CODING_STYLE §3）。

#import "IMLoginViewController.h"
#import "IMPhoneAuth.h"

@class IMLoginTwoStepView, IMPublicConfig, IMLoginPhoneFields, IMLoginCompleteProfileView, IMLoginResetPasswordView;

NS_ASSUME_NONNULL_BEGIN

/// 整列距安全区顶部的静止间距；键盘顶起时在此基础上减去上移量。
FOUNDATION_EXPORT CGFloat const kIMLoginStackTop;
FOUNDATION_EXPORT NSString * const kIMLastHostKey;

@interface IMLoginViewController () <UITextViewDelegate>
/// 当前服务器地址（可带协议）。只读显示在登录按钮下方，改它走长按 Logo 的配置弹窗。
@property (nonatomic, copy) NSString *hostInput;
@property (nonatomic, strong) UITextField *userIDField;   ///< 密码登录：用户名 / 邮箱 / 手机号；用户名注册：用户名
@property (nonatomic, strong) UITextField *nicknameField; ///< 昵称（显示名，仅用户名注册时用；必填）
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UILabel *errorLabel;
/// 登录入口提成属性：请求在途时要把被点的那个转成菊花、其余禁用（见 setBusy:activeButton:）。
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIButton *registerButton;
@property (nonatomic, strong) UIButton *devButton;
@property (nonatomic, strong) UIButton *smsLoginButton;
@property (nonatomic, assign) BOOL submitting;
// 页签：「验证码登录 / 密码登录」；只有一个页签时不画页签条。原「注册」页签改成底部链接「用户名注册」。
@property (nonatomic, strong) UIStackView *tabsRow;
@property (nonatomic, strong) UIButton *smsTabButton;
@property (nonatomic, strong) UIButton *passwordTabButton;
@property (nonatomic, assign) IMLoginTab tab;
/// 用户已动过（点过页签 / 开始输入）：public-config 晚到时不再切页签。
@property (nonatomic, assign) BOOL touched;
@property (nonatomic, strong) IMLoginPhoneFields *smsFields;
@property (nonatomic, strong) UILabel *autoRegisterHintLabel;
@property (nonatomic, strong) UIStackView *linksRow;
@property (nonatomic, strong) UIButton *forgotButton;
@property (nonatomic, strong) UIButton *usernameRegisterButton;
@property (nonatomic, strong) UIButton *backToLoginButton;
@property (nonatomic, strong) UILabel *registerHintLabel;
@property (nonatomic, strong) UILabel *serverLabel;
@property (nonatomic, assign) BOOL registerMode;
@property (nonatomic, strong) UIStackView *mainStack;
// 子页（同页切换，不新开页面）：两步验证 / 完善资料 / 重设密码。ticket 只留内存，离开子页即丢弃。
@property (nonatomic, strong) IMLoginTwoStepView *twoStepView;
@property (nonatomic, strong) IMLoginCompleteProfileView *completeView;
@property (nonatomic, strong) IMLoginResetPasswordView *resetView;
@property (nonatomic, weak, nullable) UIView *currentSubpage;
@property (nonatomic, copy) NSArray<UIView *> *viewsHiddenForSubpage; ///< 进子页前可见的控件，返回时原样恢复
@property (nonatomic, copy, nullable) NSString *twoStepTicket;
@property (nonatomic, copy) NSString *twoStepHost;
@property (nonatomic, assign) IMLoginTab twoStepTab; ///< 二步页是从哪个页签进来的（成功后记住它）
@property (nonatomic, copy, nullable) NSString *registerTicket; ///< 完善资料凭证（只在内存）
@property (nonatomic, copy, nullable) NSString *registerHost;
@property (nonatomic, strong) NSLayoutConstraint *stackTopConstraint;
/// 最近一次键盘上沿（登录页坐标）；0 = 还没收到过键盘通知，按键盘未弹出处理。
@property (nonatomic, assign) CGFloat keyboardTop;
/// 底部「继续即表示同意《服务条款》和《隐私政策》」：隐式同意（无勾选框），两段链接走应用内浏览器（ABOUT_LEGAL_DESIGN 批②）。
@property (nonatomic, strong) UITextView *agreeFooter;
/// public-config（S4 注册开关 + 短信）：拉取器自带「只认最新一次请求」。
@property (nonatomic, strong) IMPublicConfig *publicConfig;
@property (nonatomic, strong, nullable) IMLoginConfig *loginConfig; ///< nil = 还没取到（按老服务端口径）
@property (nonatomic, copy, nullable) NSString *configHost;         ///< loginConfig 来自哪个地址（换服务器才重置国家码）
@property (nonatomic, strong) UILabel *registerClosedLabel; ///< 注册页内联提示「管理员已暂停注册新账号」
@property (nonatomic, assign) BOOL registerClosed;          ///< YES = 禁用注册提交；拉不到按 NO（服务端 200007 兜底）
@end

@interface IMLoginViewController (Private)
- (void)applyMode;
- (void)showError:(NSString *)message;
- (void)showNotice:(NSString *)message;
- (NSString *)trimmed:(NSString *)text;
/// 解析当前服务器地址并写入全局协议；非法时已显示错误并返回空串。
- (NSString *)resolvedHostOrShowError;
- (void)prepareServiceWithHost:(NSString *)host password:(NSString *)password;
- (void)setBusy:(BOOL)busy activeButton:(nullable UIButton *)activeButton;
/// 登录成功进主界面。username = 服务端给的公开用户名（不可信时存空并事后校正）；rememberTab = IMLoginTabNone 不记页签（用户名注册 / 静默恢复）。
- (void)enterAppWithHost:(NSString *)host userID:(NSString *)userID username:(nullable NSString *)username rememberTab:(IMLoginTab)rememberTab;
- (void)registerTabTapped;
/// 「恢复账号」确认框（冷静期账号登录）：确认回调 onConfirm。
- (void)presentRestoreConfirmWithDeleteAt:(nullable NSDate *)deleteAt onConfirm:(void (^)(void))onConfirm;
- (void)fieldDidBeginEditing:(UITextField *)field;
- (void)enterSubpage:(UIView *)page;
- (void)leaveSubpage;
- (void)beginTwoStepWithTicket:(NSString *)ticket host:(NSString *)host tab:(NSInteger)tab;
- (UIButton *)buttonTitle:(NSString *)title config:(UIButtonConfiguration *)config action:(SEL)action;
- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text keyboard:(UIKeyboardType)keyboard secure:(BOOL)secure;
@end

@interface IMLoginViewController (Phone)
- (void)setupPhoneViews;
/// 用当前服务器地址重读 public-config（打开页面 / 改服务器地址时）。hostChanged=YES 时重置国家码。
- (void)reloadLoginConfigHostChanged:(BOOL)hostChanged;
/// 提交注册回 200007 后：重拉整份配置（取代在途的那次），结果回来照常落下，但注册仍标记关闭。
- (void)reloadLoginConfigAfterRegisterClosed;
- (void)applyRegisterClosed:(BOOL)closed;
- (void)smsLoginTapped;
- (void)forgotPasswordTapped;
@end

@interface IMLoginViewController (Endpoint)
- (UITextView *)buildAgreeFooter;
- (void)logoLongPressed:(UILongPressGestureRecognizer *)gesture;
- (void)refreshServerLabel;
- (NSString *)builtinHost;
- (NSString *)defaultHost;
- (void)saveEndpointHost:(NSString *)rawHost rtc:(NSString *)rawRTC;
@end

NS_ASSUME_NONNULL_END
