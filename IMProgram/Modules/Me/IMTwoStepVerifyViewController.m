//  IMTwoStepVerifyViewController.m

#import "IMTwoStepVerifyViewController.h"
#import "IMTwoStepCodesViewController.h"
#import "IMTwoStepViews.h"
#import "IMTwoStep.h"
#import "IMHTTPService+TwoStep.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMIdentityProofSheet.h"

@interface IMTwoStepVerifyViewController () <UITextFieldDelegate>
@property (nonatomic, assign) IMTwoStepVerifyMode mode;
@property (nonatomic, assign) BOOL useRecovery;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UITextField *recoveryField;
@property (nonatomic, strong) UIView *codeRow;
@property (nonatomic, strong) UIView *recoveryRow;
@end

@implementation IMTwoStepVerifyViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID mode:(IMTwoStepVerifyMode)mode {
    self = [super initWithHost:host userID:userID];
    if (self) { _mode = mode; }
    return self;
}

- (BOOL)isDisable { return self.mode == IMTwoStepVerifyModeDisable; }
- (NSString *)pageTitle { return IMLocalized([self isDisable] ? @"twostep.disable.title" : @"twostep.regen.title"); }
- (NSString *)primaryTitle { return IMLocalized([self isDisable] ? @"twostep.disable.title" : @"twostep.regen.submit"); }
- (UIColor *)primaryColor { return [self isDisable] ? UIColor.systemRedColor : UIColor.systemBlueColor; }

- (NSString *)currentCodeText {
    return self.useRecovery ? self.recoveryField.text : self.codeField.text;
}

- (BOOL)primaryEnabled {
    return IMTwoStepCanSubmitVerify([self currentCodeText], self.useRecovery); // 身份确认在弹层里
}

- (IMProofSession *)proofSession {
    if (!_proofSession) { _proofSession = [[IMProofSession alloc] initWithHost:self.host userID:self.userID]; }
    return _proofSession;
}

- (void)viewDidLoad {
    self.codeField = IMTwoStepMakeCodeField(IMLocalized(@"twostep.field.code"));
    self.recoveryField = IMTwoStepMakeRecoveryField(IMLocalized(@"twostep.field.recovery"));
    for (UITextField *f in @[self.codeField, self.recoveryField]) {
        f.delegate = self;
        [f addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    }
    self.codeRow = IMTwoStepFieldRow(self.codeField, 56);
    self.recoveryRow = IMTwoStepFieldRow(self.recoveryField, 44);
    [super viewDidLoad];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.codeField.isFirstResponder && !self.recoveryField.isFirstResponder && !self.presentedViewController) {
        [(self.useRecovery ? self.recoveryField : self.codeField) becomeFirstResponder];
    }
}

#pragma mark - 渲染

- (NSArray<IMTwoStepSection *> *)buildSections {
    __weak typeof(self) ws = self;
    UIView *codeView = self.useRecovery ? self.recoveryRow : self.codeRow;
    IMTwoStepSection *fields = [IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:codeView onTap:nil]] footer:nil];
    UIView *toggle = IMTwoStepCenteredTextRow(IMLocalized(self.useRecovery ? @"twostep.use_code" : @"twostep.use_recovery"),
                                              UIColor.systemBlueColor);
    toggle.accessibilityIdentifier = @"twostep.toggle_method";
    IMTwoStepSection *switcher = [IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:toggle onTap:^{ [ws toggleMethod]; }]]
        footer:IMLocalized([self isDisable] ? @"twostep.disable.footer" : @"twostep.regen.footer")];
    return @[fields, switcher];
}

- (void)toggleMethod {
    self.useRecovery = !self.useRecovery;
    [self showError:nil];
    UITextField *old = self.useRecovery ? self.codeField : self.recoveryField;
    old.text = @""; // 换方式就丢掉另一种码，别把上一种残留带进提交
    [self reloadSections];
    [self refreshPrimary];
    UITextField *now = self.useRecovery ? self.recoveryField : self.codeField;
    dispatch_async(dispatch_get_main_queue(), ^{ [now becomeFirstResponder]; });
}

#pragma mark - 输入

- (void)fieldChanged:(UITextField *)f {
    if (f == self.codeField && !f.markedTextRange) { // 组词期间不改写文本
        NSString *clean = IMTwoStepSanitizeCode(f.text);
        if (![clean isEqualToString:f.text]) { f.text = clean; }
    }
    if (!self.errorLabel.hidden) { [self showError:nil]; }
    [self refreshPrimary];
}

- (BOOL)textField:(UITextField *)tf shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (tf != self.recoveryField) { return YES; }
    if (IMTwoStepHandleRecoveryPaste(tf, range, string)) { return NO; }
    return IMTwoStepRecoveryAllowsEdit(tf.text, range, string, tf.markedTextRange != nil);
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    if (self.primaryButton.enabled) {
        [self primaryButtonTapped];
    }
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    dispatch_async(dispatch_get_main_queue(), ^{ [self scrollPrimaryButtonIntoView]; });
}

#pragma mark - 提交

- (void)primaryTapped {
    [self.view endEditing:YES];
    if (![self isDisable]) { [self submit]; return; }
    // 关闭：系统二次确认（破坏性按钮用 .destructive）
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:IMLocalized(@"twostep.disable.confirm_title")
                                                                message:IMLocalized(@"twostep.disable.confirm_body")
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [ac addAction:[UIAlertAction actionWithTitle:IMLocalized(@"twostep.disable.title") style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) { [ws submit]; }]];
    [self presentViewController:ac animated:YES completion:nil];
}

/// 确认身份弹层（密码或短信验证码）→ disable / recovery-codes {proof, code}。
/// 证明本身的错留在弹层；动态码错（200021）等收起弹层回本页红字——服务端操作成功前不会用掉短信验证码，改对动态码可直接重交。
- (void)submit {
    NSString *code = self.useRecovery ? IMTwoStepNormalizeRecovery(self.recoveryField.text) : IMTwoStepSanitizeCode(self.codeField.text);
    BOOL usedRecovery = self.useRecovery;
    BOOL disable = [self isDisable];
    [self showError:nil];
    __weak typeof(self) ws = self;
    __block NSArray<NSString *> *codes = nil;
    [self.proofSession presentFrom:self request:^(NSString *token, IMIdentityProof *proof, void (^finish)(NSError *)) {
        if (disable) {
            [IMHTTPService.sharedService disableTwoStepWithToken:token proof:proof code:code completion:^(NSError *error) { finish(error); }];
            return;
        }
        [IMHTTPService.sharedService regenerateRecoveryCodesWithToken:token proof:proof code:code
                                                           completion:^(NSArray<NSString *> *c, NSError *error) {
            codes = c;
            finish(error ?: (c.count > 0 ? nil : [NSError errorWithDomain:@"IMTwoStep" code:-1 userInfo:nil]));
        }];
    } completion:^(BOOL succeeded, NSError *pageError) {
        if (!succeeded && !pageError) { return; } // 取消
        if (disable) { [ws handleDisableError:pageError]; }
        else { [ws handleRegenerated:succeeded ? codes : nil usedRecovery:usedRecovery error:pageError]; }
    }];
}

- (void)handleDisableError:(nullable NSError *)error {
    if (!error) {
        IMLog(@"twostep_disabled");
        [self popToFlowRootWithToast:IMLocalized(@"twostep.toast.disabled")];
        return;
    }
    [self showFailure:error];
}

- (void)handleRegenerated:(nullable NSArray<NSString *> *)codes usedRecovery:(BOOL)usedRecovery error:(nullable NSError *)error {
    if (codes.count == 0) { [self showFailure:error]; return; }
    if (!usedRecovery) { IMTwoStepMarkEnabledNow(); } // 这个 30 秒窗口的动态码已被服务端记账，再用会被当重放
    IMLog(@"twostep_recovery_regenerated count=%lu", (unsigned long)codes.count);
    IMTwoStepCodesViewController *vc = [[IMTwoStepCodesViewController alloc] initWithHost:self.host userID:self.userID
                                                                            recoveryCodes:codes regenerated:YES];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showFailure:(NSError *)error {
    IMLogWarnWithTag(IMLogTagUI, @"twostep_manage_failed code=%ld", (long)error.code);
    if (error.code == IMErrCodeTwoStepNotEnabled) { // 别处已关闭：回根页刷新
        [self popToFlowRootWithToast:error.localizedDescription];
        return;
    }
    NSString *msg = IMTwoStepErrorMessage(error.code, IMTwoStepErrorContextManage, -1,
                                          IMTwoStepRecentlyEnabled([NSDate date]) && !self.useRecovery, error.localizedDescription);
    [self showError:msg];
    if (error.code == IMErrCodeTwoStepCodeInvalid) { [self markErrorView:self.useRecovery ? self.recoveryRow : self.codeRow]; }
}

@end
