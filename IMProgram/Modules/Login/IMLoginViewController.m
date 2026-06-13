//  IMLoginViewController.m

#import "IMLoginViewController.h"
#import "IMChatViewController.h"

static NSString * const kIMDefaultHost = @"localhost:8080";

@interface IMLoginViewController ()
@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UITextField *userIDField;
@property (nonatomic, strong) UITextField *peerIDField;
@end

@implementation IMLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IMProgram 登录";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self setupUI];
}

- (void)setupUI {
    self.hostField   = [self fieldWithPlaceholder:@"服务器地址 host:port" text:kIMDefaultHost keyboard:UIKeyboardTypeURL];
    self.userIDField = [self fieldWithPlaceholder:@"我的 uid" text:@"1001" keyboard:UIKeyboardTypeNumberPad];
    self.peerIDField = [self fieldWithPlaceholder:@"对方 uid" text:@"1002" keyboard:UIKeyboardTypeNumberPad];

    UIButton *enterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    enterButton.translatesAutoresizingMaskIntoConstraints = NO;
    enterButton.configuration = [UIButtonConfiguration filledButtonConfiguration];
    [enterButton setTitle:@"连接并进入聊天" forState:UIControlStateNormal];
    [enterButton addTarget:self action:@selector(enterTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.hostField, self.userIDField, self.peerIDField, enterButton
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
    NSString *peerID = [self trimmed:self.peerIDField.text];
    if (host.length == 0 || userID.length == 0 || peerID.length == 0) {
        [self showAlert:@"请填写服务器地址、我的 uid 与对方 uid"];
        return;
    }
    if ([userID isEqualToString:peerID]) {
        [self showAlert:@"我的 uid 与对方 uid 不能相同"];
        return;
    }
    IMChatViewController *chat = [[IMChatViewController alloc] initWithHost:host userID:userID peerID:peerID];
    [self.navigationController pushViewController:chat animated:YES];
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
