//  IMProfileEditViewController.m

#import "IMProfileEditViewController.h"
#import "IMHTTPService.h"
#import "IMUserCard.h"
#import "IMTheme.h"
#import "IMLog.h"

@interface IMProfileEditViewController ()
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic, strong) UITextField *nicknameField;
@property (nonatomic, strong) UITextField *avatarField;
@property (nonatomic, strong) UITextField *phoneField;
@property (nonatomic, strong) UITextField *tagsField;
@end

@implementation IMProfileEditViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"编辑资料";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTapped)];

    self.nicknameField = [self fieldWithPlaceholder:@"昵称"];
    self.avatarField = [self fieldWithPlaceholder:@"头像 URL"];
    self.avatarField.keyboardType = UIKeyboardTypeURL;
    self.avatarField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.phoneField = [self fieldWithPlaceholder:@"手机号"];
    self.phoneField.keyboardType = UIKeyboardTypePhonePad;
    self.tagsField = [self fieldWithPlaceholder:@"标签（空格或逗号分隔）"];
    self.tagsField.autocapitalizationType = UITextAutocapitalizationTypeNone;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self labeledRow:@"昵称" field:self.nicknameField],
        [self labeledRow:@"头像 URL" field:self.avatarField],
        [self labeledRow:@"手机号" field:self.phoneField],
        [self labeledRow:@"标签" field:self.tagsField],
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = IMTheme.space4;
    [self.view addSubview:stack];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:IMTheme.space4 * 2],
        [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:IMTheme.space4],
        [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-IMTheme.space4],
    ]];

    [self load];
}

#pragma mark - 构建

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder {
    UITextField *f = [UITextField new];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.placeholder = placeholder;
    f.font = [UIFont systemFontOfSize:16];
    f.textColor = IMTheme.textPrimary;
    f.borderStyle = UITextBorderStyleRoundedRect;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    [f.heightAnchor constraintEqualToConstant:40].active = YES;
    return f;
}

- (UIStackView *)labeledRow:(NSString *)title field:(UITextField *)field {
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = IMTheme.textSecondary;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, field]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = IMTheme.space1;
    return row;
}

#pragma mark - 数据

- (void)load {
    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (token.length == 0) {
            [self showMessage:[NSString stringWithFormat:@"登录失败：%@", error.localizedDescription]];
            return;
        }
        self.token = token;
        [IMHTTPService.sharedService myProfileWithToken:token completion:^(IMUserCard *profile, NSError *err) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !profile) {
                if (err) { [weakSelf showMessage:[NSString stringWithFormat:@"拉取资料失败：%@", err.localizedDescription]]; }
                return;
            }
            self.nicknameField.text = profile.nickname;
            self.avatarField.text = profile.avatarURL;
            self.phoneField.text = profile.phone;
            self.tagsField.text = [profile.tags componentsJoinedByString:@" "];
        }];
    }];
}

- (void)saveTapped {
    if (self.token.length == 0) { [self showMessage:@"尚未登录，请稍候重试"]; return; }
    [self.view endEditing:YES];
    NSArray<NSString *> *tags = [self tagsFromString:self.tagsField.text];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService updateProfileWithToken:self.token
                                               nickname:[self trimmed:self.nicknameField.text]
                                              avatarURL:[self trimmed:self.avatarField.text]
                                                  phone:[self trimmed:self.phoneField.text]
                                                   tags:tags
                                             completion:^(IMUserCard *profile, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        self.navigationItem.rightBarButtonItem.enabled = YES;
        if (error) {
            [self showMessage:[NSString stringWithFormat:@"保存失败：%@", error.localizedDescription]];
            return;
        }
        [self.navigationController popViewControllerAnimated:YES];
    }];
}

/// 标签串按空格/逗号切分，去空白去空项。
- (NSArray<NSString *> *)tagsFromString:(NSString *)s {
    NSCharacterSet *sep = [NSCharacterSet characterSetWithCharactersInString:@" ,，\n\t"];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *raw in [s componentsSeparatedByCharactersInSet:sep]) {
        NSString *t = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (t.length > 0) { [out addObject:t]; }
    }
    return out;
}

- (NSString *)trimmed:(NSString *)s {
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

- (void)showMessage:(NSString *)message {
    IMLog(@"%@", message);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
