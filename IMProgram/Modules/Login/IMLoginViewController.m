//  IMLoginViewController.m

#import "IMLoginViewController+Private.h"
#import "IMLocalization.h"
#import "IMMainTabBarController.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Phone.h"
#import "IMSessionStore.h"
#import "IMServerEndpoint.h"
#import "IMHTTPService+Account.h"
#import "IMHTTPService+TwoStep.h"
#import "IMLoginTwoStepView.h"
#import "IMLoginPhoneFields.h"
#import "IMLoginSubpageViews.h"
#import "IMPublicConfig.h"
#import "IMTwoStep.h"
#import "IMLog.h"
#import "IMTheme.h"

NSString * const kIMLastHostKey = @"im_last_host"; // 记住上次用过的 host
CGFloat const kIMLoginStackTop = 32;
/// 输入框下沿与键盘上沿之间留的空隙。
static const CGFloat kIMLoginKeyboardGap = 12;

CGFloat IMLoginKeyboardLift(CGFloat fieldBottom, CGFloat keyboardTop) {
    return MAX(0, fieldBottom - (keyboardTop - kIMLoginKeyboardGap));
}

@implementation IMLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self setupUI];
    if (self.initialNotice.length > 0) { [self showNotice:self.initialNotice]; }
    [self reloadLoginConfigHostChanged:NO];
}

- (void)setupUI {
    self.hostInput = [self defaultHost];
    // 登录名原样传给 /login（用户名 / 邮箱 / 手机号），不预检；规范化在服务端。注册页签复用它当用户名框。
    self.userIDField   = [self fieldWithPlaceholder:IMLocalized(@"login.ident.placeholder") text:@"" keyboard:UIKeyboardTypeASCIICapable secure:NO];
    self.userIDField.accessibilityIdentifier = @"login.ident";
    // 昵称是显示名（可中文/emoji），与用户名是两回事；仅「用户名注册」用得到。
    self.nicknameField = [self fieldWithPlaceholder:IMLocalized(@"login.nickname.placeholder") text:@"" keyboard:UIKeyboardTypeDefault secure:NO];
    self.passwordField = [self fieldWithPlaceholder:IMLocalized(@"login.password.placeholder") text:@"" keyboard:UIKeyboardTypeDefault secure:YES];
    self.passwordField.accessibilityIdentifier = @"login.password";

    self.errorLabel = [self label:13 color:UIColor.systemRedColor];
    self.errorLabel.hidden = YES;
    self.errorLabel.accessibilityIdentifier = @"login.error";
    self.registerHintLabel = [self label:13 color:UIColor.tertiaryLabelColor];
    self.registerHintLabel.text = IMLocalized(@"login.register_format_hint");
    self.registerClosedLabel = [self label:13 color:IMTheme.danger];
    self.registerClosedLabel.text = IMLocalized(@"err.200007");
    self.registerClosedLabel.accessibilityIdentifier = @"login.register_closed";
    self.registerClosedLabel.hidden = YES;

    self.loginButton = [self buttonTitle:IMLocalized(@"login.button.login") config:[UIButtonConfiguration filledButtonConfiguration] action:@selector(loginTapped)];
    self.loginButton.accessibilityIdentifier = @"login.submit_password";
    self.registerButton = [self buttonTitle:IMLocalized(@"login.button.register") config:[UIButtonConfiguration filledButtonConfiguration] action:@selector(registerTapped)];
    self.registerButton.accessibilityIdentifier = @"login.submit_register";
    self.devButton = [self buttonTitle:IMLocalized(@"login.dev_login") config:[UIButtonConfiguration tintedButtonConfiguration] action:@selector(devLoginTapped)];
    self.devButton.accessibilityIdentifier = @"login.dev";
#ifndef DEBUG
    self.devButton.hidden = YES; // 仅 Debug 包显示免密入口（Android 同口径：release 不显示）
#endif
    self.backToLoginButton = [self linkButton:IMLocalized(@"login.back_to_login") action:@selector(backToLoginTapped)];
    self.backToLoginButton.accessibilityIdentifier = @"login.back_to_login";

    self.serverLabel = [self label:13 color:UIColor.secondaryLabelColor];
    self.serverLabel.textAlignment = NSTextAlignmentCenter;
    self.serverLabel.accessibilityIdentifier = @"login.server_label";
    [self refreshServerLabel];
    self.agreeFooter = [self buildAgreeFooter];

    self.smsTabButton = [self buttonTitle:IMLocalized(@"login.tab_sms") config:[UIButtonConfiguration plainButtonConfiguration] action:@selector(smsTabTapped)];
    self.smsTabButton.accessibilityIdentifier = @"login.tab_sms";
    self.passwordTabButton = [self buttonTitle:IMLocalized(@"login.tab_password") config:[UIButtonConfiguration plainButtonConfiguration] action:@selector(passwordTabTapped)];
    self.passwordTabButton.accessibilityIdentifier = @"login.tab_password";
    self.tabsRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.smsTabButton, self.passwordTabButton]];
    self.tabsRow.distribution = UIStackViewDistributionFillEqually;
    self.tabsRow.spacing = 8;
    [self setupPhoneViews]; // 验证码表单 / 自动注册提示 / 忘记密码与用户名注册链接（+Phone）

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self logoView], [self titleLabelView], self.tabsRow, self.smsFields,
        self.userIDField, self.passwordField, self.nicknameField, self.registerHintLabel, self.registerClosedLabel, self.errorLabel,
        self.smsLoginButton, self.loginButton, self.registerButton, self.autoRegisterHintLabel, self.devButton,
        self.linksRow, self.backToLoginButton, self.serverLabel, self.agreeFooter
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:8 afterView:self.errorLabel];
    [self.view addSubview:stack];
    self.mainStack = stack;
    [self setupSubpages];
    self.tab = IMLoginInitialTab(IMLoginTabsForConfig(nil), IMLoginRememberedTab(NSUserDefaults.standardUserDefaults));
    [self applyMode];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24],
    ]];
    self.stackTopConstraint = [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:kIMLoginStackTop];
    self.stackTopConstraint.active = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (UILabel *)label:(CGFloat)size color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.font = [UIFont systemFontOfSize:size];
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text keyboard:(UIKeyboardType)keyboard secure:(BOOL)secure {
    UITextField *field = [UITextField new];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholder;
    field.text = text;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.keyboardType = keyboard;
    field.secureTextEntry = secure;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    // 同一个键盘下切换输入框时系统不再发键盘通知，要靠开始编辑事件重新算上移量。
    [field addTarget:self action:@selector(fieldDidBeginEditing:) forControlEvents:UIControlEventEditingDidBegin];
    [field addTarget:self action:@selector(fieldEdited) forControlEvents:UIControlEventEditingChanged];
    [field.heightAnchor constraintEqualToConstant:44].active = YES;
    return field;
}

- (UIButton *)buttonTitle:(NSString *)title config:(UIButtonConfiguration *)config action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.configuration = config;
    [b setTitle:title forState:UIControlStateNormal];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

/// 15 regular accent 文字链（「返回登录」等）。
- (UIButton *)linkButton:(NSString *)title action:(SEL)action {
    UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
    cfg.baseForegroundColor = IMTheme.accent;
    cfg.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attrs) {
        NSMutableDictionary *m = [attrs mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:15];
        return m;
    };
    return [self buttonTitle:title config:cfg action:action];
}

#pragma mark - 页面结构（对齐 Android）

/// 80pt 圆角 accent 方块 + 白色气泡图标，居中（Android 登录页 Logo）。
- (UIView *)logoView {
    UIView *holder = [UIView new];
    holder.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *box = [UIView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.backgroundColor = IMTheme.accent;
    box.layer.cornerRadius = 20;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"message"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:36 weight:UIImageSymbolWeightRegular]]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.whiteColor;
    [box addSubview:icon];
    [holder addSubview:box];
    box.accessibilityIdentifier = @"login.logo";
    [box addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(logoLongPressed:)]];
    [NSLayoutConstraint activateConstraints:@[
        [box.widthAnchor constraintEqualToConstant:80], [box.heightAnchor constraintEqualToConstant:80],
        [box.topAnchor constraintEqualToAnchor:holder.topAnchor], [box.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
        [box.centerXAnchor constraintEqualToAnchor:holder.centerXAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:box.centerXAnchor], [icon.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
    ]];
    return holder;
}

- (UILabel *)titleLabelView {
    UILabel *label = [UILabel new];
    label.text = @"IM";
    label.font = [UIFont systemFontOfSize:24 weight:UIFontWeightRegular];
    label.textAlignment = NSTextAlignmentCenter;
    return label;
}

#pragma mark - 页签 / 模式

- (void)smsTabTapped { [self selectTab:IMLoginTabSMS]; }
- (void)passwordTabTapped { [self selectTab:IMLoginTabPassword]; }

- (void)selectTab:(IMLoginTab)tab {
    self.touched = YES;
    if (self.tab == tab && !self.registerMode) { return; }
    self.tab = tab;
    [self showError:@""];
    [self applyMode];
}

/// 底部「用户名注册」：原注册表单（用户名 / 昵称 / 密码），有「返回登录」。
- (void)registerTabTapped {
    if (self.registerMode || self.submitting) { return; } // 请求在途不切表单（与 backToLoginTapped 对齐）
    self.touched = YES;
    self.registerMode = YES;
    [self showError:@""];
    [self applyMode];
    [self reloadLoginConfigHostChanged:NO]; // 注册开关以最新为准
}

- (void)backToLoginTapped {
    if (!self.registerMode || self.submitting) { return; }
    self.registerMode = NO;
    [self showError:@""];
    [self applyMode];
}

/// 用户开始输入：public-config 晚到时不再切页签；清红字（重新给一次机会，不清空输入）。
- (void)fieldEdited {
    self.touched = YES;
}

/// 按模式 / 页签显隐控件并刷新页签选中态（选中 accentSoft 底 + accent 字，未选中卡片底 + 次要字）。
- (void)applyMode {
    BOOL reg = self.registerMode;
    IMLoginConfig *cfg = self.loginConfig;
    NSArray<NSNumber *> *tabs = IMLoginTabsForConfig(cfg);
    if (![tabs containsObject:@(self.tab)]) { self.tab = (IMLoginTab)tabs.firstObject.integerValue; }
    BOOL sms = !reg && self.tab == IMLoginTabSMS;
    BOOL pwd = !reg && self.tab == IMLoginTabPassword;
    self.tabsRow.hidden = reg || tabs.count < 2;
    self.smsFields.hidden = !sms;
    self.smsLoginButton.hidden = !sms;
    self.autoRegisterHintLabel.hidden = !sms || !IMLoginShowsAutoRegisterHint(cfg);
    // 注册页签用用户名规则（不接受邮箱 / 手机号）；密码登录的登录名可以是用户名 / 邮箱 / 手机号。
    self.userIDField.hidden = sms;
    self.userIDField.placeholder = IMLocalized(reg ? @"login.username.placeholder" : @"login.ident.placeholder");
    self.passwordField.hidden = sms;
    self.passwordField.placeholder = IMLocalized(reg ? @"login.password.placeholder" : @"login.password");
    self.nicknameField.hidden = !reg;
    self.registerHintLabel.hidden = !reg;
    self.registerButton.hidden = !reg;
    self.registerClosedLabel.hidden = !(reg && self.registerClosed);
    self.loginButton.hidden = !pwd;
#ifdef DEBUG
    self.devButton.hidden = !pwd;
#endif
    self.forgotButton.hidden = !IMLoginShowsForgotPassword(cfg);
    self.usernameRegisterButton.hidden = !IMLoginShowsUsernameRegister(cfg);
    self.linksRow.hidden = reg || (self.forgotButton.hidden && self.usernameRegisterButton.hidden);
    self.backToLoginButton.hidden = !reg;
    [self styleTab:self.smsTabButton selected:sms];
    [self styleTab:self.passwordTabButton selected:pwd];
}

- (void)styleTab:(UIButton *)button selected:(BOOL)selected {
    UIButtonConfiguration *config = button.configuration;
    config.baseBackgroundColor = selected ? IMTheme.accentSoft : UIColor.secondarySystemGroupedBackgroundColor;
    config.baseForegroundColor = selected ? IMTheme.accent : UIColor.secondaryLabelColor;
    config.background.cornerRadius = 10;
    config.background.backgroundColor = config.baseBackgroundColor;
    button.configuration = config;
}

#pragma mark - 密码登录 / 用户名注册 / 免密

/// 登录：带密码做真账号校验，成功才进主界面；失败把服务端文案显示在登录页（不深入 App 再报错）。
- (void)loginTapped {
    NSString *host = [self resolvedHostOrShowError];
    if (host.length == 0) { return; }
    NSString *ident = [self trimmed:self.userIDField.text];
    NSString *password = self.passwordField.text ?: @"";
    if (ident.length == 0 || password.length == 0) {
        [self showError:IMLocalized(@"login.error.fill_credentials")];
        return;
    }
    [self loginWithHost:host username:ident password:password fallback:IMLocalized(@"login.error.login_failed")
           activeButton:self.loginButton rememberTab:IMLoginTabPassword];
}

/// 注册并登录：先注册账号，成功后用同一密码进入。
- (void)registerTapped {
    if (self.registerClosed) { return; } // 按钮已禁用，防御一下
    NSString *host = [self resolvedHostOrShowError];
    if (host.length == 0) { return; }
    NSString *username = [self trimmed:self.userIDField.text];
    NSString *nickname = [self trimmed:self.nicknameField.text];
    NSString *password = self.passwordField.text ?: @"";
    if (username.length == 0 || password.length < 6) {
        [self showError:IMLocalized(@"login.error.register_requirements")];
        return;
    }
    // 昵称必填：全端显示名回退链止于它，留空会让界面露出 10 位数字内部 ID。后端也会拒，这里前置提示省一次往返。
    if (nickname.length == 0) {
        [self showError:IMLocalized(@"login.error.nickname_required")];
        return;
    }
    [self showError:@""];
    [self setBusy:YES activeButton:self.registerButton];
    [self prepareServiceWithHost:host password:password];
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService registerWithUsername:username password:password nickname:nickname
                                          completion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) {
            [self setBusy:NO activeButton:self.registerButton];
            if (error.code == IMErrCodeRegisterClosed) {
                // 页面打开后管理员才关的注册（或 public-config 没拉到）：转成内联提示 + 禁用，不再重复红字。
                // 在途的 public-config（可能是失败兜底的 YES）不得把这条权威结论翻回开放；但也不能直接 cancel 丢掉它——
                // 首次配置还没回来时 loginConfig 会一直是 nil（没有验证码页签 / 忘记密码）。改为重拉一次，回来后仍标记关闭。
                [self applyRegisterClosed:YES];
                [self reloadLoginConfigAfterRegisterClosed];
                return;
            }
            [self showError:error.localizedDescription ?: IMLocalized(@"login.error.register_failed")];
            return;
        }
        // 注册接口不签发 token——必须再登录一次拿 token + 内部 ID。用户名注册不记页签。
        [self loginWithHost:host username:username password:password
                   fallback:IMLocalized(@"login.error.register_login_failed") activeButton:self.registerButton rememberTab:IMLoginTabNone];
    }];
}

/// 免密登录（开发）：清空密码走后端 dev-login，凭 username 直签。**同样真发一次 POST /login**：登录页必须能自证后端可达。
- (void)devLoginTapped {
    NSString *host = [self resolvedHostOrShowError];
    if (host.length == 0) { return; }
    NSString *userID = [self trimmed:self.userIDField.text];
    if (userID.length == 0) {
        [self showError:@"请填写用户名（uid）"];
        return;
    }
    [self loginWithHost:host username:userID password:@"" fallback:IMLocalized(@"login.error.dev_login_failed")
           activeButton:self.devButton rememberTab:IMLoginTabNone];
}

/// 登录入口共用：host/密码设入服务层 → 真发一次 POST /login → 成功才进主界面，失败把文案留在登录页。
/// password 传空串即走后端 dev-login 免密直签；fallback 仅在错误无文案时兜底。
- (void)loginWithHost:(NSString *)host username:(NSString *)username password:(NSString *)password
             fallback:(NSString *)fallback activeButton:(UIButton *)activeButton rememberTab:(IMLoginTab)rememberTab {
    [self showError:@""];
    [self setBusy:YES activeButton:activeButton];
    [self prepareServiceWithHost:host password:password];
    __weak typeof(self) weakSelf = self;
    // 入参是登录名（用户名 / 邮箱 / 手机号），回来的 userID 才是服务端分配的**内部 ID**。
    [IMHTTPService.sharedService loginWithUsername:username completion:^(NSString *token, NSString *userID, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        [self setBusy:NO activeButton:activeButton];
        if (token.length == 0 || userID.length == 0) {
            if (error.code == IMErrCodeAccountPendingDeletion && password.length == 0) {
                [self showError:IMLocalized(@"err.200005")]; // 免密路径没有密码可交给 /account/restore
                return;
            }
            NSString *ticket = error.userInfo[IMErrorTwoStepTicketKey];
            if (error.code == IMErrCodeTwoStepRequired && ticket.length > 0) {
                [self beginTwoStepWithTicket:ticket host:host tab:rememberTab];
                return;
            }
            if (error.code == IMErrCodeAccountPendingDeletion) {
                [self promptRestoreForHost:host username:username password:password fallback:fallback
                              activeButton:activeButton deleteAt:error.userInfo[IMErrorDeleteAtKey] rememberTab:rememberTab];
                return;
            }
            [self showError:error.localizedDescription.length > 0 ? error.localizedDescription : fallback];
            return;
        }
        // 服务端在登录响应里给了 username（IMHTTPService 已据此改写）；老服务端没给时是用户输入的登录名，进主界面前再判一次可信。
        [self enterAppWithHost:host userID:userID username:IMHTTPService.sharedService.username rememberTab:rememberTab];
    }];
}

/// 冷静期内登录（AccountPendingDeletion）：弹「恢复账号」确认；确认后调 restore，成功再按原凭据继续登录。
- (void)promptRestoreForHost:(NSString *)host username:(NSString *)username password:(NSString *)password
                    fallback:(NSString *)fallback activeButton:(UIButton *)activeButton
                    deleteAt:(nullable NSDate *)deleteAt rememberTab:(IMLoginTab)rememberTab {
    __weak typeof(self) weakSelf = self;
    [self presentRestoreConfirmWithDeleteAt:deleteAt onConfirm:^{
        __strong typeof(weakSelf) self = weakSelf;
        [self setBusy:YES activeButton:activeButton];
        [IMHTTPService.sharedService restoreAccountWithUsername:username password:password completion:^(NSError *error) {
            if (error) {
                [weakSelf setBusy:NO activeButton:activeButton];
                [weakSelf showError:IMErrorMessageOrFallback(error, fallback)];
                return;
            }
            [weakSelf loginWithHost:host username:username password:password fallback:fallback activeButton:activeButton rememberTab:rememberTab];
        }];
    }];
}

/// 「恢复账号」确认框（密码登录与验证码登录命中冷静期共用）：取消不做事，确认回调 onConfirm。
- (void)presentRestoreConfirmWithDeleteAt:(nullable NSDate *)deleteAt onConfirm:(void (^)(void))onConfirm {
    NSString *message = deleteAt ? IMLocalizedFormat(@"delete_account.restore_message", IMDeleteAtDisplayString(deleteAt))
                                 : IMLocalized(@"delete_account.restore_title");
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"delete_account.restore_title")
                                                                message:message preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"delete_account.restore_action") style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) { onConfirm(); }]];
    [self presentViewController:ac animated:YES completion:nil];
}

/// 请求在途：被点的按钮转菊花，所有入口一起禁用（防重复提交）。configuration 是值语义，改完必须整份回写。
- (void)setBusy:(BOOL)busy activeButton:(UIButton *)activeButton {
    self.submitting = busy;
    for (UIButton *button in @[self.loginButton, self.registerButton, self.devButton, self.smsLoginButton]) {
        button.enabled = !busy && !(button == self.registerButton && self.registerClosed);
        UIButtonConfiguration *config = button.configuration;
        config.showsActivityIndicator = (busy && button == activeButton);
        button.configuration = config;
    }
    self.smsTabButton.enabled = self.passwordTabButton.enabled = !busy;
    self.usernameRegisterButton.enabled = self.forgotButton.enabled = !busy; // 底部两个链接同样会切走表单
}

/// 解析当前服务器地址：接受 `host:port` 与 `http(s)://host:port` 两种写法。协议记进 IMServerEndpoint（全 App 唯一权威）并持久化；
/// 返回纯 `host:port`。非法或为空时**已经把错误显示出来**并返回空串，调用方直接 return 即可。
- (NSString *)resolvedHostOrShowError {
    NSString *raw = [self trimmed:self.hostInput];
    if (raw.length == 0) {
        [self showError:IMLocalized(@"login.error.host_required")];
        return @"";
    }
    NSString *scheme = nil, *host = nil;
    if (![IMServerEndpoint parseInput:raw scheme:&scheme host:&host]) {
        [self showError:IMLocalized(@"login.error.host_invalid")];
        return @"";
    }
    IMServerEndpoint.shared.scheme = scheme;
    [IMSessionStore saveScheme:scheme];
    return host;
}

/// 把 host/password 设入共享 HTTP 服务，供后续所有内部登录与 socket 换 token 复用。
- (void)prepareServiceWithHost:(NSString *)host password:(NSString *)password {
    IMHTTPService.sharedService.host = host;
    IMHTTPService.sharedService.password = password;
    // 换账号/重新登录：先擦掉上一个账号的续期凭据（内存 + 磁盘），免得兜底路径拿它换到别人的 token。
    IMHTTPService.sharedService.refreshToken = nil;
    [IMSessionStore saveRefreshToken:nil];
    // 作废内存里的旧 token：loginWithUserID 有 10 分钟 TTL 缓存，不清就可能命中缓存直接回调成功。
    [IMHTTPService.sharedService invalidateToken];
    // 记住，下次免重填。**带上协议**：只存 host 的话 https 下次会静默退回 http。
    NSString *remembered = [IMServerEndpoint rememberedInputForScheme:IMServerEndpoint.shared.scheme host:host];
    [NSUserDefaults.standardUserDefaults setObject:remembered forKey:kIMLastHostKey];
}

- (void)enterAppWithHost:(NSString *)host userID:(NSString *)userID username:(NSString *)username rememberTab:(IMLoginTab)rememberTab {
    // username 只来自登录成功响应（adoptLoginSuccessData 已滤掉输入的手机号 / 邮箱），直接存。
    [IMSessionStore saveHost:host userID:userID username:username];
    // 记住页签只在真正进入主界面后保存；用户名注册 / 免密传 IMLoginTabNone 不记。
    IMLoginRememberTab(NSUserDefaults.standardUserDefaults, rememberTab);
    IMMainTabBarController *main = [[IMMainTabBarController alloc] initWithHost:host userID:userID];
    self.view.window.rootViewController = main;
}

#pragma mark - 子页（同页切换）

- (void)setupSubpages {
    self.twoStepView = [IMLoginTwoStepView new];
    self.twoStepView.hidden = YES;
    __weak typeof(self) ws = self;
    self.twoStepView.onSubmit = ^(NSString *code, BOOL recovery) { [ws submitTwoStepCode:code recovery:recovery]; };
    self.twoStepView.onBack = ^{ [ws leaveSubpage]; };
    [self.mainStack addArrangedSubview:self.twoStepView];
    for (UIView *page in @[self.completeView, self.resetView]) {
        page.hidden = YES;
        [self.mainStack addArrangedSubview:page];
    }
}

/// 进入子页：把当前可见的控件藏起来（返回时原样恢复），只显示子页。
- (void)enterSubpage:(UIView *)page {
    if (self.currentSubpage) { [self leaveSubpage]; }
    NSMutableArray<UIView *> *visible = [NSMutableArray array];
    for (UIView *v in self.mainStack.arrangedSubviews) {
        if (v == page || v.hidden) { continue; }
        [visible addObject:v];
        v.hidden = YES;
    }
    self.viewsHiddenForSubpage = visible;
    self.currentSubpage = page;
    [self showError:@""];
    page.hidden = NO;
}

/// 离开子页（返回 / 凭证失效 / 成功）：丢弃 ticket 与内存里的密码，恢复进入前的控件。
- (void)leaveSubpage {
    UIView *page = self.currentSubpage;
    if (!page) { return; }
    if (page == self.twoStepView) {
        self.twoStepTicket = nil;
        IMHTTPService.sharedService.password = nil;
        [self.twoStepView resetForNewTicket];
    }
    if (page == self.completeView) { self.registerTicket = nil; }
    [self.view endEditing:YES];
    page.hidden = YES;
    self.currentSubpage = nil;
    for (UIView *v in self.viewsHiddenForSubpage) { v.hidden = NO; }
    self.viewsHiddenForSubpage = @[];
    [self applyMode];
    self.stackTopConstraint.constant = kIMLoginStackTop;
}

/// 账号已开启两步验证（200020）：登录页换成二步页，ticket 只留内存。tab = 从哪个页签进来的（成功后记住它）。
- (void)beginTwoStepWithTicket:(NSString *)ticket host:(NSString *)host tab:(NSInteger)tab {
    self.twoStepTicket = ticket;
    self.twoStepHost = host;
    self.twoStepTab = tab;
    [self enterSubpage:self.twoStepView];
    [self.twoStepView resetForNewTicket];
    [self.twoStepView focusInput];
    IMLogUI(@"login_twostep_begin");
}

- (void)submitTwoStepCode:(NSString *)code recovery:(BOOL)recovery {
    NSString *ticket = self.twoStepTicket;
    if (ticket.length == 0 || self.twoStepView.busy) { return; }
    self.twoStepView.busy = YES;
    [self.twoStepView showError:nil];
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService loginTwoStepWithTicket:ticket code:code
                                             completion:^(NSString *token, NSString *userID, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || ![self.twoStepTicket isEqualToString:ticket]) { return; } // 已离开二步页
        self.twoStepView.busy = NO;
        if (token.length > 0 && userID.length > 0) {
            NSString *host = self.twoStepHost;
            self.twoStepTicket = nil;
            IMLogUI(@"login_twostep_ok method=%@", recovery ? @"recovery" : @"totp");
            [self enterAppWithHost:host userID:userID username:IMHTTPService.sharedService.username rememberTab:self.twoStepTab];
            return;
        }
        [self handleTwoStepFailure:error recovery:recovery];
    }];
}

- (void)handleTwoStepFailure:(NSError *)error recovery:(BOOL)recovery {
    IMLogWarnWithTag(IMLogTagUI, @"login_twostep_failed code=%ld", (long)error.code);
    IMTwoStepLoginAction action = IMTwoStepLoginActionForError(error.code, recovery);
    NSInteger left = [error.userInfo[IMErrorTwoStepAttemptsLeftKey] respondsToSelector:@selector(integerValue)]
        ? [error.userInfo[IMErrorTwoStepAttemptsLeftKey] integerValue] : -1;
    NSString *msg = IMTwoStepErrorMessage(error.code, IMTwoStepErrorContextLogin, left, IMTwoStepRecentlyEnabled([NSDate date]) && !recovery,
                                          error.localizedDescription.length > 0 ? error.localizedDescription : IMLocalized(@"login.error.login_failed"));
    if (action == IMTwoStepLoginActionExpired) { // ticket 已作废：回登录页
        [self leaveSubpage];
        [self showError:msg];
        return;
    }
    [self.twoStepView showError:msg];
    if (action == IMTwoStepLoginActionRetryCode) { [self.twoStepView clearCodeAndRefocus]; }
}

#pragma mark - 键盘

/// 键盘顶起：当前输入框（子页则是整个子页）必须在键盘之上可见，小屏也要。登录页没有滚动容器，直接上移整列。
- (void)keyboardWillChange:(NSNotification *)note {
    CGRect end = [self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    self.keyboardTop = MIN(end.origin.y, CGRectGetMaxY(self.view.bounds));
    [self liftForKeyboardWithDuration:[note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
}

- (void)fieldDidBeginEditing:(UITextField *)field {
    [self liftForKeyboardWithDuration:0.25];
}

/// 当前主按钮（编辑完输入框就是点它）：它也要露在键盘之上。
- (UIButton *)currentActionButton {
    if (self.registerMode) { return self.registerButton; }
    return self.tab == IMLoginTabSMS ? self.smsLoginButton : self.loginButton;
}

- (void)liftForKeyboardWithDuration:(NSTimeInterval)duration {
    // 不能因为「此刻不在窗口里」就跳过：应用内浏览器弹出期间键盘收起的通知会在离屏时到达。离屏也能布局和量，直接算。
    if (!self.isViewLoaded) { return; }
    [self.view layoutIfNeeded]; // 刚切到子页时那一列的高度还没重排，先结算再量
    CGFloat keyboardTop = self.keyboardTop > 0 ? self.keyboardTop : CGRectGetMaxY(self.view.bounds);
    CGFloat lift = 0;
    UIView *page = self.currentSubpage;
    UIView *active = nil;
    if (page) {
        // 子页：以当前输入框与子页里的主按钮为准（整页可能比屏幕高，不能按整列下沿）。
        for (UITextField *f in [self textFieldsIn:page]) { if (f.isFirstResponder) { active = f; break; } }
    } else {
        for (UITextField *f in @[self.userIDField, self.nicknameField, self.passwordField, self.smsFields.phoneField, self.smsFields.codeField]) {
            if (f.isFirstResponder && !f.hidden && !f.superview.hidden) { active = f; break; }
        }
    }
    if (active) {
        // 此刻量到的是已上移后的位置，加回当前上移量才是静止位置。
        CGFloat currentLift = kIMLoginStackTop - self.stackTopConstraint.constant;
        CGRect frame = [self.view convertRect:active.bounds fromView:active];
        CGFloat bottomAtRest = CGRectGetMaxY(frame) + currentLift;
        UIButton *action = page ? [self primaryButtonOfSubpage:page] : [self currentActionButton];
        if (action) {
            CGRect buttonFrame = [self.view convertRect:action.bounds fromView:action];
            bottomAtRest = MAX(bottomAtRest, CGRectGetMaxY(buttonFrame) + currentLift);
        }
        lift = IMLoginKeyboardLift(bottomAtRest, keyboardTop);
        // 矮屏（横屏 / 大字号）放不下时，宁可让输入框下沿贴着键盘，也不能把输入框自己顶出安全区上沿。
        CGFloat topAtRest = CGRectGetMinY(frame) + currentLift;
        CGFloat safeTop = self.view.safeAreaLayoutGuide.layoutFrame.origin.y;
        lift = MIN(lift, MAX(0, topAtRest - safeTop));
    }
    self.stackTopConstraint.constant = kIMLoginStackTop - lift;
    [UIView animateWithDuration:duration animations:^{ [self.view layoutIfNeeded]; }];
}

- (NSArray<UITextField *> *)textFieldsIn:(UIView *)view {
    NSMutableArray *out = [NSMutableArray array];
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UITextField.class]) { [out addObject:sub]; }
        else { [out addObjectsFromArray:[self textFieldsIn:sub]]; }
    }
    return out;
}

- (nullable UIButton *)primaryButtonOfSubpage:(UIView *)page {
    if (page == self.completeView) { return self.completeView.submitButton; }
    if (page == self.resetView) { return self.resetView.submitButton; }
    if (page == self.twoStepView) { return self.twoStepView.recoveryMode ? self.twoStepView.submitButton : nil; }
    return nil;
}

#pragma mark - 杂项

- (NSString *)trimmed:(NSString *)text {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

- (void)showError:(NSString *)message {
    self.errorLabel.textColor = UIColor.systemRedColor;
    self.errorLabel.text = message;
    self.errorLabel.hidden = (message.length == 0);
}

/// 非错误提示（沿用错误行位置，改用 accent 色，非红）。下一次 showError: 会恢复红色并覆盖它。
- (void)showNotice:(NSString *)message {
    self.errorLabel.textColor = IMTheme.accent;
    self.errorLabel.text = message;
    self.errorLabel.hidden = (message.length == 0);
}

@end
