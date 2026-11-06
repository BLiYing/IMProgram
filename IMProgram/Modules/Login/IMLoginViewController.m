//  IMLoginViewController.m

#import "IMLoginViewController.h"
#import "IMLocalization.h"
#import "IMMainTabBarController.h"
#import "IMHTTPService.h"
#import "IMSessionStore.h"
#import "IMServerEndpoint.h"
#import "IMHTTPService+Account.h"
#import "IMHTTPService+TwoStep.h"
#import "IMLoginTwoStepView.h"
#import "IMTwoStep.h"
#import "IMLog.h"
#import "IMTheme.h"
#import "IMAppInfo.h"
#import "IMAboutLinks.h"
#import <SafariServices/SafariServices.h>

static NSString * const kIMLastHostKey = @"im_last_host"; // 记住上次用过的 host

@interface IMLoginViewController () <UITextViewDelegate>
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
// 页面结构对齐 Android LoginScreen：Logo + 「登录 / 注册」页签 + 折叠的服务器地址行。
@property (nonatomic, strong) UIButton *loginTabButton;
@property (nonatomic, strong) UIButton *registerTabButton;
@property (nonatomic, strong) UILabel *registerHintLabel;
@property (nonatomic, strong) UIButton *hostToggleButton;
@property (nonatomic, assign) BOOL registerMode;
// 两步验证二步页（同页切换，不新开页面）：ticket 只留内存，离开二步页即丢弃（TWO_STEP_VERIFICATION_DESIGN §2.3）
@property (nonatomic, strong) UIStackView *mainStack;
@property (nonatomic, strong) IMLoginTwoStepView *twoStepView;
@property (nonatomic, copy, nullable) NSString *twoStepTicket;
@property (nonatomic, copy) NSString *twoStepHost;
@property (nonatomic, copy) NSString *twoStepUsername;
@property (nonatomic, copy) NSArray<UIView *> *viewsHiddenForTwoStep; ///< 进二步页前可见的控件，返回时原样恢复
@property (nonatomic, strong) NSLayoutConstraint *stackTopConstraint;
/// 底部「继续即表示同意《服务条款》和《隐私政策》」：隐式同意（无勾选框），两段链接走应用内浏览器（ABOUT_LEGAL_DESIGN 批②）。
@property (nonatomic, strong) UITextView *agreeFooter;
@end

@implementation IMLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self setupUI];
    if (self.initialNotice.length > 0) { [self showNotice:self.initialNotice]; }
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
    self.hostField     = [self fieldWithPlaceholder:IMLocalized(@"login.host.placeholder") text:[self defaultHost] keyboard:UIKeyboardTypeURL secure:NO];
    // 用户名规则与服务端 ^[a-z0-9_]{5,32}$ 对齐（后端权威校验，这里只做提示与键盘优化）。
    self.userIDField   = [self fieldWithPlaceholder:IMLocalized(@"login.username.placeholder") text:@"" keyboard:UIKeyboardTypeASCIICapable secure:NO];
    self.userIDField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.userIDField.autocorrectionType = UITextAutocorrectionTypeNo;
    // 昵称是显示名（可中文/emoji），与用户名是两回事；仅"注册并登录"用得到。
    self.nicknameField = [self fieldWithPlaceholder:IMLocalized(@"login.nickname.placeholder") text:@"" keyboard:UIKeyboardTypeDefault secure:NO];
    self.passwordField = [self fieldWithPlaceholder:IMLocalized(@"login.password.placeholder") text:@"" keyboard:UIKeyboardTypeDefault secure:YES];

    self.errorLabel = [UILabel new];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.font = [UIFont systemFontOfSize:13];
    self.errorLabel.textColor = UIColor.systemRedColor;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;

    self.registerHintLabel = [UILabel new];
    self.registerHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.registerHintLabel.font = [UIFont systemFontOfSize:13];
    self.registerHintLabel.textColor = UIColor.tertiaryLabelColor;
    self.registerHintLabel.numberOfLines = 0;
    self.registerHintLabel.text = IMLocalized(@"login.register_format_hint");

    self.loginButton = [self buttonTitle:IMLocalized(@"login.button.login") config:[UIButtonConfiguration filledButtonConfiguration] action:@selector(loginTapped)];
    self.registerButton = [self buttonTitle:IMLocalized(@"login.button.register") config:[UIButtonConfiguration filledButtonConfiguration] action:@selector(registerTapped)];
    self.devButton = [self buttonTitle:IMLocalized(@"login.dev_login") config:[UIButtonConfiguration tintedButtonConfiguration] action:@selector(devLoginTapped)];
#ifndef DEBUG
    self.devButton.hidden = YES; // 仅 Debug 包显示免密入口（Android 同口径：release 不显示）
#endif

    // —— 服务器地址（开发期常要改，收在一个可折叠行里）——
    self.hostToggleButton = [self buttonTitle:@"" config:[UIButtonConfiguration plainButtonConfiguration] action:@selector(hostToggleTapped)];
    self.hostField.hidden = YES;
    [self refreshHostToggleTitle];

    self.agreeFooter = [self buildAgreeFooter];

    self.loginTabButton = [self buttonTitle:IMLocalized(@"login.button.login") config:[UIButtonConfiguration plainButtonConfiguration] action:@selector(loginTabTapped)];
    self.registerTabButton = [self buttonTitle:IMLocalized(@"login.tab_register") config:[UIButtonConfiguration plainButtonConfiguration] action:@selector(registerTabTapped)];
    UIStackView *tabs = [[UIStackView alloc] initWithArrangedSubviews:@[self.loginTabButton, self.registerTabButton]];
    tabs.axis = UILayoutConstraintAxisHorizontal;
    tabs.distribution = UIStackViewDistributionFillEqually;
    tabs.spacing = 8;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self logoView], [self titleLabelView], tabs,
        self.userIDField, self.passwordField, self.nicknameField, self.registerHintLabel, self.errorLabel,
        self.loginButton, self.registerButton, self.devButton, self.hostToggleButton, self.hostField, self.agreeFooter
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:8 afterView:self.errorLabel];
    [self.view addSubview:stack];
    self.mainStack = stack;
    [self setupTwoStepView];
    [self applyMode];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24],
    ]];
    self.stackTopConstraint = [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:32];
    self.stackTopConstraint.active = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

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

- (void)loginTabTapped { if (self.registerMode) { self.registerMode = NO; [self applyMode]; } }
- (void)registerTabTapped { if (!self.registerMode) { self.registerMode = YES; [self applyMode]; } }

/// 按当前页签显隐控件并刷新页签选中态（选中 accentSoft 底 + accent 字，未选中卡片底 + 次要字）。
- (void)applyMode {
    BOOL reg = self.registerMode;
    // 括号里的格式说明只在注册页签需要；登录页签占位 = 「用户名或邮箱」（EMAIL_LOGIN_DESIGN §2.4；注册页不接受邮箱，仍用用户名规则）。
    // 键盘保持 ASCIICapable（含 @）；登录名原样发送，规范化（大小写 / 空白）在服务端。
    self.userIDField.placeholder = IMLocalized(reg ? @"login.username.placeholder" : @"login.identifier.label");
    self.passwordField.placeholder = IMLocalized(reg ? @"login.password.placeholder" : @"login.password");
    self.nicknameField.hidden = !reg;
    self.registerHintLabel.hidden = !reg;
    self.registerButton.hidden = !reg;
    self.loginButton.hidden = reg;
#ifdef DEBUG
    self.devButton.hidden = reg;
#endif
    [self styleTab:self.loginTabButton selected:!reg];
    [self styleTab:self.registerTabButton selected:reg];
}

- (void)styleTab:(UIButton *)button selected:(BOOL)selected {
    UIButtonConfiguration *config = button.configuration;
    config.baseBackgroundColor = selected ? IMTheme.accentSoft : UIColor.secondarySystemGroupedBackgroundColor;
    config.baseForegroundColor = selected ? IMTheme.accent : UIColor.secondaryLabelColor;
    config.background.cornerRadius = 10;
    config.background.backgroundColor = config.baseBackgroundColor;
    button.configuration = config;
}

- (void)hostToggleTapped {
    self.hostField.hidden = !self.hostField.hidden;
    [self refreshHostToggleTitle];
}

- (void)refreshHostToggleTitle {
    NSString *host = [self trimmed:self.hostField.text];
    NSString *title = self.hostField.hidden ? IMLocalizedFormat(@"login.server_summary", host) : IMLocalized(@"login.server_address");
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.baseForegroundColor = UIColor.secondaryLabelColor;
    self.hostToggleButton.configuration = config;
    // 必须走 setTitle:——buttonTitle: 里设过的空串会覆盖 configuration.title
    [self.hostToggleButton setTitle:title forState:UIControlStateNormal];
    [self.hostToggleButton invalidateIntrinsicContentSize];
}

#pragma mark - 同意提示（隐式同意，批②）

/// 不可编辑/不可滚动的 UITextView：两段链接可点，走应用内浏览器。无勾选框——点「登录/注册」即视为同意（见 ABOUT_LEGAL_DESIGN §0 批②）。
- (UITextView *)buildAgreeFooter {
    UITextView *tv = [UITextView new];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.scrollEnabled = NO;
    tv.editable = NO;
    tv.backgroundColor = UIColor.clearColor;
    tv.textContainerInset = UIEdgeInsetsZero;
    tv.textContainer.lineFragmentPadding = 0;
    tv.delegate = self;
    tv.accessibilityIdentifier = @"login.agree_footer";
    tv.linkTextAttributes = @{ NSForegroundColorAttributeName: IMTheme.accent };
    tv.attributedText = [self agreeFooterText];
    return tv;
}

/// 「继续即表示同意《服务条款》和《隐私政策》」：复用 about.terms / about.privacy_policy 作链接文案；
/// 中文的《》在格式串里，链接范围只覆盖文字本身。链接值用自定义 scheme，点击分流到对应法务页。
- (NSAttributedString *)agreeFooterText {
    NSString *terms = IMLocalized(@"about.terms");
    NSString *privacy = IMLocalized(@"about.privacy_policy");
    NSString *full = [NSString stringWithFormat:IMLocalized(@"about.agree_footer"), terms, privacy];
    NSMutableParagraphStyle *para = [NSMutableParagraphStyle new];
    para.alignment = NSTextAlignmentCenter;
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:full attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:13],
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
        NSParagraphStyleAttributeName: para,
    }];
    [self linkify:s label:terms url:@"imlegal://terms"];
    [self linkify:s label:privacy url:@"imlegal://privacy"];
    return s;
}

- (void)linkify:(NSMutableAttributedString *)s label:(NSString *)label url:(NSString *)url {
    NSRange r = [s.string rangeOfString:label];
    if (r.location != NSNotFound) { [s addAttribute:NSLinkAttributeName value:[NSURL URLWithString:url] range:r]; }
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)range interaction:(UITextItemInteraction)interaction {
    NSString *path = [URL.host isEqualToString:@"terms"] ? IMLegalPathTerms
                   : [URL.host isEqualToString:@"privacy"] ? IMLegalPathPrivacy : nil;
    if (path) { [self openLegalPath:path]; }
    return NO; // 自己用 SFSafariViewController 呈现，不交给系统
}

/// 用登录页当前填写的服务器地址拼法务页链接并在应用内浏览器打开（法务页是公开静态页，不带 token / Cookie）。
- (void)openLegalPath:(NSString *)path {
    NSString *raw = [self trimmed:self.hostField.text];
    NSString *scheme = nil, *host = nil;
    if (raw.length == 0 || ![IMServerEndpoint parseInput:raw scheme:&scheme host:&host]) {
        [self showError:IMLocalized(@"login.error.host_required")];
        return;
    }
    // 用用户此刻填的 scheme/host 匿名拉一次后台配置的链接（失败 / 老服务端回退内置路径）；
    // 同样**不改**全局 IMServerEndpoint——真正提交地址在点登录/注册时才发生。
    NSString *field = [path isEqualToString:IMLegalPathTerms] ? IMAboutLinkFieldTerms : IMAboutLinkFieldPrivacy;
    __weak typeof(self) weakSelf = self;
    [IMAboutLinks.shared refreshWithScheme:scheme host:host token:nil timeout:5 completion:^(BOOL ok) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.presentedViewController) { return; } // 5s 内连点会叠出多个 Safari
        NSDictionary *links = [IMAboutLinks.shared cachedLinksForScheme:scheme host:host];
        NSURL *url = [IMAboutLinks URLForField:field links:links host:host scheme:scheme language:IMLocalization.shared.language];
        if (!url) {
            IMLogWarnWithTag(IMLogTagUI, @"login_legal_open_failed path=%@", path);
            [self showError:IMLocalized(@"about.open_failed")];
            return;
        }
        [self presentViewController:[[SFSafariViewController alloc] initWithURL:url] animated:YES completion:nil];
    }];
}

#pragma mark - 交互

/// 登录：带密码做真账号校验，成功才进主界面；失败把服务端文案显示在登录页（不深入 App 再报错）。
- (void)loginTapped {
    NSString *host = [self resolvedHostOrShowError];
    if (host.length == 0) { return; }
    NSString *userID = [self trimmed:self.userIDField.text];
    NSString *password = self.passwordField.text ?: @"";
    if (userID.length == 0 || password.length == 0) {
        [self showError:IMLocalized(@"login.error.fill_credentials")];
        return;
    }
    [self loginWithHost:host username:userID password:password fallback:IMLocalized(@"login.error.login_failed") activeButton:self.loginButton];
}

/// 注册并登录：先注册账号，成功后用同一密码进入。
- (void)registerTapped {
    NSString *host = [self resolvedHostOrShowError];
    if (host.length == 0) { return; }
    NSString *username = [self trimmed:self.userIDField.text];
    NSString *nickname = [self trimmed:self.nicknameField.text];
    NSString *password = self.passwordField.text ?: @"";
    if (username.length == 0 || password.length < 6) {
        [self showError:IMLocalized(@"login.error.register_requirements")];
        return;
    }
    // 昵称必填：全端显示名回退链止于它，留空会让界面露出 10 位数字内部 ID。
    // 后端也会拒，这里前置提示省一次往返。
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
            [self showError:error.localizedDescription ?: IMLocalized(@"login.error.register_failed")];
            return;
        }
        // 注册接口不签发 token，也不回内部 ID 之外的东西——必须再登录一次拿 token + 内部 ID。
        [self loginWithHost:host username:username password:password
                   fallback:IMLocalized(@"login.error.register_login_failed") activeButton:self.registerButton];
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
    [self loginWithHost:host username:userID password:@"" fallback:IMLocalized(@"login.error.dev_login_failed") activeButton:self.devButton];
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
            if (error.code == IMErrCodeAccountPendingDeletion && password.length == 0) {
                // 免密路径没有密码可交给 /account/restore：给本地化指引，不显示服务端英文原文
                [self showError:IMLocalized(@"err.200005")];
                return;
            }
            NSString *ticket = error.userInfo[IMErrorTwoStepTicketKey];
            if (error.code == IMErrCodeTwoStepRequired && ticket.length > 0) {
                [self beginTwoStepWithTicket:ticket host:host username:username];
                return;
            }
            if (error.code == IMErrCodeAccountPendingDeletion) {
                [self promptRestoreForHost:host username:username password:password fallback:fallback
                              activeButton:activeButton deleteAt:error.userInfo[IMErrorDeleteAtKey]];
                return;
            }
            [self showError:error.localizedDescription.length > 0 ? error.localizedDescription : fallback];
            return;
        }
        [self enterAppWithHost:host userID:userID username:username];
    }];
}

/// 冷静期内登录（AccountPendingDeletion）：弹「恢复账号」确认；确认后调 restore，成功再按原凭据继续登录。
/// 取消则留在登录页、不留红字（用户是主动选择不恢复）。
- (void)promptRestoreForHost:(NSString *)host
                    username:(NSString *)username
                    password:(NSString *)password
                    fallback:(NSString *)fallback
                activeButton:(UIButton *)activeButton
                    deleteAt:(nullable NSDate *)deleteAt {
    // 服务端没给 delete_at 时不渲染「-」占位日期（Android / Web 同口径：退回标题文案）
    NSString *message = deleteAt ? IMLocalizedFormat(@"delete_account.restore_message", IMDeleteAtDisplayString(deleteAt))
                                 : IMLocalized(@"delete_account.restore_title");
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"delete_account.restore_title")
                                                                message:message preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"delete_account.restore_action") style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [weakSelf restoreThenLoginHost:host username:username password:password fallback:fallback activeButton:activeButton];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)restoreThenLoginHost:(NSString *)host username:(NSString *)username password:(NSString *)password
                    fallback:(NSString *)fallback activeButton:(UIButton *)activeButton {
    [self setBusy:YES activeButton:activeButton];
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService restoreAccountWithUsername:username password:password completion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) {
            [self setBusy:NO activeButton:activeButton];
            [self showError:error.localizedDescription.length > 0 ? error.localizedDescription : fallback];
            return;
        }
        [self loginWithHost:host username:username password:password fallback:fallback activeButton:activeButton];
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

#pragma mark - 两步验证二步页（同页切换）

- (void)setupTwoStepView {
    self.twoStepView = [IMLoginTwoStepView new];
    self.twoStepView.hidden = YES;
    __weak typeof(self) ws = self;
    self.twoStepView.onSubmit = ^(NSString *code, BOOL recovery) { [ws submitTwoStepCode:code recovery:recovery]; };
    self.twoStepView.onBack = ^{ [ws leaveTwoStep]; };
    [self.mainStack addArrangedSubview:self.twoStepView];
}

/// 密码对且账号已开启两步验证（200020）：登录页换成二步页，ticket 只留内存。
- (void)beginTwoStepWithTicket:(NSString *)ticket host:(NSString *)host username:(NSString *)username {
    self.twoStepTicket = ticket;
    self.twoStepHost = host;
    self.twoStepUsername = username;
    NSMutableArray<UIView *> *visible = [NSMutableArray array];
    for (UIView *v in self.mainStack.arrangedSubviews) {
        if (v == self.twoStepView || v.hidden) { continue; }
        [visible addObject:v];
        v.hidden = YES;
    }
    self.viewsHiddenForTwoStep = visible;
    [self showError:@""];
    [self.twoStepView resetForNewTicket];
    self.twoStepView.hidden = NO;
    [self.twoStepView focusInput];
    IMLogUI(@"login_twostep_begin");
}

/// 离开二步页（返回 / ticket 失效）：丢弃 ticket 与内存里的密码，恢复进入前的控件。
- (void)leaveTwoStep {
    self.twoStepTicket = nil;
    IMHTTPService.sharedService.password = nil;
    [self.twoStepView resetForNewTicket];
    [self.view endEditing:YES];
    self.twoStepView.hidden = YES;
    for (UIView *v in self.viewsHiddenForTwoStep) { v.hidden = NO; }
    self.viewsHiddenForTwoStep = @[];
    self.stackTopConstraint.constant = 32;
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
            NSString *host = self.twoStepHost, *username = self.twoStepUsername;
            self.twoStepTicket = nil;
            IMLogUI(@"login_twostep_ok method=%@", recovery ? @"recovery" : @"totp");
            [self enterAppWithHost:host userID:userID username:username];
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
    if (action == IMTwoStepLoginActionExpired) { // ticket 已作废：回密码页
        [self leaveTwoStep];
        [self showError:msg];
        return;
    }
    [self.twoStepView showError:msg];
    if (action == IMTwoStepLoginActionRetryCode) { [self.twoStepView clearCodeAndRefocus]; }
}

/// 键盘顶起：二步页的输入框与按钮必须同时在键盘之上可见（小屏也要）。登录页本身没有滚动容器，直接上移整列。
- (void)keyboardWillChange:(NSNotification *)note {
    if (self.twoStepView.hidden) { return; }
    [self.view layoutIfNeeded]; // 刚切到二步页时登录页那一列的高度还没重排，先结算再量，否则整列会多上移一截
    CGRect end = [self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat keyboardTop = MIN(end.origin.y, CGRectGetMaxY(self.view.bounds));
    CGFloat safeTop = self.view.safeAreaLayoutGuide.layoutFrame.origin.y;
    CGFloat baseBottom = safeTop + 32 + self.mainStack.bounds.size.height;
    CGFloat shift = MAX(0, baseBottom - (keyboardTop - 12));
    self.stackTopConstraint.constant = MAX(4, 32 - shift);
    NSTimeInterval d = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:d animations:^{ [self.view layoutIfNeeded]; }];
}

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
