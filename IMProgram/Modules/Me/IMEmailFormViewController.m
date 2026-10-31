//  IMEmailFormViewController.m

#import "IMEmailFormViewController.h"
#import "IMEmailCodeViewController.h"
#import "IMEmailViews.h"
#import "IMTwoStepViews.h"
#import "IMHTTPService+Email.h"
#import "IMLocalization.h"
#import "IMLog.h"

@interface IMEmailFormViewController () <UITextFieldDelegate>
@property (nonatomic, assign) BOOL change;
@property (nonatomic, copy, nullable) NSString *currentEmail;
@property (nonatomic, strong, readwrite) UITextField *emailField;
@property (nonatomic, strong, readwrite) UITextField *passwordField;
@property (nonatomic, strong) UIView *emailRow;
@property (nonatomic, strong) UIView *passwordRow;
@property (nonatomic, assign) BOOL pushedCodePage; ///< 推过验证码页：回来时清空密码（保留邮箱）
@end

@implementation IMEmailFormViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID change:(BOOL)change currentEmail:(NSString *)currentEmail {
    self = [super initWithHost:host userID:userID];
    if (self) { _change = change; _currentEmail = [currentEmail copy]; }
    return self;
}

- (NSString *)pageTitle { return IMLocalized(self.change ? @"email.action.change" : @"email.action.bind"); }
- (NSString *)primaryTitle { return IMLocalized(@"email.action.send_code"); }
- (BOOL)primaryEnabled { return IMEmailTrim(self.emailField.text).length > 0 && self.passwordField.text.length > 0; }

- (void)viewDidLoad {
    self.emailField = IMEmailMakeField(IMLocalized(@"email.field.email"));
    self.emailField.delegate = self;
    [self.emailField addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
    self.emailRow = IMTwoStepFieldRow(self.emailField, 44);
    self.passwordField = IMTwoStepMakePasswordField(IMLocalized(@"email.field.password"));
    self.passwordField.delegate = self;
    self.passwordField.returnKeyType = UIReturnKeySend;
    [self.passwordField addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
    self.passwordRow = IMTwoStepFieldRow(self.passwordField, 44);
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.pushedCodePage) { // 从验证码页回来（「更换邮箱」/ 返回）：保留邮箱，清空密码
        self.pushedCodePage = NO;
        self.passwordField.text = @"";
        [self refreshPrimary];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.emailField.isFirstResponder && !self.passwordField.isFirstResponder) {
        [(self.emailField.text.length == 0 ? self.emailField : self.passwordField) becomeFirstResponder];
    }
}

- (NSArray<IMTwoStepSection *> *)buildSections {
    return @[[IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:self.emailRow onTap:nil],
                                                 [IMTwoStepRow rowWithView:self.passwordRow onTap:nil]]
                                        footer:IMLocalized(self.change ? @"email.change.footer" : @"email.bind.footer")]];
}

- (void)fieldChanged {
    if (!self.errorLabel.hidden) { [self showError:nil]; } // 重新给一次机会，不清空输入
    [self refreshPrimary];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.emailField) { [self.passwordField becomeFirstResponder]; return NO; }
    if (self.primaryButton.enabled) { [self primaryButtonTapped]; }
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    dispatch_async(dispatch_get_main_queue(), ^{ [self scrollPrimaryButtonIntoView]; });
}

#pragma mark - 提交

- (void)primaryTapped {
    NSString *email = IMEmailTrim(self.emailField.text);
    NSString *password = self.passwordField.text ?: @"";
    [self showError:nil];
    if (!IMEmailPrecheck(email)) { // 不发请求；按钮保持可点
        [self showError:IMEmailErrorMessage(IMErrCodeEmailInvalid, -1, -1, nil)];
        [self markErrorView:self.emailRow];
        return;
    }
    self.busy = YES;
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token) {
        [IMHTTPService.sharedService sendEmailCodeWithToken:token email:email password:password
                                                 completion:^(IMEmailSendResult *result, NSError *error) {
            [ws handleSend:result error:error email:email password:password];
        }];
    }];
}

- (void)handleSend:(nullable IMEmailSendResult *)result error:(nullable NSError *)error email:(NSString *)email password:(NSString *)password {
    self.busy = NO;
    if (result) {
        IMLogUI(@"email_code_sent mode=%@ email=%@", self.change ? @"change" : @"bind", IMEmailMasked(email));
        self.pushedCodePage = YES;
        self.passwordField.text = @""; // 密码只交给验证码页（重发要用），本页不再持有
        [self refreshPrimary];
        NSDate *deadline = IMEmailResendDeadline(result.resendAfter, [NSDate date]);
        [self.navigationController pushViewController:[[IMEmailCodeViewController alloc] initWithHost:self.host userID:self.userID
                                                                                                email:email password:password
                                                                                       resendDeadline:deadline]
                                             animated:YES];
        return;
    }
    IMLogWarnWithTag(IMLogTagUI, @"email_send_failed code=%ld email=%@", (long)error.code, IMEmailMasked(email));
    [self showError:IMEmailErrorMessage(error.code, IMEmailAttemptsLeftFromError(error), IMEmailRetryAfterFromError(error),
                                        error.localizedDescription)];
    switch (IMEmailFormTargetForError(error.code)) { // 输入不清空，只描红
        case IMEmailFormTargetEmail: [self markErrorView:self.emailRow]; break;
        case IMEmailFormTargetPassword: [self markErrorView:self.passwordRow]; break;
        default: break;
    }
}

@end
