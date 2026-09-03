//  IMLoginViewController.m

#import "IMLoginViewController.h"
#import "IMMainTabBarController.h"
#import "IMHTTPService.h"
#import "IMSessionStore.h"
#import "IMServerEndpoint.h"

static NSString * const kIMLastHostKey = @"im_last_host"; // 记住上次用过的 host

@interface IMLoginViewController ()
@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UITextField *userIDField;   ///< 用户名（公开句柄 username）
@property (nonatomic, strong) UITextField *nicknameField; ///< 昵称（显示名，仅注册时用；必填）
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UILabel *errorLabel;
/// 三个登录入口提成属性：请求在途时要把被点的那个转成菊花、另外两个禁用（见 setBusy:activeButton:）。
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIButton *registerButton;
@property (nonatomic, strong) UIButton *devButton;
@property (nonatomic, assign) BOOL submitting;
@end

@implementation IMLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IMProgram 登录";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self setupUI];
}

/// 默认 host：模拟器恒用 127.0.0.1（避免 localhost DNS 解析在 iOS 模拟器偶发失败——
/// Go WS/HTTP 与 IMRemoteLogSink 都会静默挂掉。见 current_task.md 已知坑 / memory 记录）。
/// 真机优先用上次成功填过的地址，否则给个占位让用户改成 Mac 当前局域网 IP。
- (NSString *)defaultHost {
#if TARGET_OS_SIMULATOR
    // 优先用上次成功填过的地址（切网/切端口时无需每次改），未填过回退 127.0.0.1:8080。
    NSString *last = [NSUserDefaults.standardUserDefaults stringForKey:kIMLastHostKey];
    return last.length > 0 ? last : @"127.0.0.1:8080";
#else
    NSString *last = [NSUserDefaults.standardUserDefaults stringForKey:kIMLastHostKey];
    return last.length > 0 ? last : @"192.168.1.x:8080";
#endif
}

- (void)setupUI {
    self.hostField     = [self fieldWithPlaceholder:@"服务器地址 host:port" text:[self defaultHost] keyboard:UIKeyboardTypeURL secure:NO];
    // 用户名规则与服务端 ^[a-z0-9_]{5,32}$ 对齐（后端权威校验，这里只做提示与键盘优化）。
    self.userIDField   = [self fieldWithPlaceholder:@"用户名（a-z、0-9、下划线，≥5 位）" text:@"" keyboard:UIKeyboardTypeASCIICapable secure:NO];
    self.userIDField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.userIDField.autocorrectionType = UITextAutocorrectionTypeNo;
    // 昵称是显示名（可中文/emoji），与用户名是两回事；仅"注册并登录"用得到。
    self.nicknameField = [self fieldWithPlaceholder:@"昵称（注册用，可中文，≤32 字）" text:@"" keyboard:UIKeyboardTypeDefault secure:NO];
    self.passwordField = [self fieldWithPlaceholder:@"密码（≥ 6 位）" text:@"" keyboard:UIKeyboardTypeDefault secure:YES];

    self.errorLabel = [UILabel new];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.font = [UIFont systemFontOfSize:13];
    self.errorLabel.textColor = UIColor.systemRedColor;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;

    self.loginButton = [self buttonTitle:@"登录" config:[UIButtonConfiguration filledButtonConfiguration] action:@selector(loginTapped)];
    self.registerButton = [self buttonTitle:@"注册并登录" config:[UIButtonConfiguration tintedButtonConfiguration] action:@selector(registerTapped)];
    self.devButton = [self buttonTitle:@"免密登录（开发）" config:[UIButtonConfiguration plainButtonConfiguration] action:@selector(devLoginTapped)];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.hostField, self.userIDField, self.nicknameField, self.passwordField, self.errorLabel,
        self.loginButton, self.registerButton, self.devButton
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
    NSString *host = [self resolvedHostOrShowError];
    if (host.length == 0) { return; }
    NSString *userID = [self trimmed:self.userIDField.text];
    NSString *password = self.passwordField.text ?: @"";
    if (userID.length == 0 || password.length == 0) {
        [self showError:@"请填写用户名与密码"];
        return;
    }
    [self loginWithHost:host username:userID password:password fallback:@"登录失败" activeButton:self.loginButton];
}

/// 注册并登录：先注册账号，成功后用同一密码进入。
- (void)registerTapped {
    NSString *host = [self resolvedHostOrShowError];
    if (host.length == 0) { return; }
    NSString *username = [self trimmed:self.userIDField.text];
    NSString *nickname = [self trimmed:self.nicknameField.text];
    NSString *password = self.passwordField.text ?: @"";
    if (username.length == 0 || password.length < 6) {
        [self showError:@"用户名必填，密码至少 6 位"];
        return;
    }
    // 昵称必填：全端显示名回退链止于它，留空会让界面露出 10 位数字内部 ID。
    // 后端也会拒，这里前置提示省一次往返。
    if (nickname.length == 0) {
        [self showError:@"请填写昵称（这是别人看到的名字）"];
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
            [self showError:error.localizedDescription ?: @"注册失败"];
            return;
        }
        // 注册接口不签发 token，也不回内部 ID 之外的东西——必须再登录一次拿 token + 内部 ID。
        [self loginWithHost:host username:username password:password
                   fallback:@"注册成功但登录失败" activeButton:self.registerButton];
    }];
}

/// 免密登录（开发）：清空密码走后端 dev-login，凭 uid 直签。
/// **同样真发一次 POST /login**：早期这里不打网络直接进主界面，后端连不上时也照样"登录成功"，
/// 把连不通的真相推迟到主界面里静默失败。真机排障踩过——密码登录失败、免密"成功"，误判成密码问题，
/// 实际是手机压根没连上 Mac（iOS 本地网络权限被拒）。登录页必须能自证后端可达。
- (void)devLoginTapped {
    NSString *host = [self resolvedHostOrShowError];
    if (host.length == 0) { return; }
    NSString *userID = [self trimmed:self.userIDField.text];
    if (userID.length == 0) {
        [self showError:@"请填写用户名（uid）"];
        return;
    }
    [self loginWithHost:host username:userID password:@"" fallback:@"免密登录失败（后端需以 -dev-login 启动）" activeButton:self.devButton];
}

/// 登录入口共用：host/密码设入服务层 → 真发一次 POST /login → 成功才进主界面，失败把文案留在登录页。
/// password 传空串即走后端 dev-login 免密直签；fallback 仅在错误无文案时兜底。
- (void)loginWithHost:(NSString *)host
             username:(NSString *)username
             password:(NSString *)password
             fallback:(NSString *)fallback
         activeButton:(UIButton *)activeButton {
    [self showError:@""];
    [self setBusy:YES activeButton:activeButton];
    [self prepareServiceWithHost:host password:password];
    __weak typeof(self) weakSelf = self;
    // 入参是 username（登录凭据），回来的 userID 才是服务端分配的**内部 ID**——
    // App 内一切业务参数（conv_id 推导、好友接口、消息 sender）都用后者，绝不能拿 username 冒充。
    [IMHTTPService.sharedService loginWithUsername:username completion:^(NSString *token, NSString *userID, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        [self setBusy:NO activeButton:activeButton];
        if (token.length == 0 || userID.length == 0) {
            [self showError:error.localizedDescription.length > 0 ? error.localizedDescription : fallback];
            return;
        }
        [self enterAppWithHost:host userID:userID username:username];
    }];
}

/// 请求在途：被点的按钮转菊花，三个入口一起禁用（防重复提交，也让"点了没反应"变成看得见的进行中）。
/// 用 UIButtonConfiguration 自带的 showsActivityIndicator（iOS 15+），不自己加 UIActivityIndicatorView；
/// 注意 configuration 是值语义，改完必须整份回写按钮才生效。
- (void)setBusy:(BOOL)busy activeButton:(UIButton *)activeButton {
    self.submitting = busy;
    for (UIButton *button in @[self.loginButton, self.registerButton, self.devButton]) {
        button.enabled = !busy;
        UIButtonConfiguration *config = button.configuration;
        config.showsActivityIndicator = (busy && button == activeButton);
        button.configuration = config;
    }
}

/// 解析服务器地址输入框：接受 `host:port` 与 `http(s)://host:port` 两种写法。
/// 协议记进 IMServerEndpoint（全 App 唯一权威）并持久化；返回纯 `host:port`——
/// App 内各处仍按 host 串传递，协议不再各自拼字面量。
/// 非法或为空时**已经把错误显示出来**并返回空串，调用方直接 return 即可。
///
/// 这是「以后换 https 不用改代码」的落点：用户把地址改成 `https://im.example.com` 就整端切换，
/// HTTP / WebSocket / 媒体补全 / 日志上报四路一起走 TLS。
- (NSString *)resolvedHostOrShowError {
    NSString *raw = [self trimmed:self.hostField.text];
    if (raw.length == 0) {
        [self showError:@"请填写服务器地址"];
        return @"";
    }
    NSString *scheme = nil, *host = nil;
    if (![IMServerEndpoint parseInput:raw scheme:&scheme host:&host]) {
        [self showError:@"服务器地址格式不对（示例：192.168.1.12:8080 或 https://im.example.com）"];
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
    // 换账号/重新登录：先擦掉上一个账号的续期凭据（内存 + 磁盘）。留着的话，本次密码填错后
    // 内存里仍躺着一枚别人的有效凭据，任何走 loginWithUserID: 的兜底路径都可能拿它换到 token。
    IMHTTPService.sharedService.refreshToken = nil;
    [IMSessionStore saveRefreshToken:nil];
    // 作废内存里的旧 token：loginWithUserID 有 10 分钟 TTL 缓存，不清就可能命中缓存直接回调成功——
    // 换 host / 换账号 / 改了密码后仍复用旧 token，且登录页看不出后端是否真的可达（排障假象）。
    [IMHTTPService.sharedService invalidateToken];
    // 记住，下次免重填。**带上协议**：只存 host 的话，这次填的 https 下次回填成裸 host，
    // 又静默退回默认的 http（用户看不出来，只会觉得"怎么又不加密了"）。
    NSString *remembered = IMServerEndpoint.shared.isSecure
        ? [@"https://" stringByAppendingString:host] : host;
    [NSUserDefaults.standardUserDefaults setObject:remembered forKey:kIMLastHostKey];
}

- (void)enterAppWithHost:(NSString *)host userID:(NSString *)userID username:(NSString *)username {
    // 持久化会话（保持登录）。下次启动靠 refresh_token 静默换 token 直达主界面——
    // 那枚凭据由 IMHTTPService 在登录响应里收到时自行落盘，这里不经手（也不再存明文密码）。
    // **username 必须一起存**——它是密码登录的凭据；续期失效退回登录页时要能回填。
    [IMSessionStore saveHost:host userID:userID username:username];
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
