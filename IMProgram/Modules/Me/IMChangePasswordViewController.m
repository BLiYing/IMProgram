//  IMChangePasswordViewController.m

#import "IMChangePasswordViewController.h"
#import "IMHTTPService.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"
#import "IMLog.h"
#import <objc/runtime.h>

/// 与后端 errcode 对齐（不引 IMServer 头，硬编码常量集中一处）。
static NSInteger const IMWrongPassword     = 200002;  // 旧密码错
static NSInteger const IMParamInvalid      = 100002;  // 新密度不足（Register 同码）
static NSInteger const IMAccountBanned     = 200003;  // 账号被封
static NSInteger const IMTokenInvalid      = 100101;  // token 无效/过期

@interface IMChangePasswordViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong) UITableView *tableView;

@property (nonatomic, strong) UITextField *oldField;
@property (nonatomic, strong) UITextField *freshField;
@property (nonatomic, strong) UITextField *confirmField;

@property (nonatomic, strong) UIButton *submitButton;
@property (nonatomic, strong) UILabel *errorLabel;         ///< 错误红字（跟随最近一次失败的输入行下方）

@property (nonatomic, assign) BOOL submitting;
@end

@implementation IMChangePasswordViewController

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
    self.title = @"修改密码";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 44;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.allowsSelection = NO;
    [self.view addSubview:self.tableView];

    // 三个输入框（在 cellForRow 里挂到 cell.contentView；这里先建实例并配好属性）。
    self.oldField     = [self makeField:@"旧密码"];
    self.freshField     = [self makeField:@"新密码（≥6 位）"];
    self.confirmField = [self makeField:@"再次输入新密码"];

    // 底部主按钮 + 错误红字：都挂在 tableFooterView 里（跟随 keyboard 布局）。
    UIView *footer = [self buildFooterView];
    self.tableView.tableFooterView = footer;

    // 键盘遮挡：调整 contentInset。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];

    [self refreshSubmitEnabled];
    [self.oldField becomeFirstResponder];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

#pragma mark - 构造

/// 单个密码输入框：密文 + 眼睛切换 + 变更监听。
- (UITextField *)makeField:(NSString *)placeholder {
    UITextField *f = [UITextField new];
    f.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; // 17pt
    f.textColor = UIColor.labelColor;
    f.placeholder = placeholder;
    f.secureTextEntry = YES;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.returnKeyType = UIReturnKeyNext;
    f.delegate = self;
    [f addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    return f;
}

/// 挂在字段右侧的眼睛按钮（明暗切换）。用 rightView 承载，clearButton 位置不冲突。
- (UIButton *)eyeButtonFor:(UITextField *)field {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(0, 0, 34, 34);
    b.tintColor = UIColor.secondaryLabelColor;
    UIImage *eye = [UIImage systemImageNamed:@"eye.fill"];
    UIImage *slash = [UIImage systemImageNamed:@"eye.slash.fill"];
    [b setImage:slash forState:UIControlStateNormal];       // 默认密文=eye.slash
    [b setImage:eye forState:UIControlStateSelected];
    [b addTarget:self action:@selector(eyeTapped:) forControlEvents:UIControlEventTouchUpInside];
    // 保留一个反查引用：sender.tag 保存目标 field 的 hash，回调时找回。
    objc_setAssociatedObject(b, (__bridge const void *)@"field", field, OBJC_ASSOCIATION_ASSIGN);
    return b;
}

- (UIView *)buildFooterView {
    UIView *host = [UIView new];
    host.frame = CGRectMake(0, 0, self.view.bounds.size.width, 130);
    host.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    // 错误红字（默认隐藏，失败时显）——挂靠"新密卡"下方也够近，简化实现（不做逐行贴合）。
    self.errorLabel = [UILabel new];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; // 13pt
    self.errorLabel.textColor = UIColor.systemRedColor;
    self.errorLabel.hidden = YES;
    self.errorLabel.numberOfLines = 0;
    [host addSubview:self.errorLabel];

    UILabel *helper = [UILabel new];
    helper.translatesAutoresizingMaskIntoConstraints = NO;
    helper.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    helper.textColor = UIColor.secondaryLabelColor;
    helper.text = @"新密码至少 6 位，与旧密码不同。";
    helper.numberOfLines = 0;
    [host addSubview:helper];

    self.submitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.submitButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.submitButton.backgroundColor = UIColor.systemBlueColor;
    self.submitButton.layer.cornerRadius = 12;
    [self.submitButton setTitle:@"修改密码" forState:UIControlStateNormal];
    [self.submitButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.submitButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [self.submitButton addTarget:self action:@selector(submitTapped) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:self.submitButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.errorLabel.leadingAnchor  constraintEqualToAnchor:host.leadingAnchor  constant:32],
        [self.errorLabel.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-32],
        [self.errorLabel.topAnchor      constraintEqualToAnchor:host.topAnchor constant:6],

        [helper.leadingAnchor  constraintEqualToAnchor:host.leadingAnchor  constant:32],
        [helper.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-32],
        [helper.topAnchor      constraintEqualToAnchor:self.errorLabel.bottomAnchor constant:6],

        [self.submitButton.leadingAnchor  constraintEqualToAnchor:host.leadingAnchor  constant:16],
        [self.submitButton.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-16],
        [self.submitButton.topAnchor      constraintEqualToAnchor:helper.bottomAnchor constant:20],
        [self.submitButton.heightAnchor   constraintEqualToConstant:50],
    ]];
    return host;
}

#pragma mark - 校验 & 提交

- (BOOL)passesLocalValidation {
    NSString *o = self.oldField.text ?: @"";
    NSString *n = self.freshField.text ?: @"";
    NSString *c = self.confirmField.text ?: @"";
    if (o.length == 0 || n.length == 0 || c.length == 0) { return NO; }
    if (n.length < 6) { return NO; }
    if ([n isEqualToString:o]) { return NO; }
    if (![n isEqualToString:c]) { return NO; }
    return YES;
}

- (void)refreshSubmitEnabled {
    BOOL ok = [self passesLocalValidation] && !self.submitting;
    self.submitButton.enabled = ok;
    self.submitButton.alpha = ok ? 1.0 : 0.5;
}

- (void)fieldChanged:(UITextField *)f {
    // 用户开始改动 → 清红字（重新给一次机会），不清空输入。
    if (!self.errorLabel.hidden) {
        self.errorLabel.hidden = YES;
        [self markFieldError:nil]; // 清红边
    }
    [self refreshSubmitEnabled];
}

- (void)submitTapped {
    // 二次本地校验（防 UI 状态漂移）；具体友好提示：给出第一个不通过的原因。
    NSString *o = self.oldField.text ?: @"", *n = self.freshField.text ?: @"", *c = self.confirmField.text ?: @"";
    if (n.length < 6) {
        [self showLocalError:@"新密码至少 6 位" onField:self.freshField]; return;
    }
    if ([n isEqualToString:o]) {
        [self showLocalError:@"新密码不能与旧密码相同" onField:self.freshField]; return;
    }
    if (![n isEqualToString:c]) {
        [self showLocalError:@"两次输入不一致" onField:self.confirmField]; return;
    }

    self.submitting = YES;
    [self refreshSubmitEnabled];
    [self.submitButton setTitle:@"" forState:UIControlStateNormal];
    UIActivityIndicatorView *spin = [self spinnerOnButton];

    IMHTTPService.sharedService.host = self.host;
    __weak typeof(self) ws = self;
    // 登录一次拿新鲜 token（loginWithUserID 内 10min 缓存，多数命中缓存不触发真登录）。
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *loginErr) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (token.length == 0) {
            [self resetSubmittingWithSpinner:spin];
            [self showLocalError:loginErr.localizedDescription ?: @"登录会话已失效" onField:nil];
            return;
        }
        [IMHTTPService.sharedService changePasswordWithToken:token oldPassword:o newPassword:n
                                                  completion:^(NSError *err) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            [self resetSubmittingWithSpinner:spin];
            if (err == nil) {
                // 成功：pop + 上级 toast（Toast 挂上级 VC 才可见，本 VC 已 pop）。
                UIViewController *back = self.navigationController.viewControllers.count >= 2
                    ? self.navigationController.viewControllers[self.navigationController.viewControllers.count - 2] : nil;
                [self.navigationController popViewControllerAnimated:YES];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [back im_showToast:@"✓ 密码已修改"];
                });
                return;
            }
            [self handleBackendError:err];
        }];
    }];
}

- (void)handleBackendError:(NSError *)err {
    NSInteger code = err.code;
    switch (code) {
        case IMWrongPassword:
            [self showLocalError:@"旧密码错误" onField:self.oldField]; break;
        case IMParamInvalid:
            [self showLocalError:@"密码强度不足（至少 6 位）" onField:self.freshField]; break;
        case IMAccountBanned:
            [self showLocalError:@"账号已被封禁，无法修改密码" onField:nil]; break;
        case IMTokenInvalid:
            [self im_showToast:@"会话已过期，请重新登录"];
            // 保持在本页——用户会自行退出登录；避免这里侵入导航栈。
            break;
        default:
            [self im_showToast:err.localizedDescription ?: @"修改密码失败，请稍后再试"];
            break;
    }
}

- (void)showLocalError:(NSString *)text onField:(nullable UITextField *)field {
    self.errorLabel.text = text;
    self.errorLabel.hidden = NO;
    [self markFieldError:field];
}

- (void)markFieldError:(nullable UITextField *)field {
    for (UITextField *f in @[self.oldField, self.freshField, self.confirmField]) {
        UIView *host = f.superview; // cell.contentView 里的直接父容器
        host.layer.borderWidth = 0;
        host.layer.borderColor = nil;
    }
    if (field) {
        UIView *host = field.superview;
        host.layer.borderWidth = 1.0;
        host.layer.borderColor = UIColor.systemRedColor.CGColor;
        host.layer.cornerRadius = 0; // 直接边框在 cell 里，靠 cell 圆角遮住；不额外圆
    }
}

- (UIActivityIndicatorView *)spinnerOnButton {
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spin.color = UIColor.whiteColor;
    spin.translatesAutoresizingMaskIntoConstraints = NO;
    [self.submitButton addSubview:spin];
    [NSLayoutConstraint activateConstraints:@[
        [spin.centerXAnchor constraintEqualToAnchor:self.submitButton.centerXAnchor],
        [spin.centerYAnchor constraintEqualToAnchor:self.submitButton.centerYAnchor],
    ]];
    [spin startAnimating];
    return spin;
}

- (void)resetSubmittingWithSpinner:(UIActivityIndicatorView *)spin {
    [spin stopAnimating];
    [spin removeFromSuperview];
    self.submitting = NO;
    [self.submitButton setTitle:@"修改密码" forState:UIControlStateNormal];
    [self refreshSubmitEnabled];
}

#pragma mark - 眼睛按钮 / 键盘 / TextField delegate

- (void)eyeTapped:(UIButton *)b {
    b.selected = !b.selected;
    UITextField *f = objc_getAssociatedObject(b, (__bridge const void *)@"field");
    // secureTextEntry 切换后光标位置守护：先短暂 resign 再 become，避免 iOS 光标跳到中间的老 bug。
    BOOL wasFirst = f.isFirstResponder;
    if (wasFirst) { [f resignFirstResponder]; }
    f.secureTextEntry = !b.selected;
    if (wasFirst) { [f becomeFirstResponder]; }
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    if (f == self.oldField)     { [self.freshField becomeFirstResponder]; }
    else if (f == self.freshField){ [self.confirmField becomeFirstResponder]; }
    else                        {
        if (self.submitButton.enabled) { [self submitTapped]; }
    }
    return NO;
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:end fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - converted.origin.y);
    UIEdgeInsets ins = self.tableView.contentInset;
    ins.bottom = overlap;
    self.tableView.contentInset = ins;
    self.tableView.verticalScrollIndicatorInsets = ins;
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"修改后你的所有其它设备将继续保持登录。如果密码可能被泄露，请前往「已登录设备」逐台下线。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const kID = @"pw";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kID];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    UITextField *field = nil;
    if (indexPath.section == 0) {
        field = self.oldField;
    } else {
        field = indexPath.row == 0 ? self.freshField : self.confirmField;
    }
    // 清掉旧 subviews 后重新挂（tableView 复用可能挪 field 到别的 cell）。
    for (UIView *v in cell.contentView.subviews) { [v removeFromSuperview]; }
    // 眼睛按钮：每 cell 独立，配对当前 field。
    UIButton *eye = [self eyeButtonFor:field];
    field.rightView = eye;
    field.rightViewMode = UITextFieldViewModeAlways;

    field.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor  constraintEqualToAnchor:cell.contentView.leadingAnchor  constant:16],
        [field.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [field.topAnchor      constraintEqualToAnchor:cell.contentView.topAnchor],
        [field.bottomAnchor   constraintEqualToAnchor:cell.contentView.bottomAnchor],
    ]];
    return cell;
}

@end
