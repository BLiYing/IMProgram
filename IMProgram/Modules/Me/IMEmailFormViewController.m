//  IMEmailFormViewController.m

#import "IMEmailFormViewController.h"
#import "IMEmailCodeViewController.h"
#import "IMEmailViews.h"
#import "IMTwoStepViews.h"
#import "IMHTTPService+Email.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMIdentityProofSheet.h"

@interface IMEmailFormViewController () <UITextFieldDelegate>
@property (nonatomic, assign) BOOL change;
@property (nonatomic, copy, nullable) NSString *currentEmail;
@property (nonatomic, strong, readwrite) UITextField *emailField;
@property (nonatomic, strong) UIView *emailRow;
@property (nonatomic, strong, readwrite) IMProofSession *proofSession;
@end

@implementation IMEmailFormViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID change:(BOOL)change currentEmail:(NSString *)currentEmail {
    self = [super initWithHost:host userID:userID];
    if (self) {
        _change = change;
        _currentEmail = [currentEmail copy];
        _proofSession = [[IMProofSession alloc] initWithHost:host userID:userID];
    }
    return self;
}

- (NSString *)pageTitle { return IMLocalized(self.change ? @"email.action.change" : @"email.action.bind"); }
- (NSString *)primaryTitle { return IMLocalized(@"email.action.send_code"); }
- (BOOL)primaryEnabled { return IMEmailTrim(self.emailField.text).length > 0; }

- (void)viewDidLoad {
    self.emailField = IMEmailMakeField(IMLocalized(@"email.field.email"));
    self.emailField.delegate = self;
    self.emailField.returnKeyType = UIReturnKeySend;
    [self.emailField addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
    self.emailRow = IMTwoStepFieldRow(self.emailField, 44);
    [super viewDidLoad];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.emailField.isFirstResponder && !self.presentedViewController) { [self.emailField becomeFirstResponder]; }
}

- (NSArray<IMTwoStepSection *> *)buildSections {
    return @[[IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:self.emailRow onTap:nil]]
                                        footer:IMLocalized(self.change ? @"email.change.footer" : @"email.bind.footer")]];
}

- (void)fieldChanged {
    if (!self.errorLabel.hidden) { [self showError:nil]; } // 重新给一次机会，不清空输入
    [self refreshPrimary];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.primaryButton.enabled) { [self primaryButtonTapped]; }
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    dispatch_async(dispatch_get_main_queue(), ^{ [self scrollPrimaryButtonIntoView]; });
}

#pragma mark - 提交

/// 预检邮箱 → 确认身份弹层（密码或短信验证码，PHONE_AUTH_DESIGN §7）→ send-code。
/// 证明本身的错留在弹层里；邮箱不合规 / 已被占用 / 限流等交给本页（验证码不会被用掉，下次预填）。
- (void)primaryTapped {
    NSString *email = IMEmailTrim(self.emailField.text);
    [self showError:nil];
    if (!IMEmailPrecheck(email)) { // 不发请求；按钮保持可点
        [self showError:IMEmailErrorMessage(IMErrCodeEmailInvalid, -1, -1, nil)];
        [self markErrorView:self.emailRow];
        return;
    }
    __weak typeof(self) ws = self;
    __block IMEmailSendResult *sent = nil;
    __block IMIdentityProof *usedProof = nil;
    [self.proofSession presentFrom:self request:^(NSString *token, IMIdentityProof *proof, void (^finish)(NSError *)) {
        [IMHTTPService.sharedService sendEmailCodeWithToken:token email:email proof:proof
                                                 completion:^(IMEmailSendResult *result, NSError *error) {
            sent = result; usedProof = proof;
            finish(error);
        }];
    } completion:^(BOOL succeeded, NSError *pageError) {
        if (succeeded || pageError) { [ws handleSend:succeeded ? sent : nil error:pageError email:email proof:usedProof]; }
    }];
}

- (void)handleSend:(nullable IMEmailSendResult *)result error:(nullable NSError *)error email:(NSString *)email
             proof:(nullable IMIdentityProof *)proof {
    if (result) {
        IMLogUI(@"email_code_sent mode=%@ email=%@", self.change ? @"change" : @"bind", IMEmailMasked(email));
        NSDate *deadline = IMEmailResendDeadline(result.resendAfter, [NSDate date]);
        // 重发也要证明身份：密码留在验证码页内存里复用；验证码已被这次发信用掉，验证码页 init 自己滤掉、重发时再弹层（共用本页的弹层会话）。
        [self.navigationController pushViewController:[[IMEmailCodeViewController alloc] initWithHost:self.host userID:self.userID
                                                                                                email:email proof:proof
                                                                                         proofSession:self.proofSession
                                                                                       resendDeadline:deadline]
                                             animated:YES];
        return;
    }
    IMLogWarnWithTag(IMLogTagUI, @"email_send_failed code=%ld email=%@", (long)error.code, IMEmailMasked(email));
    [self showError:IMEmailErrorMessage(error.code, IMEmailAttemptsLeftFromError(error), IMEmailRetryAfterFromError(error),
                                        error.localizedDescription)];
    if (IMEmailFormTargetForError(error.code) == IMEmailFormTargetEmail) { [self markErrorView:self.emailRow]; } // 输入不清空，只描红
}

@end
