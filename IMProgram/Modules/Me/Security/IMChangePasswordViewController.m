//  IMChangePasswordViewController.m

#import "IMChangePasswordViewController.h"
#import "IMHTTPService+Phone.h"
#import "IMPhoneAuth.h"
#import "IMSMSCodeField.h"
#import "IMTwoStepViews.h"
#import "IMEmailViews.h"
#import "IMLocalization.h"
#import "IMLog.h"

static NSInteger const kIMAccountBanned = 200003;

@interface IMChangePasswordViewController () <UITextFieldDelegate>
@property (nonatomic, strong, nullable) IMSecurityState *security;
@property (nonatomic, strong, readwrite) UITextField *oldField;
@property (nonatomic, strong, readwrite) UITextField *freshField;
@property (nonatomic, strong, readwrite) UITextField *confirmField;
@property (nonatomic, strong, readwrite) IMSMSCodeField *codeField;
@property (nonatomic, strong) UIView *oldRow, *freshRow, *confirmRow, *codeRow;
@property (nonatomic, assign, readwrite) BOOL usingSMS;
@property (nonatomic, assign) BOOL loadingState;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@end

@implementation IMChangePasswordViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    return [self initWithHost:host userID:userID security:nil];
}

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID security:(IMSecurityState *)security {
    self = [super initWithHost:host userID:userID];
    if (self) { _security = security; }
    return self;
}

- (BOOL)setMode { return IMSecurityPasswordPageIsSet(self.security); }
- (BOOL)proofIsSMS { return IMSecurityPasswordProofMode(self.setMode, self.usingSMS, self.security) == IMPasswordProofModeSMS; }

- (NSString *)pageTitle { return IMLocalized(self.setMode ? @"security.password.set_title" : @"settings.change_password"); }
- (nullable NSString *)primaryTitle {
    if (self.loadingState) { return nil; }
    return IMLocalized(self.setMode ? @"common.done" : @"settings.change_password");
}

- (BOOL)primaryEnabled {
    NSString *n = self.freshField.text ?: @"", *c = self.confirmField.text ?: @"";
    if (n.length == 0 || c.length == 0) { return NO; }
    return [self proofIsSMS] ? IMSMSCodeIsComplete(self.codeField.text) : self.oldField.text.length > 0;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    self.oldField = [self passwordField:@"password.field.old"];
    self.freshField = [self passwordField:@"password.field.new"];
    self.confirmField = [self passwordField:@"password.field.confirm"];
    self.confirmField.returnKeyType = UIReturnKeyDone;
    // 明确标注新 / 旧密码：不标时验证码框 + 两个密文框会被系统当成注册表单，弹「自动生成强密码」盖住输入框。
    self.oldField.textContentType = UITextContentTypePassword;
    self.freshField.textContentType = UITextContentTypeNewPassword;
    self.confirmField.textContentType = UITextContentTypeNewPassword;
    self.codeField = [[IMSMSCodeField alloc] initWithTint:UIColor.systemBlueColor];
    self.codeField.delegate = self;
    self.codeField.accessibilityIdentifier = @"password.code";
    [self.codeField.clock followTarget:@"verify"];
    __weak typeof(self) ws = self;
    self.codeField.onSend = ^{ [ws sendCode]; };
    [self.codeField addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
    self.oldRow = IMTwoStepFieldRow(self.oldField, 44);
    self.freshRow = IMTwoStepFieldRow(self.freshField, 44);
    self.confirmRow = IMTwoStepFieldRow(self.confirmField, 44);
    self.codeRow = IMTwoStepFieldRow(self.codeField, 44);
    self.loadingState = self.security == nil;
    [super viewDidLoad];
    self.loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.tableView.backgroundView = self.loadingSpinner;
    [self loadSecurity];
}

- (UITextField *)passwordField:(NSString *)placeholderKey {
    UITextField *f = IMTwoStepMakePasswordField(IMLocalized(placeholderKey));
    f.delegate = self;
    f.accessibilityIdentifier = placeholderKey;
    [f addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
    return f;
}

/// 入口没给状态（设置搜索直达）：先取，期间不显示表单；取不到按「修改」（改造前的行为）。给了也后台重取一次校正。
- (void)loadSecurity {
    if (self.loadingState) { [self.loadingSpinner startAnimating]; }
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token) {
        [IMHTTPService.sharedService fetchSecurityStateWithToken:token completion:^(IMSecurityState *state, NSError *error) {
            [ws securityLoaded:state];
        }];
    } failure:^(NSError *error) { [ws securityLoaded:nil]; }];
}

- (void)securityLoaded:(nullable IMSecurityState *)state {
    [self.loadingSpinner stopAnimating];
    BOOL wasSet = self.setMode;
    if (state) { self.security = state; }
    BOOL changed = self.loadingState || wasSet != self.setMode;
    self.loadingState = NO;
    if (!IMSecurityCanChangePasswordBySMS(self.security)) { self.usingSMS = NO; }
    if (changed) { [self rebuild]; }
    else { [self reloadSections]; }
}

- (void)rebuild {
    self.title = [self pageTitle];
    [self reloadSections];
    [self refreshPrimary];
    UITextField *first = [self proofIsSMS] ? self.freshField : self.oldField;
    if (!self.presentedViewController) { [first becomeFirstResponder]; }
}

#pragma mark - 渲染

- (NSArray<IMTwoStepSection *> *)buildSections {
    if (self.loadingState) { return @[]; }
    BOOL sms = [self proofIsSMS];
    IMTwoStepSection *proof = [IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:sms ? self.codeRow : self.oldRow onTap:nil]]
                                                         footer:IMLocalized(self.setMode ? @"security.password.set_footer"
                                                                                         : @"password.footer.security_note")];
    if (sms && self.security.phoneMasked.length > 0) { proof.header = IMLocalizedFormat(@"security.code_sent_to", self.security.phoneMasked); }
    // 「与旧密码不同」只在用旧密码修改时说；短信方式（含设置）只说长度。
    NSString *hint = IMLocalized(sms ? @"password.error.min_length" : @"password.helper.min_length_hint");
    IMTwoStepSection *fresh = [IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:self.freshRow onTap:nil],
                                                                  [IMTwoStepRow rowWithView:self.confirmRow onTap:nil]] footer:hint];
    NSMutableArray *sections = [NSMutableArray arrayWithObjects:proof, fresh, nil];
    if (!self.setMode && IMSecurityCanChangePasswordBySMS(self.security)) {
        __weak typeof(self) ws = self;
        UILabel *link = IMEmailLinkLabel(IMLocalized(self.usingSMS ? @"security.password.change_by_password"
                                                                   : @"security.password.change_by_sms"), UIColor.systemBlueColor);
        link.accessibilityIdentifier = @"password.switch_proof";
        IMTwoStepRow *row = [IMTwoStepRow rowWithView:IMEmailLinkRow(link) onTap:^{ [ws toggleProofMode]; }];
        row.transparent = YES;
        [sections addObject:[IMTwoStepSection sectionWithRows:@[row] footer:nil]];
    }
    return sections;
}

- (void)toggleProofMode {
    self.usingSMS = !self.usingSMS;
    self.oldField.text = @"";
    [self showError:nil];
    [self reloadSections];
    [self refreshPrimary];
}

#pragma mark - 输入

- (void)fieldChanged {
    if (!self.errorLabel.hidden) { [self showError:nil]; } // 重新给一次机会，不清空输入
    [self refreshPrimary];
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    if (f == self.oldField || f == self.codeField) { [self.freshField becomeFirstResponder]; }
    else if (f == self.freshField) { [self.confirmField becomeFirstResponder]; }
    else if (self.primaryButton.enabled) { [self primaryButtonTapped]; }
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    dispatch_async(dispatch_get_main_queue(), ^{ [self scrollPrimaryButtonIntoView]; });
}

#pragma mark - 发码

- (void)sendCode {
    [self.codeField beginSending];
    [self showError:nil];
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token) {
        [IMHTTPService.sharedService sendVerifyCodeWithToken:token completion:^(IMSMSSendResult *result, NSError *error) {
            [ws codeSent:result error:error];
        }];
    } failure:^(NSError *error) { [ws codeSent:nil error:error]; }];
}

- (void)codeSent:(nullable IMSMSSendResult *)result error:(nullable NSError *)error {
    NSString *failure = [self.codeField applySendResult:result error:error sameTarget:YES];
    if (result) {
        IMLogUI(@"password_verify_code_sent");
        self.codeField.text = @"";
        if (result.phoneMasked.length > 0 && self.security) { self.security.phoneMasked = result.phoneMasked; [self reloadSections]; }
        [self.codeField becomeFirstResponder];
    } else {
        IMLogWarnWithTag(IMLogTagUI, @"password_verify_code_failed code=%ld", (long)error.code);
        [self showError:failure];
    }
}

#pragma mark - 提交

- (void)primaryTapped {
    BOOL sms = [self proofIsSMS];
    NSString *o = self.oldField.text ?: @"", *n = self.freshField.text ?: @"", *c = self.confirmField.text ?: @"";
    NSString *localKey = IMNewPasswordErrorKey(n, c);
    if (!localKey && !sms && [n isEqualToString:o]) { localKey = @"password.err.same_as_old"; }
    if (localKey) {
        [self showError:IMLocalized(localKey)];
        [self markErrorView:[localKey isEqualToString:@"reset.mismatch"] ? self.confirmRow : self.freshRow];
        return;
    }
    IMIdentityProof *proof = sms ? [IMIdentityProof smsProof:self.codeField.text] : [IMIdentityProof passwordProof:o];
    BOOL wasSet = self.setMode;
    [self showError:nil];
    [self.view endEditing:YES];
    self.busy = YES;
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token) {
        [IMHTTPService.sharedService updatePasswordWithToken:token proof:proof newPassword:n completion:^(NSError *error) {
            [ws finishWithError:error wasSet:wasSet];
        }];
    }];
}

- (void)finishWithError:(nullable NSError *)error wasSet:(BOOL)wasSet {
    self.busy = NO;
    if (!error) {
        IMLogUI(@"password_%@ proof=%@", wasSet ? @"set" : @"changed", [self proofIsSMS] ? @"sms" : @"password");
        self.oldField.text = self.freshField.text = self.confirmField.text = self.codeField.text = @"";
        // 本页不是流程根、栈里也没有流程根：pop 一层，0.35s 后在上一页弹 toast。
        [self popToFlowRootWithToast:IMLocalized(wasSet ? @"security.password.toast_set" : @"password.success_toast")];
        return;
    }
    IMLogWarnWithTag(IMLogTagUI, @"password_update_failed code=%ld", (long)error.code);
    if (error.code == IMErrCodeWrongPassword) {
        [self showError:IMLocalized(@"password.err.wrong_old")];
        [self markErrorView:self.oldRow];
    } else if (error.code == IMErrCodeSMSCodeInvalid || error.code == IMErrCodeSMSCodeExpired) {
        self.codeField.text = @""; // 判错过的码留着无意义
        [self showError:IMSMSSubmitErrorMessage(error.code, IMSMSAttemptsLeftFromError(error), error.localizedDescription)];
        [self markErrorView:self.codeRow];
    } else if (error.code == kIMAccountBanned) {
        [self showError:IMLocalized(@"password.error.account_banned")];
    } else {
        [self showError:IMErrorMessageOrFallback(error, IMLocalized(@"password.error.generic_failed"))];
    }
    [self refreshPrimary];
}

@end
