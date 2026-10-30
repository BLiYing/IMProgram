//  IMTwoStepPasswordViewController.m

#import "IMTwoStepPasswordViewController.h"
#import "IMTwoStepBindViewController.h"
#import "IMTwoStepViews.h"
#import "IMTwoStep.h"
#import "IMHTTPService+TwoStep.h"
#import "IMLocalization.h"
#import "IMLog.h"

@interface IMTwoStepPasswordViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIView *passwordRow;
@end

@implementation IMTwoStepPasswordViewController

- (NSString *)pageTitle { return IMLocalized(@"twostep.verify_pw.title"); }
- (NSString *)primaryTitle { return IMLocalized(@"twostep.action.continue"); }
- (BOOL)primaryEnabled { return self.passwordField.text.length > 0; }

- (void)viewDidLoad {
    self.passwordField = IMTwoStepMakePasswordField(IMLocalized(@"twostep.field.password"));
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
                                        footer:IMLocalized(@"twostep.verify_pw.footer")]];
}

- (void)fieldChanged {
    if (!self.errorLabel.hidden) { [self showError:nil]; } // 重新给一次机会，不清空输入
    [self refreshPrimary];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.primaryButton.enabled) { [self primaryButtonTapped]; }
    return NO;
}

- (void)primaryTapped {
    NSString *password = self.passwordField.text ?: @"";
    [self showError:nil];
    self.busy = YES;
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token) {
        [IMHTTPService.sharedService setupTwoStepWithToken:token password:password
                                                completion:^(IMTwoStepSetup *setup, NSError *error) {
            [ws handleSetup:setup error:error];
        }];
    }];
}

- (void)handleSetup:(nullable IMTwoStepSetup *)setup error:(nullable NSError *)error {
    self.busy = NO;
    if (setup) {
        IMTwoStepBindViewController *bind = [[IMTwoStepBindViewController alloc] initWithHost:self.host userID:self.userID setup:setup];
        [self.navigationController pushViewController:bind animated:YES];
        return;
    }
    IMLogWarnWithTag(IMLogTagUI, @"twostep_setup_failed code=%ld", (long)error.code);
    NSString *msg = IMTwoStepErrorMessage(error.code, IMTwoStepErrorContextPassword, -1, NO, error.localizedDescription);
    if (error.code == IMErrCodeTwoStepAlreadyEnabled) { // 别的设备刚开启：回根页（会重新取状态）
        [self popToFlowRootWithToast:msg];
        return;
    }
    [self showError:msg];
    if (error.code == 200002) { [self markErrorView:self.passwordRow]; }
}

@end
