//  IMEmailCodeViewController.m

#import "IMEmailCodeViewController.h"
#import "IMEmailLoginViewController.h"
#import "IMEmailViews.h"
#import "IMTwoStepViews.h"
#import "IMTwoStep.h"
#import "IMHTTPService+Email.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMIdentityProofSheet.h"

@interface IMEmailCodeViewController () <UITextFieldDelegate>
@property (nonatomic, copy) NSString *email;
@property (nonatomic, strong, nullable) IMIdentityProof *proof; ///< 只留密码（可复用）；验证码已用掉，重发时重新弹层
@property (nonatomic, strong) IMProofSession *proofSession;
@property (nonatomic, strong, readwrite) UITextField *codeField;
@property (nonatomic, strong) UIView *codeRow;
@property (nonatomic, strong, readwrite) UILabel *resendLabel;
@property (nonatomic, strong, nullable, readwrite) NSDate *resendDeadline;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, assign) BOOL resending;
@property (nonatomic, copy, nullable) NSString *inlineError; ///< 紧贴码框下方的红字（码框 → 红字 → 重新发送 → 更换邮箱）
@property (nonatomic, assign) BOOL visible; ///< 在屏（Timer 只在在屏期间存在）
@end

@implementation IMEmailCodeViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                       email:(NSString *)email proof:(IMIdentityProof *)proof
                proofSession:(IMProofSession *)proofSession resendDeadline:(NSDate *)deadline {
    self = [super initWithHost:host userID:userID];
    if (self) {
        _email = [email copy];
        _proof = proof.isSMS ? nil : proof;
        _proofSession = proofSession ?: [[IMProofSession alloc] initWithHost:host userID:userID];
        _resendDeadline = deadline;
    }
    return self;
}

- (NSString *)pageTitle { return IMLocalized(@"email.code.title"); }
- (BOOL)isCountdownRunning { return self.timer.isValid; }

- (void)viewDidLoad {
    self.codeField = IMTwoStepMakeCodeField(IMLocalized(@"email.code.title"));
    self.codeField.delegate = self;
    [self.codeField addTarget:self action:@selector(codeChanged) forControlEvents:UIControlEventEditingChanged];
    self.codeRow = IMTwoStepFieldRow(self.codeField, 56);
    self.resendLabel = IMEmailLinkLabel(@"", UIColor.systemBlueColor);
    self.resendLabel.accessibilityIdentifier = @"email.resend";
    [super viewDidLoad];
    [self updateResendLabel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.visible = YES;
    [self updateResendLabel];
    [self startCountdownIfNeeded];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.codeField.isFirstResponder) { [self.codeField becomeFirstResponder]; }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.visible = NO;
    [self stopCountdown]; // 离开页面即销毁 Timer；回来时 viewWillAppear 按截止时刻重建
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isMovingFromParentViewController) { [self wipePassword]; } // 被 pop：密码不再留内存
}

/// 密码只为「重新发送」而留在本页内存；流程结束（绑定成功 / 离开本页）立即丢弃。
- (void)wipePassword { self.proof = nil; }

- (void)dealloc { [self stopCountdown]; }

#pragma mark - 渲染

- (NSArray<IMTwoStepSection *> *)buildSections {
    __weak typeof(self) ws = self;
    IMTwoStepSection *code = [IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:self.codeRow onTap:nil]] footer:nil];
    code.header = IMLocalizedFormat(@"email.code.sent_to", self.email);
    code.footer = self.inlineError; // 无错误时为 nil，不占高度
    code.footerColor = UIColor.systemRedColor;
    IMTwoStepRow *resend = [IMTwoStepRow rowWithView:IMEmailLinkRow(self.resendLabel) onTap:^{ [ws resendTapped]; }];
    resend.transparent = YES;
    UILabel *changeLabel = IMEmailLinkLabel(IMLocalized(@"email.action.change"), UIColor.systemBlueColor);
    changeLabel.accessibilityIdentifier = @"email.change_email";
    IMTwoStepRow *change = [IMTwoStepRow rowWithView:IMEmailLinkRow(changeLabel) onTap:^{ [ws changeEmailTapped]; }];
    change.transparent = YES;
    return @[code, [IMTwoStepSection sectionWithRows:@[resend] footer:nil], [IMTwoStepSection sectionWithRows:@[change] footer:nil]];
}

#pragma mark - 错误行（紧贴码框）

/// 覆写：红字不进表尾（那在重发 / 更换邮箱两行之下），改为码框所在组的 footer；文本没变不重载，免得打字时抖。
- (void)showError:(NSString *)text {
    [super showError:nil];
    NSString *next = text.length > 0 ? text : nil;
    if ((next == nil && self.inlineError == nil) || [next isEqualToString:self.inlineError]) { return; }
    self.inlineError = next;
    if (!self.isViewLoaded) { return; }
    BOOL hadFocus = self.codeField.isFirstResponder;
    [self reloadSections];
    if (hadFocus) { [self.codeField becomeFirstResponder]; }
}

#pragma mark - 输入 / 提交

- (void)codeChanged {
    if (!self.codeField.markedTextRange) { // 组词期间不改写文本
        NSString *clean = IMTwoStepSanitizeCode(self.codeField.text);
        if (![clean isEqualToString:self.codeField.text]) { self.codeField.text = clean; }
    }
    if (!self.errorLabel.hidden) { [self showError:nil]; }
    if (!self.codeField.markedTextRange && IMEmailShouldAutoSubmit(self.codeField.text, self.busy || self.resending)) { [self submitCode]; }
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    dispatch_async(dispatch_get_main_queue(), ^{ [self scrollPrimaryButtonIntoView]; });
}

- (void)submitCode {
    NSString *code = IMTwoStepSanitizeCode(self.codeField.text);
    [self showError:nil];
    self.busy = YES;
    NSString *email = self.email;
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token) {
        [IMHTTPService.sharedService verifyEmailWithToken:token email:email code:code completion:^(IMEmailState *bound, NSError *error) {
            [ws handleVerify:bound error:error];
        }];
    }];
}

- (void)handleVerify:(nullable IMEmailState *)bound error:(nullable NSError *)error {
    self.busy = NO;
    if (bound) {
        IMLogUI(@"email_bound email=%@", IMEmailMasked(bound.email));
        [self wipePassword];
        [IMEmailLoginViewController finishFlowFromPage:self state:bound toast:IMLocalized(@"email.toast.bound")];
        return;
    }
    IMLogWarnWithTag(IMLogTagUI, @"email_verify_failed code=%ld", (long)error.code);
    NSInteger retry = IMEmailRetryAfterFromError(error);
    [self showError:IMEmailErrorMessage(error.code, IMEmailAttemptsLeftFromError(error), retry, error.localizedDescription)];
    switch (IMEmailCodeActionForError(error.code)) {
        case IMEmailCodeActionClearAndRefocus: // 已满 6 位被拒，留着无意义：清空并重新聚焦（唯一清空的输入）
            self.codeField.text = @"";
            [self.codeField becomeFirstResponder];
            break;
        case IMEmailCodeActionExpired:
            self.codeField.text = @"";
            [self.codeField resignFirstResponder];
            if (retry >= 0) { [self setResendDeadline:IMEmailResendDeadline(retry, [NSDate date])]; }
            UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.resendLabel); // 焦点回「重新发送」
            break;
        case IMEmailCodeActionShowError:
            break;
    }
}

#pragma mark - 重发 / 更换邮箱

- (BOOL)canResend {
    return !self.resending && !self.busy && IMEmailResendRemaining(self.resendDeadline, [NSDate date]) == 0;
}

- (void)resendTapped {
    if (![self canResend]) { return; }
    self.resending = YES;
    [self showError:nil];
    [self updateResendLabel];
    NSString *email = self.email;
    __weak typeof(self) ws = self;
    if (self.proof) { // 交过密码：直接复用
        IMIdentityProof *proof = self.proof;
        [self withToken:^(NSString *token) {
            [IMHTTPService.sharedService sendEmailCodeWithToken:token email:email proof:proof
                                                     completion:^(IMEmailSendResult *result, NSError *error) {
                [ws handleResend:result error:error];
            }];
        } failure:^(NSError *error) {
            [ws handleResend:nil error:error];
        }];
        return;
    }
    // 交的是短信验证码（已被上次发信用掉）：重新确认身份。证明本身的错留在弹层；其余回到本页红字。
    __block IMEmailSendResult *sent = nil;
    BOOL shown = [self.proofSession presentFrom:self request:^(NSString *token, IMIdentityProof *proof, void (^finish)(NSError *)) {
        [IMHTTPService.sharedService sendEmailCodeWithToken:token email:email proof:proof
                                                 completion:^(IMEmailSendResult *result, NSError *error) {
            sent = result;
            if (result && !proof.isSMS) { ws.proof = proof; }
            finish(error);
        }];
    } completion:^(BOOL succeeded, NSError *pageError) {
        if (succeeded) { [ws handleResend:sent error:nil]; }
        else if (pageError) { [ws handleResend:nil error:pageError]; }
        else { ws.resending = NO; [ws updateResendLabel]; } // 取消
    }];
    if (!shown) { self.resending = NO; [self updateResendLabel]; }
}

- (void)handleResend:(nullable IMEmailSendResult *)result error:(nullable NSError *)error {
    self.resending = NO;
    if (result) {
        IMLogUI(@"email_code_resent email=%@", IMEmailMasked(self.email));
        self.codeField.text = @""; // 旧码已作废
        [self setResendDeadline:IMEmailResendDeadline(result.resendAfter, [NSDate date])];
        [self.codeField becomeFirstResponder];
        return;
    }
    IMLogWarnWithTag(IMLogTagUI, @"email_resend_failed code=%ld", (long)error.code);
    NSInteger retry = IMEmailRetryAfterFromError(error);
    [self showError:IMEmailErrorMessage(error.code, -1, retry, error.localizedDescription)];
    if (error.code == 100002 && retry > 0) { [self setResendDeadline:IMEmailResendDeadline(retry, [NSDate date])]; return; }
    [self updateResendLabel];
}

- (void)changeEmailTapped {
    if (self.busy) { return; }
    [self.navigationController popViewControllerAnimated:YES]; // 上一页保留邮箱、清空密码
}

#pragma mark - 倒计时

- (void)setResendDeadline:(NSDate *)deadline {
    _resendDeadline = deadline;
    [self updateResendLabel];
    [self startCountdownIfNeeded];
}

- (void)updateResendLabel {
    if (!self.resendLabel) { return; }
    NSInteger left = IMEmailResendRemaining(self.resendDeadline, [NSDate date]);
    self.resendLabel.text = IMEmailResendTitle(left);
    self.resendLabel.textColor = (left > 0 || self.resending) ? UIColor.tertiaryLabelColor : UIColor.systemBlueColor;
}

- (void)startCountdownIfNeeded {
    if (!self.visible) { return; }
    if (self.timer.isValid || IMEmailResendRemaining(self.resendDeadline, [NSDate date]) == 0) { return; }
    __weak typeof(self) ws = self;
    self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { [ws tick]; }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)tick {
    [self updateResendLabel];
    if (IMEmailResendRemaining(self.resendDeadline, [NSDate date]) == 0) { [self stopCountdown]; }
}

- (void)stopCountdown {
    [self.timer invalidate];
    self.timer = nil;
}

@end
