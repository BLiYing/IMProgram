//  IMLoginViewController.m

#import "IMLoginViewController.h"
#import "IMMainTabBarController.h"
#import "IMHTTPService.h"
#import "IMSessionStore.h"

static NSString * const kIMLastHostKey = @"im_last_host"; // 记住上次用过的 host

@interface IMLoginViewController ()
@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UITextField *userIDField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UILabel *errorLabel;
@end

@implementation IMLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IMProgram 登录";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self setupUI];
}

/// 默认 host：模拟器恒用 localhost（与 Mac 共享网络，不受 DHCP 变 IP 影响）；
/// 真机优先用上次成功填过的地址，否则给个占位让用户改成 Mac 当前局域网 IP。
- (NSString *)defaultHost {
#if TARGET_OS_SIMULATOR
    return @"localhost:8080";
#else
    NSString *last = [NSUserDefaults.standardUserDefaults stringForKey:kIMLastHostKey];
    return last.length > 0 ? last : @"192.168.1.x:8080";
#endif
}

- (void)setupUI {
    self.hostField     = [self fieldWithPlaceholder:@"服务器地址 host:port" text:[self defaultHost] keyboard:UIKeyboardTypeURL secure:NO];
    self.userIDField   = [self fieldWithPlaceholder:@"用户名" text:@"" keyboard:UIKeyboardTypeDefault secure:NO];
    self.passwordField = [self fieldWithPlaceholder:@"密码（≥ 6 位）" text:@"" keyboard:UIKeyboardTypeDefault secure:YES];

    self.errorLabel = [UILabel new];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.font = [UIFont systemFontOfSize:13];
    self.errorLabel.textColor = UIColor.systemRedColor;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;

    UIButton *loginButton = [self buttonTitle:@"登录" config:[UIButtonConfiguration filledButtonConfiguration] action:@selector(loginTapped)];
    UIButton *registerButton = [self buttonTitle:@"注册并登录" config:[UIButtonConfiguration tintedButtonConfiguration] action:@selector(registerTapped)];
    UIButton *devButton = [self buttonTitle:@"免密登录（开发）" config:[UIButtonConfiguration plainButtonConfiguration] action:@selector(devLoginTapped)];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.hostField, self.userIDField, self.passwordField, self.errorLabel, loginButton, registerButton, devButton
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:8 afterView:self.errorLabel];
    [self.view addSubview:stack];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:40],
    ]];
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

#pragma mark - 交互

/// 登录：带密码做真账号校验，成功才进主界面；失败把服务端文案显示在登录页（不深入 App 再报错）。
- (void)loginTapped {
    NSString *host = [self trimmed:self.hostField.text];
    NSString *userID = [self trimmed:self.userIDField.text];
    NSString *password = self.passwordField.text ?: @"";
    if (host.length == 0 || userID.length == 0 || password.length == 0) {
        [self showError:@"请填写服务器地址、用户名与密码"];
        return;
    }
    [self prepareServiceWithHost:host password:password];
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            [self showError:error.localizedDescription ?: @"登录失败"];
            return;
        }
        [self enterAppWithHost:host userID:userID];
    }];
}

/// 注册并登录：先注册账号，成功后用同一密码进入。
- (void)registerTapped {
    NSString *host = [self trimmed:self.hostField.text];
    NSString *userID = [self trimmed:self.userIDField.text];
    NSString *password = self.passwordField.text ?: @"";
    if (host.length == 0 || userID.length == 0 || password.length < 6) {
        [self showError:@"用户名必填，密码至少 6 位"];
        return;
    }
    [self prepareServiceWithHost:host password:password];
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService registerWithUsername:userID password:password completion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) {
            [self showError:error.localizedDescription ?: @"注册失败"];
            return;
        }
        [self enterAppWithHost:host userID:userID]; // 注册成功 → 直接进入（密码已设入服务层）
    }];
}

/// 免密登录（开发）：清空密码走后端 dev-login，凭 uid 直签。
- (void)devLoginTapped {
    NSString *host = [self trimmed:self.hostField.text];
    NSString *userID = [self trimmed:self.userIDField.text];
    if (host.length == 0 || userID.length == 0) {
        [self showError:@"请填写服务器地址与用户名（uid）"];
        return;
    }
    [self prepareServiceWithHost:host password:@""];
    [self enterAppWithHost:host userID:userID];
}

/// 把 host/password 设入共享 HTTP 服务，供后续所有内部登录与 socket 换 token 复用。
- (void)prepareServiceWithHost:(NSString *)host password:(NSString *)password {
    IMHTTPService.sharedService.host = host;
    IMHTTPService.sharedService.password = password;
    [NSUserDefaults.standardUserDefaults setObject:host forKey:kIMLastHostKey]; // 记住，下次免重填
}

- (void)enterAppWithHost:(NSString *)host userID:(NSString *)userID {
    // 持久化会话（保持登录）：password 从服务层取（免密登录为空串）。下次启动静默重登直达主界面。
    [IMSessionStore saveHost:host userID:userID password:IMHTTPService.sharedService.password];
    IMMainTabBarController *main = [[IMMainTabBarController alloc] initWithHost:host userID:userID];
    self.view.window.rootViewController = main;
}

- (NSString *)trimmed:(NSString *)text {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

- (void)showError:(NSString *)message {
    self.errorLabel.text = message;
    self.errorLabel.hidden = (message.length == 0);
}

@end
