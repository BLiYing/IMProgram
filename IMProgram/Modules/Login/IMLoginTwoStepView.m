//  IMLoginTwoStepView.m

#import "IMLoginTwoStepView.h"
#import "IMTwoStep.h"
#import "IMTwoStepViews.h"
#import "IMLocalization.h"

@interface IMLoginTwoStepView () <UITextFieldDelegate>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UILabel *noRecoveryLabel;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong, readwrite) UITextField *codeField;
@property (nonatomic, strong, readwrite) UITextField *recoveryField;
@property (nonatomic, strong, readwrite) UIButton *submitButton;
@property (nonatomic, assign, readwrite) BOOL recoveryMode;
@end

@implementation IMLoginTwoStepView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self build];
        [self applyMode];
    }
    return self;
}

#pragma mark - 构造

- (UILabel *)label:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.font = font;
    l.textColor = color;
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 0;
    return l;
}

- (UIButton *)plainButton:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
    cfg.baseForegroundColor = color;
    b.configuration = cfg;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)build {
    self.titleLabel = [self label:[UIFont systemFontOfSize:22 weight:UIFontWeightSemibold] color:UIColor.labelColor];
    self.titleLabel.text = IMLocalized(@"twostep.login.title");
    self.titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    self.hintLabel = [self label:[UIFont systemFontOfSize:13] color:UIColor.secondaryLabelColor];

    self.codeField = IMTwoStepMakeCodeField(IMLocalized(@"twostep.field.code"));
    self.codeField.borderStyle = UITextBorderStyleRoundedRect;
    self.codeField.delegate = self;
    [self.codeField addTarget:self action:@selector(codeChanged) forControlEvents:UIControlEventEditingChanged];
    [self.codeField.heightAnchor constraintEqualToConstant:56].active = YES;

    self.recoveryField = IMTwoStepMakeRecoveryField(@"xxxxx-xxxxx");
    self.recoveryField.borderStyle = UITextBorderStyleRoundedRect;
    self.recoveryField.delegate = self;
    self.recoveryField.accessibilityLabel = IMLocalized(@"twostep.field.recovery");
    [self.recoveryField addTarget:self action:@selector(recoveryChanged) forControlEvents:UIControlEventEditingChanged];
    [self.recoveryField.heightAnchor constraintEqualToConstant:44].active = YES;

    self.errorLabel = [self label:[UIFont systemFontOfSize:13] color:UIColor.systemRedColor];
    self.errorLabel.hidden = YES;
    self.errorLabel.accessibilityIdentifier = @"twostep.login.error";

    self.submitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.submitButton.configuration = [UIButtonConfiguration filledButtonConfiguration];
    [self.submitButton setTitle:IMLocalized(@"twostep.login.submit") forState:UIControlStateNormal];
    [self.submitButton addTarget:self action:@selector(submitTapped) forControlEvents:UIControlEventTouchUpInside];
    self.submitButton.accessibilityIdentifier = @"twostep.login.submit";

    self.toggleButton = [self plainButton:@"" color:UIColor.systemBlueColor action:@selector(toggleTapped)];
    self.toggleButton.accessibilityIdentifier = @"twostep.login.toggle";
    self.noRecoveryLabel = [self label:[UIFont systemFontOfSize:13] color:UIColor.tertiaryLabelColor];
    self.noRecoveryLabel.text = IMLocalized(@"twostep.login.no_recovery");
    self.backButton = [self plainButton:IMLocalized(@"twostep.login.back") color:UIColor.secondaryLabelColor action:@selector(backTapped)];
    self.backButton.accessibilityIdentifier = @"twostep.login.back";

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.titleLabel, self.hintLabel, self.codeField, self.recoveryField, self.errorLabel,
        self.submitButton, self.toggleButton, self.noRecoveryLabel, self.backButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)applyMode {
    BOOL rec = self.recoveryMode;
    self.hintLabel.text = IMLocalized(rec ? @"twostep.login.hint_recovery" : @"twostep.login.hint");
    self.codeField.hidden = rec;
    self.recoveryField.hidden = !rec;
    self.submitButton.hidden = !rec; // 动态码输满自动提交，不需要按钮
    [self.toggleButton setTitle:IMLocalized(rec ? @"twostep.use_code" : @"twostep.use_recovery") forState:UIControlStateNormal];
}

#pragma mark - 对外

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.codeField.enabled = !busy;
    self.recoveryField.enabled = !busy;
    self.toggleButton.enabled = !busy;
    self.backButton.enabled = !busy;
    self.submitButton.enabled = !busy;
    UIButtonConfiguration *cfg = self.submitButton.configuration;
    cfg.showsActivityIndicator = busy;
    self.submitButton.configuration = cfg;
}

- (void)showError:(NSString *)message {
    self.errorLabel.text = message;
    self.errorLabel.hidden = message.length == 0;
}

- (void)resetForNewTicket {
    self.recoveryMode = NO;
    self.codeField.text = @"";
    self.recoveryField.text = @"";
    self.busy = NO;
    [self showError:nil];
    [self applyMode];
}

- (void)clearCodeAndRefocus {
    self.codeField.text = @"";
    [self.codeField becomeFirstResponder];
}

- (void)focusInput {
    [(self.recoveryMode ? self.recoveryField : self.codeField) becomeFirstResponder];
}

#pragma mark - 输入

- (void)codeChanged {
    if (!self.codeField.markedTextRange) { // 组词期间不改写文本
        NSString *clean = IMTwoStepSanitizeCode(self.codeField.text);
        if (![clean isEqualToString:self.codeField.text]) { self.codeField.text = clean; }
    }
    if (self.errorLabel.hidden == NO && self.codeField.text.length > 0) { [self showError:nil]; }
    if (IMTwoStepShouldAutoSubmit(self.codeField.text, self.busy)) {
        [self.codeField resignFirstResponder];
        if (self.onSubmit) { self.onSubmit(self.codeField.text, NO); }
    }
}

- (void)recoveryChanged {
    if (!self.errorLabel.hidden) { [self showError:nil]; } // 红字随输入消失；输入本身不清空，归一化只在提交时做
}

- (BOOL)textField:(UITextField *)tf shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (tf != self.recoveryField) { return YES; }
    if (IMTwoStepHandleRecoveryPaste(tf, range, string)) { return NO; }
    return IMTwoStepRecoveryAllowsEdit(tf.text, range, string, tf.markedTextRange != nil);
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    if (tf == self.recoveryField) { [self submitTapped]; }
    return NO;
}

#pragma mark - 动作

- (void)submitTapped {
    if (self.busy) { return; }
    if (self.recoveryMode) {
        if (!IMTwoStepRecoveryIsComplete(self.recoveryField.text)) {
            [self showError:IMLocalized(@"twostep.error.code_invalid_short")]; // 长度不对没必要打服务端
            return;
        }
        [self.recoveryField resignFirstResponder];
        if (self.onSubmit) { self.onSubmit(IMTwoStepNormalizeRecovery(self.recoveryField.text), YES); }
    } else if (IMTwoStepCodeIsComplete(self.codeField.text) && self.onSubmit) {
        self.onSubmit(self.codeField.text, NO);
    }
}

- (void)toggleTapped {
    self.recoveryMode = !self.recoveryMode;
    (self.recoveryMode ? self.codeField : self.recoveryField).text = @"";
    [self showError:nil];
    [self applyMode];
    [self focusInput];
}

- (void)backTapped {
    if (!self.busy && self.onBack) { self.onBack(); }
}

@end
