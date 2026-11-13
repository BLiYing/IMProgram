//  IMLoginSubpageViews.m

#import "IMLoginSubpageViews.h"
#import "IMLocalization.h"

static UILabel *IMLoginSubLabel(UIFont *font, UIColor *color) {
    UILabel *l = [UILabel new];
    l.font = font;
    l.textColor = color;
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 0;
    return l;
}

static UITextField *IMLoginSubField(NSString *placeholder, BOOL secure) {
    UITextField *f = [UITextField new];
    f.borderStyle = UITextBorderStyleRoundedRect;
    f.placeholder = placeholder;
    f.font = [UIFont systemFontOfSize:17];
    f.secureTextEntry = secure;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    if (secure) { f.textContentType = UITextContentTypeNewPassword; }
    [f.heightAnchor constraintEqualToConstant:44].active = YES;
    return f;
}

static UIButton *IMLoginSubButton(NSString *title, BOOL filled, id target, SEL action) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = filled ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration plainButtonConfiguration];
    if (!filled) { cfg.baseForegroundColor = UIColor.secondaryLabelColor; }
    b.configuration = cfg;
    [b setTitle:title forState:UIControlStateNormal];
    if (!filled) { b.titleLabel.font = [UIFont systemFontOfSize:15]; }
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

static void IMLoginSubSetBusy(UIButton *button, BOOL busy) {
    UIButtonConfiguration *cfg = button.configuration;
    cfg.showsActivityIndicator = busy;
    button.configuration = cfg;
    button.enabled = !busy;
}

static void IMLoginSubPin(UIView *host, UIStackView *stack) {
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:host.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:host.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
    ]];
}

#pragma mark - 完善资料

@interface IMLoginCompleteProfileView () <UITextFieldDelegate>
@property (nonatomic, strong) UILabel *verifiedLabel;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong, readwrite) UITextField *nicknameField;
@property (nonatomic, strong, readwrite) UIButton *submitButton;
@end

@implementation IMLoginCompleteProfileView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *title = IMLoginSubLabel([UIFont systemFontOfSize:22 weight:UIFontWeightSemibold], UIColor.labelColor);
        title.text = IMLocalized(@"register.complete.title");
        title.accessibilityTraits = UIAccessibilityTraitHeader;
        self.verifiedLabel = IMLoginSubLabel([UIFont systemFontOfSize:13], UIColor.secondaryLabelColor);
        self.verifiedLabel.accessibilityIdentifier = @"complete.verified";
        UILabel *hint = IMLoginSubLabel([UIFont systemFontOfSize:13], UIColor.secondaryLabelColor);
        hint.text = IMLocalized(@"register.complete.hint");
        self.nicknameField = IMLoginSubField(IMLocalized(@"login.nickname.placeholder"), NO);
        self.nicknameField.accessibilityIdentifier = @"complete.nickname";
        self.nicknameField.textContentType = UITextContentTypeNickname;
        self.nicknameField.returnKeyType = UIReturnKeyDone;
        self.nicknameField.delegate = self;
        [self.nicknameField addTarget:self action:@selector(edited) forControlEvents:UIControlEventEditingChanged];
        self.errorLabel = IMLoginSubLabel([UIFont systemFontOfSize:13], UIColor.systemRedColor);
        self.errorLabel.hidden = YES;
        self.errorLabel.accessibilityIdentifier = @"complete.error";
        self.submitButton = IMLoginSubButton(IMLocalized(@"register.complete.submit"), YES, self, @selector(submitTapped));
        self.submitButton.accessibilityIdentifier = @"complete.submit";
        self.backButton = IMLoginSubButton(IMLocalized(@"login.back_to_login"), NO, self, @selector(backTapped));
        self.backButton.accessibilityIdentifier = @"complete.back";
        IMLoginSubPin(self, [[UIStackView alloc] initWithArrangedSubviews:@[
            title, self.verifiedLabel, hint, self.nicknameField, self.errorLabel, self.submitButton, self.backButton]]);
    }
    return self;
}

- (void)resetWithMaskedPhone:(NSString *)maskedPhone {
    self.verifiedLabel.text = IMLocalizedFormat(@"register.complete.verified", maskedPhone);
    self.nicknameField.text = @"";
    [self showError:nil];
    self.busy = NO;
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    IMLoginSubSetBusy(self.submitButton, busy);
    self.nicknameField.enabled = !busy;
    self.backButton.enabled = !busy;
}

- (void)showError:(NSString *)message {
    self.errorLabel.text = message;
    self.errorLabel.hidden = message.length == 0;
}

- (void)edited { if (!self.errorLabel.hidden) { [self showError:nil]; } }

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [self submitTapped]; return NO; }

- (void)submitTapped {
    if (self.busy) { return; }
    NSString *nick = [self.nicknameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (nick.length == 0) { [self showError:IMLocalized(@"login.error.nickname_required")]; return; }
    if (self.onSubmit) { self.onSubmit(nick); }
}

- (void)backTapped { if (!self.busy && self.onBack) { self.onBack(); } }

@end

#pragma mark - 重设密码

@interface IMLoginResetPasswordView () <UITextFieldDelegate>
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong, readwrite) IMLoginPhoneFields *phoneFields;
@property (nonatomic, strong, readwrite) UITextField *passwordField;
@property (nonatomic, strong, readwrite) UITextField *confirmField;
@property (nonatomic, strong, readwrite) UIButton *submitButton;
@end

@implementation IMLoginResetPasswordView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *title = IMLoginSubLabel([UIFont systemFontOfSize:22 weight:UIFontWeightSemibold], UIColor.labelColor);
        title.text = IMLocalized(@"reset.title");
        title.accessibilityTraits = UIAccessibilityTraitHeader;
        self.phoneFields = [[IMLoginPhoneFields alloc] initWithIdentifierPrefix:@"reset"];
        __weak typeof(self) ws = self;
        self.phoneFields.onEdit = ^{ [ws edited]; };
        self.passwordField = IMLoginSubField(IMLocalized(@"reset.new_password"), YES);
        self.passwordField.accessibilityIdentifier = @"reset.new_password";
        self.confirmField = IMLoginSubField(IMLocalized(@"reset.confirm_password"), YES);
        self.confirmField.accessibilityIdentifier = @"reset.confirm_password";
        self.confirmField.returnKeyType = UIReturnKeyDone;
        for (UITextField *f in @[self.passwordField, self.confirmField]) {
            f.delegate = self;
            [f addTarget:self action:@selector(edited) forControlEvents:UIControlEventEditingChanged];
        }
        UILabel *footer = IMLoginSubLabel([UIFont systemFontOfSize:13], UIColor.secondaryLabelColor);
        footer.text = IMLocalized(@"reset.footer");
        self.errorLabel = IMLoginSubLabel([UIFont systemFontOfSize:13], UIColor.systemRedColor);
        self.errorLabel.hidden = YES;
        self.errorLabel.accessibilityIdentifier = @"reset.error";
        self.submitButton = IMLoginSubButton(IMLocalized(@"reset.title"), YES, self, @selector(submitTapped));
        self.submitButton.accessibilityIdentifier = @"reset.submit";
        self.backButton = IMLoginSubButton(IMLocalized(@"login.back_to_login"), NO, self, @selector(backTapped));
        self.backButton.accessibilityIdentifier = @"reset.back";
        IMLoginSubPin(self, [[UIStackView alloc] initWithArrangedSubviews:@[
            title, self.phoneFields, self.passwordField, self.confirmField, footer, self.errorLabel, self.submitButton, self.backButton]]);
    }
    return self;
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    IMLoginSubSetBusy(self.submitButton, busy);
    self.backButton.enabled = !busy;
    for (UITextField *f in @[self.phoneFields.phoneField, self.phoneFields.codeField, self.passwordField, self.confirmField]) { f.enabled = !busy; }
}

- (void)showError:(NSString *)message {
    self.errorLabel.text = message;
    self.errorLabel.hidden = message.length == 0;
}

- (void)resetPasswords {
    self.passwordField.text = @"";
    self.confirmField.text = @"";
    [self showError:nil];
    self.busy = NO;
}

- (void)edited { if (!self.errorLabel.hidden) { [self showError:nil]; } }

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.passwordField) { [self.confirmField becomeFirstResponder]; } else { [self submitTapped]; }
    return NO;
}

- (void)submitTapped { if (!self.busy && self.onSubmit) { self.onSubmit(); } }
- (void)backTapped { if (!self.busy && self.onBack) { self.onBack(); } }

@end
