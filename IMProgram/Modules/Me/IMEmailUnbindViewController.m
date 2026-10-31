//  IMEmailUnbindViewController.m

#import "IMEmailUnbindViewController.h"
#import "IMEmailLoginViewController.h"
#import "IMEmailLogin.h"
#import "IMTwoStepViews.h"
#import "IMHTTPService+Email.h"
#import "IMLocalization.h"
#import "IMLog.h"

@interface IMEmailUnbindViewController () <UITextFieldDelegate>
@property (nonatomic, strong, readwrite) UITextField *passwordField;
@property (nonatomic, strong) UIView *passwordRow;
@end

@implementation IMEmailUnbindViewController

- (NSString *)pageTitle { return IMLocalized(@"email.action.unbind"); }
- (NSString *)primaryTitle { return IMLocalized(@"email.action.unbind"); }
- (UIColor *)primaryColor { return UIColor.systemRedColor; }
- (BOOL)primaryEnabled { return self.passwordField.text.length > 0; }

- (void)viewDidLoad {
    self.passwordField = IMTwoStepMakePasswordField(IMLocalized(@"email.field.password"));
    self.passwordField.delegate = self;
    self.passwordField.returnKeyType = UIReturnKeyContinue;
    [self.passwordField addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
    self.passwordRow = IMTwoStepFieldRow(self.passwordField, 44);
    [super viewDidLoad];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.passwordField.isFirstResponder) { [self.passwordField becomeFirstResponder]; }
}

- (NSArray<IMTwoStepSection *> *)buildSections {
    return @[[IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:self.passwordRow onTap:nil]]
                                        footer:IMLocalized(@"email.unbind.body")]];
}

- (void)fieldChanged {
    if (!self.errorLabel.hidden) { [self showError:nil]; }
    [self refreshPrimary];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.primaryButton.enabled) { [self primaryButtonTapped]; }
    return NO;
}

#pragma mark - 确认 + 提交

- (void)primaryTapped {
    if (self.presentedViewController) { return; } // 确认框已在弹出（连点）
    [self showError:nil];
    [self.view endEditing:YES];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"email.unbind.confirm_title")
                                                                message:IMLocalized(@"email.unbind.body")
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"email.action.unbind") style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) { [ws performUnbind]; }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)performUnbind {
    NSString *password = self.passwordField.text ?: @"";
    self.busy = YES;
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token) {
        [IMHTTPService.sharedService unbindEmailWithToken:token password:password completion:^(NSError *error) {
            [ws handleUnbind:error];
        }];
    }];
}

- (void)handleUnbind:(nullable NSError *)error {
    self.busy = NO;
    if (!error) {
        IMLogUI(@"email_unbound");
        self.passwordField.text = @"";
        [IMEmailLoginViewController finishFlowFromPage:self state:nil toast:IMLocalized(@"email.toast.unbound")];
        return;
    }
    IMLogWarnWithTag(IMLogTagUI, @"email_unbind_failed code=%ld", (long)error.code);
    NSString *msg = IMEmailErrorMessage(error.code, -1, IMEmailRetryAfterFromError(error), error.localizedDescription);
    if (error.code == IMErrCodeEmailNotBound) { // 别的设备刚解绑：回根页（会重新取状态）
        [IMEmailLoginViewController finishFlowFromPage:self state:nil toast:msg];
        return;
    }
    [self showError:msg];
    if (IMEmailFormTargetForError(error.code) == IMEmailFormTargetPassword) { [self markErrorView:self.passwordRow]; }
}

@end
