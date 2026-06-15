//  IMLoginViewController.m

#import "IMLoginViewController.h"
#import "IMMainTabBarController.h"

static NSString * const kIMLastHostKey = @"im_last_host"; // 记住上次用过的 host

@interface IMLoginViewController ()
@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UITextField *userIDField;
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
    self.hostField   = [self fieldWithPlaceholder:@"服务器地址 host:port" text:[self defaultHost] keyboard:UIKeyboardTypeURL];
    self.userIDField = [self fieldWithPlaceholder:@"我的 uid" text:@"1001" keyboard:UIKeyboardTypeNumberPad];

    UIButton *enterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    enterButton.translatesAutoresizingMaskIntoConstraints = NO;
    enterButton.configuration = [UIButtonConfiguration filledButtonConfiguration];
    [enterButton setTitle:@"登录" forState:UIControlStateNormal];
    [enterButton addTarget:self action:@selector(enterTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.hostField, self.userIDField, enterButton
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:40],
    ]];
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text keyboard:(UIKeyboardType)keyboard {
    UITextField *field = [UITextField new];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholder;
    field.text = text;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.keyboardType = keyboard;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [field.heightAnchor constraintEqualToConstant:44].active = YES;
    return field;
}

- (void)enterTapped {
    NSString *host = [self trimmed:self.hostField.text];
    NSString *userID = [self trimmed:self.userIDField.text];
    if (host.length == 0 || userID.length == 0) {
        [self showAlert:@"请填写服务器地址与我的 uid"];
        return;
    }
    [NSUserDefaults.standardUserDefaults setObject:host forKey:kIMLastHostKey]; // 记住，下次免重填
    // 进入主界面（会话列表）。会话列表负责登录换 token + 拉会话。
    IMMainTabBarController *main = [[IMMainTabBarController alloc] initWithHost:host userID:userID];
    self.view.window.rootViewController = main;
}

- (NSString *)trimmed:(NSString *)text {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

- (void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
