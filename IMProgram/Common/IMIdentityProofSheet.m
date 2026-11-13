//  IMIdentityProofSheet.m

#import "IMIdentityProofSheet.h"
#import "IMLiquidSegmentedControl.h"
#import "IMSMSCodeField.h"
#import "IMTwoStepViews.h"
#import "IMHTTPService+Phone.h"
#import "IMLocalization.h"
#import "IMLog.h"

static CGFloat const kIMProofSheetHeight = 320;
static NSString * const kIMProofVerifyOwner = @"verify"; // 本人号码：一个会话只有一个
static NSString * const kIMProofErrorDomain = @"IMProof"; // 取 token 失败又没带错误时的兜底（实际登录失败总带错误）
/// 取 token 失败的标记：证明根本没送到服务端，这类错误（哪怕是重登回的 200002）不能当证明错误留在弹层。
static NSString * const kIMProofTokenFailureKey = @"im_proof_token_failure";

/// 取 token 失败 → 打上标记交还页面；没带错误时兜底成「操作失败」。
static NSError *IMProofTokenFailure(NSError *_Nullable error) {
    NSMutableDictionary *info = [error.userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
    if (!error) { info[NSLocalizedDescriptionKey] = IMLocalized(@"common.action_failed"); }
    info[kIMProofTokenFailureKey] = @YES;
    return [NSError errorWithDomain:error.domain ?: kIMProofErrorDomain code:error ? error.code : -1 userInfo:info];
}

@interface IMIdentityProofSheet () <UIAdaptivePresentationControllerDelegate, UITextFieldDelegate>
@property (nonatomic, weak) IMProofSession *session;
@property (nonatomic, copy) IMProofSubmitBlock submit;
@property (nonatomic, copy, nullable) IMProofCompletion completion;
@property (nonatomic, strong, readwrite) UITextField *passwordField;
@property (nonatomic, strong, readwrite) IMSMSCodeField *codeField;
@property (nonatomic, strong, readwrite) UIButton *confirmButton;
@property (nonatomic, strong, readwrite) IMLiquidSegmentedControl *segmentedControl;
@property (nonatomic, strong, readwrite) UILabel *errorLabel;
@property (nonatomic, strong, readwrite) UILabel *noticeLabel;
@property (nonatomic, strong) UIView *passwordCard;
@property (nonatomic, strong) UIView *codeCard;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@property (nonatomic, strong) UIActivityIndicatorView *buttonSpinner;
@property (nonatomic, copy, readwrite) NSArray<NSNumber *> *tabs;
@property (nonatomic, assign, readwrite) IMProofTab tab;
@property (nonatomic, assign, readwrite, getter=isSubmitting) BOOL submitting;
@property (nonatomic, assign) BOOL loadFailed;
@end

@interface IMProofSession ()
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, strong, readwrite) IMProofCodeCache *codeCache;
@property (nonatomic, strong, readwrite) IMResendClock *verifyClock;
@property (nonatomic, weak, nullable) IMIdentityProofSheet *sheet;
/// 弹出前取安全状态中 / 免确认直接发请求中（§15.2）：此时再点不重入。
@property (nonatomic, assign) BOOL preparing;
/// 弹出前取状态 / 免确认请求在途时宿主页面中央的转圈（0.3 秒内结束的不显示，免得闪一下）。
@property (nonatomic, strong, nullable) UIActivityIndicatorView *preparingSpinner;
/// 取 token → GET /users/me/security；取到就记进 self.security。会话弹出前与弹层（重）取共用。
- (void)loadSecurity:(void (^)(IMSecurityState *_Nullable state))done;
@end

@implementation IMProofSession

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID {
    self = [super init];
    if (self) {
        _host = [host copy];
        _userID = [userID copy];
        _codeCache = [IMProofCodeCache new];
        _verifyClock = [IMResendClock new];
        [_verifyClock followTarget:kIMProofVerifyOwner];
    }
    return self;
}

- (BOOL)isPresenting { return self.sheet != nil || self.preparing; }

- (void)withToken:(void (^)(NSString *, NSError *))block {
    IMHTTPService.sharedService.host = self.host;
    [IMHTTPService.sharedService loginWithUserID:self.userID completion:^(NSString *token, NSError *error) {
        block(token.length > 0 ? token : nil, error);
    }];
}

- (void)loadSecurity:(void (^)(IMSecurityState *))done {
    [self withToken:^(NSString *token, NSError *tokenErr) {
        if (!token) { done(nil); return; }
        [IMHTTPService.sharedService fetchSecurityStateWithToken:token completion:^(IMSecurityState *state, NSError *error) {
            if (state) { self.security = state; }
            done(state);
        }];
    }];
}

- (BOOL)presentFrom:(UIViewController *)host request:(IMProofTokenRequest)request completion:(IMProofCompletion)completion {
    // 强持有 self 无环：弹层持有 submit，会话对弹层是 weak。
    return [self presentFrom:host submit:^(IMIdentityProof *proof, void (^finish)(NSError *)) {
        [self withToken:^(NSString *token, NSError *tokenErr) {
            if (!token) { finish(IMProofTokenFailure(tokenErr)); return; } // 与「页面错误」同路：收起、不作废码
            request(token, proof, finish);
        }];
    } completion:completion];
}

- (BOOL)presentFrom:(UIViewController *)host submit:(IMProofSubmitBlock)submit completion:(IMProofCompletion)completion {
    // 弹层被程序收起（不走下滑代理）时 sheet 还挂着：已不在屏就当没有。
    if (self.preparing || (self.sheet && self.sheet.presentingViewController)) { return NO; }
    [host.view endEditing:YES];
    [self beginPreparingOn:host];
    __weak UIViewController *weakHost = host;
    // 先取安全状态（弹层本来就要它定页签）：本会话最近验证过 → 不弹层，空证明直接发；回 200049 再照常弹（§15.2）。
    // 取不到 → 照常弹层：有旧值用旧值，没有显示 proof.load_failed（点「重试」再取），进场不再自动重取一遍。
    [self loadSecurity:^(IMSecurityState *state) {
        if (IMProofSkipsSheet(state)) { IMLogUI(@"proof_skipped recent_auth_sec=%ld", (long)state.recentAuthSec); }
        IMProofRunWithoutSheet(state, submit, ^{
            [self endPreparing];
            UIViewController *h = weakHost;
            if (!h.view.window) { completion(NO, nil); return; } // 页面已离开：当取消
            [self showSheetFrom:h submit:submit completion:completion];
        }, ^(BOOL succeeded, NSError *pageError) {
            [self endPreparing];
            completion(succeeded, pageError);
        });
    }];
    return YES;
}

- (void)beginPreparingOn:(UIViewController *)host {
    self.preparing = YES;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.hidden = YES;
    [spinner startAnimating];
    [host.view addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:host.view.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:host.view.centerYAnchor],
    ]];
    self.preparingSpinner = spinner;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (spinner.superview) { spinner.hidden = NO; }
    });
}

- (void)endPreparing {
    self.preparing = NO;
    [self.preparingSpinner removeFromSuperview];
    self.preparingSpinner = nil;
}

- (void)showSheetFrom:(UIViewController *)host submit:(IMProofSubmitBlock)submit completion:(IMProofCompletion)completion {
    IMIdentityProofSheet *sheet = [IMIdentityProofSheet new];
    sheet.session = self;
    sheet.submit = submit;
    sheet.completion = completion;
    sheet.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *spc = sheet.sheetPresentationController;
    if (@available(iOS 16.0, *)) {
        UISheetPresentationControllerDetent *fit = [UISheetPresentationControllerDetent
            customDetentWithIdentifier:@"proof" resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> ctx) {
                return kIMProofSheetHeight;
            }];
        spc.detents = @[fit, UISheetPresentationControllerDetent.largeDetent];
    } else {
        spc.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    }
    spc.prefersGrabberVisible = YES;
    spc.preferredCornerRadius = 20;
    sheet.presentationController.delegate = sheet;
    self.sheet = sheet;
    [host presentViewController:sheet animated:YES completion:nil];
}

@end

@implementation IMIdentityProofSheet

#pragma mark - 构造

- (UIView *)cardWithField:(UITextField *)field {
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 10;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [field.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-8],
        [field.topAnchor constraintEqualToAnchor:card.topAnchor], [field.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [card.heightAnchor constraintEqualToConstant:44],
    ]];
    return card;
}

- (UILabel *)footnote:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:13];
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UILabel *title = [UILabel new];
    title.text = IMLocalized(@"proof.title");
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.textAlignment = NSTextAlignmentCenter;
    title.accessibilityTraits = UIAccessibilityTraitHeader;

    self.segmentedControl = [[IMLiquidSegmentedControl alloc] initWithFrame:CGRectZero];
    self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.segmentedControl.accessibilityIdentifier = @"proof.segments";
    [self.segmentedControl addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    [self.segmentedControl.heightAnchor constraintEqualToConstant:34].active = YES;

    self.passwordField = IMTwoStepMakePasswordField(IMLocalized(@"proof.password.placeholder"));
    self.passwordField.accessibilityIdentifier = @"proof.password";
    self.passwordField.returnKeyType = UIReturnKeyDone;
    self.passwordField.delegate = self;
    [self.passwordField addTarget:self action:@selector(inputChanged) forControlEvents:UIControlEventEditingChanged];
    self.passwordCard = [self cardWithField:self.passwordField];

    self.codeField = [[IMSMSCodeField alloc] initWithTint:UIColor.systemBlueColor];
    self.codeField.accessibilityIdentifier = @"proof.code";
    self.codeField.clock = self.session.verifyClock;
    __weak typeof(self) ws = self;
    self.codeField.onSend = ^{ [ws sendCode]; };
    [self.codeField addTarget:self action:@selector(inputChanged) forControlEvents:UIControlEventEditingChanged];
    self.codeCard = [self cardWithField:self.codeField];

    self.noticeLabel = [self footnote:UIColor.secondaryLabelColor];
    self.errorLabel = [self footnote:UIColor.systemRedColor];
    self.errorLabel.accessibilityIdentifier = @"proof.error";
    self.loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingSpinner.hidesWhenStopped = YES;
    [self buildConfirmButton];

    UIStackView *seg = [[UIStackView alloc] initWithArrangedSubviews:@[self.segmentedControl]];
    seg.alignment = UIStackViewAlignmentCenter;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title, seg, self.loadingSpinner, self.noticeLabel, self.passwordCard, self.codeCard, self.errorLabel, self.confirmButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:14 afterView:seg];
    [stack setCustomSpacing:20 afterView:self.errorLabel];
    [stack setCustomSpacing:20 afterView:self.codeCard];
    [stack setCustomSpacing:20 afterView:self.passwordCard];
    [self.view addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:g.topAnchor constant:18],
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [self.segmentedControl.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];
    [self startWithSecurity];
}

- (void)buildConfirmButton {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor = UIColor.systemBlueColor;
    b.layer.cornerRadius = 12;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.accessibilityIdentifier = @"proof.confirm";
    [b addTarget:self action:@selector(confirmTapped) forControlEvents:UIControlEventTouchUpInside];
    [b.heightAnchor constraintEqualToConstant:50].active = YES;
    self.buttonSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.buttonSpinner.color = UIColor.whiteColor;
    self.buttonSpinner.hidesWhenStopped = YES;
    self.buttonSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [b addSubview:self.buttonSpinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.buttonSpinner.centerXAnchor constraintEqualToAnchor:b.centerXAnchor],
        [self.buttonSpinner.centerYAnchor constraintEqualToAnchor:b.centerYAnchor],
    ]];
    self.confirmButton = b;
}

#pragma mark - 安全状态 → 页签

/// 会话弹出前已经取过一次安全状态（成功就已记进 session.security）：这里只用结果，不再自动重取。
- (void)startWithSecurity {
    IMSecurityState *cached = self.session.security;
    if (cached) { [self applySecurity:cached preferCachedCode:YES]; return; }
    IMLogWarnWithTag(IMLogTagUI, @"proof_security_load_failed cached=0");
    self.tabs = @[];
    self.loadFailed = YES;
    [self render];
}

- (void)refreshSecurity {
    self.loadFailed = NO;
    if (!self.session.security) { [self.loadingSpinner startAnimating]; }
    [self render];
    __weak typeof(self) ws = self;
    [self.session loadSecurity:^(IMSecurityState *state) { [ws securityLoaded:state]; }];
}

- (void)securityLoaded:(nullable IMSecurityState *)state {
    [self.loadingSpinner stopAnimating];
    if (!state) {
        IMLogWarnWithTag(IMLogTagUI, @"proof_security_load_failed cached=%d", self.session.security != nil);
        if (!self.session.security) { self.loadFailed = YES; [self render]; } // 有旧值就继续用旧值
        return;
    }
    BOOL first = self.tabs.count == 0; // session.security 已由 loadSecurity 记下
    [self applySecurity:state preferCachedCode:first];
}

- (void)applySecurity:(IMSecurityState *)state preferCachedCode:(BOOL)preferCachedCode {
    NSArray<NSNumber *> *tabs = IMProofTabsForState(state);
    BOOL changed = ![tabs isEqualToArray:self.tabs];
    self.tabs = tabs;
    NSString *cachedCode = self.session.codeCache.code;
    if (preferCachedCode && cachedCode.length > 0 && [tabs containsObject:@(IMProofTabSMS)]) {
        self.tab = IMProofTabSMS;
        self.codeField.text = cachedCode;
    } else if (tabs.count > 0 && ![tabs containsObject:@(self.tab)]) {
        self.tab = (IMProofTab)tabs.firstObject.integerValue;
    }
    if (changed || preferCachedCode) {
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        for (NSNumber *t in tabs) { [titles addObject:IMLocalized(t.integerValue == IMProofTabSMS ? @"proof.tab_sms" : @"proof.tab_password")]; }
        self.segmentedControl.titles = titles;
    }
    if (tabs.count > 0) { self.segmentedControl.selectedIndex = (NSInteger)[tabs indexOfObject:@(self.tab)]; }
    [self render];
    [self focusCurrentField];
}

#pragma mark - 渲染

/// 状态已知但没有可用方式（没设密码又不能发短信，见 IMProofTabsForState）：提示、确认不可点。
/// 与「还没取到 / 取不到」区分：那时 session.security 为 nil。
- (BOOL)noMethodAvailable { return self.session.security != nil && self.tabs.count == 0; }

- (void)render {
    BOOL ready = self.tabs.count > 0;
    BOOL sms = self.tab == IMProofTabSMS;
    self.segmentedControl.superview.hidden = !(ready && IMProofShowsSegments(self.tabs));
    self.passwordCard.hidden = !ready || sms;
    self.codeCard.hidden = !ready || !sms;
    NSString *masked = self.session.security.phoneMasked;
    if ([self noMethodAvailable]) {
        self.noticeLabel.text = IMLocalized(@"proof.sms_unavailable");
        self.noticeLabel.hidden = NO;
    } else {
        self.noticeLabel.text = masked.length > 0 ? IMLocalizedFormat(@"security.code_sent_to", masked) : nil;
        self.noticeLabel.hidden = !ready || !sms || masked.length == 0;
    }
    NSString *loadFailedText = IMLocalized(@"proof.load_failed");
    if (self.loadFailed) {
        self.errorLabel.text = loadFailedText;
    } else if ([self.errorLabel.text isEqualToString:loadFailedText]) {
        self.errorLabel.text = nil; // 重试中 / 重试成功：不再挂着上一次的取失败
    }
    self.errorLabel.hidden = self.errorLabel.text.length == 0;
    [self.codeField refreshSendButton];
    [self refreshConfirm];
}

- (void)refreshConfirm {
    NSString *title = IMLocalized(self.loadFailed ? @"common.retry" : @"proof.confirm");
    BOOL enabled = self.loadFailed ||
        (self.tabs.count > 0 && IMProofCanConfirm(self.tab, self.passwordField.text, self.codeField.text, self.submitting));
    [self.confirmButton setTitle:self.submitting ? @"" : title forState:UIControlStateNormal];
    self.confirmButton.enabled = enabled;
    self.confirmButton.alpha = enabled ? 1 : (self.submitting ? 0.7 : 0.5);
    if (self.submitting) { [self.buttonSpinner startAnimating]; } else { [self.buttonSpinner stopAnimating]; }
}

- (void)showError:(nullable NSString *)text {
    self.errorLabel.text = text;
    self.errorLabel.hidden = text.length == 0;
}

- (void)focusCurrentField {
    if (self.tabs.count == 0) { return; }
    UITextField *f = self.tab == IMProofTabSMS ? self.codeField : self.passwordField;
    dispatch_async(dispatch_get_main_queue(), ^{ if (!f.isFirstResponder) { [f becomeFirstResponder]; } });
}

#pragma mark - 交互

- (void)segmentChanged {
    NSInteger i = self.segmentedControl.selectedIndex;
    if (i < 0 || i >= (NSInteger)self.tabs.count || self.submitting) { return; }
    self.tab = (IMProofTab)self.tabs[(NSUInteger)i].integerValue;
    [self showError:nil];
    [self render];
    [self focusCurrentField];
}

- (void)inputChanged {
    if (!self.loadFailed && self.errorLabel.text.length > 0) { [self showError:nil]; }
    [self refreshConfirm];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.confirmButton.enabled) { [self confirmTapped]; }
    return NO;
}

- (void)sendCode {
    if (self.codeField.isSending) { return; }
    [self.codeField beginSending];
    [self showError:nil];
    __weak typeof(self) ws = self;
    IMProofSession *session = self.session;
    [session withToken:^(NSString *token, NSError *tokenErr) {
        if (!token) { [ws codeSent:nil error:IMProofTokenFailure(tokenErr)]; return; } // 没带错误也要有提示
        [IMHTTPService.sharedService sendVerifyCodeWithToken:token completion:^(IMSMSSendResult *result, NSError *error) {
            [ws codeSent:result error:error];
        }];
    }];
}

- (void)codeSent:(nullable IMSMSSendResult *)result error:(nullable NSError *)error {
    NSString *failure = [self.codeField applySendResult:result error:error sameTarget:YES]; // codeField.clock 即 session.verifyClock
    if (result) {
        IMLogUI(@"proof_verify_code_sent");
        [self.session.codeCache noteResent]; // 服务端重发覆盖旧码：缓存与输入框里预填的旧码一起作废
        self.codeField.text = @"";
        if (result.phoneMasked.length > 0) { self.session.security.phoneMasked = result.phoneMasked; }
    } else {
        IMLogWarnWithTag(IMLogTagUI, @"proof_verify_code_failed code=%ld", (long)error.code);
        [self showError:failure];
    }
    [self render];
    if (result) { [self.codeField becomeFirstResponder]; }
}

- (void)confirmTapped {
    if (self.loadFailed) { [self refreshSecurity]; return; }
    if (!IMProofCanConfirm(self.tab, self.passwordField.text, self.codeField.text, self.submitting)) { return; }
    IMIdentityProof *proof = self.tab == IMProofTabSMS ? [IMIdentityProof smsProof:self.codeField.text]
                                                       : [IMIdentityProof passwordProof:self.passwordField.text ?: @""];
    [self setSubmittingState:YES];
    [self showError:nil];
    __weak typeof(self) ws = self;
    __block BOOL finished = NO;
    self.submit(proof, ^(NSError *error) {
        if (finished) { return; }
        finished = YES;
        [ws finishWithProof:proof error:error];
    });
}

- (void)setSubmittingState:(BOOL)submitting {
    self.submitting = submitting;
    self.modalInPresentation = submitting; // 提交中：下滑 / 点外部都忽略
    self.segmentedControl.userInteractionEnabled = !submitting;
    self.passwordField.enabled = !submitting;
    self.codeField.enabled = !submitting;
    [self refreshConfirm];
}

- (void)finishWithProof:(IMIdentityProof *)proof error:(nullable NSError *)error {
    [self setSubmittingState:NO];
    IMProofSession *session = self.session;
    if (!error) {
        [session.codeCache noteSucceeded];
        [self closeWithSucceeded:YES pageError:nil];
        return;
    }
    BOOL tokenFailure = [error.userInfo[kIMProofTokenFailureKey] boolValue];
    if (!tokenFailure && IMProofErrorStaysInSheet(error.code, IMSMSFieldFromError(error))) {
        IMLogWarnWithTag(IMLogTagUI, @"proof_rejected code=%ld sms=%d", (long)error.code, proof.isSMS);
        [session.codeCache noteProofRejected:proof];
        if (proof.isSMS) { self.codeField.text = @""; } // 服务端判错过的码留着无意义
        [self showError:IMSMSSubmitErrorMessage(error.code, IMSMSAttemptsLeftFromError(error),
                                                IMErrorMessageOrFallback(error, IMLocalized(@"common.action_failed")))];
        [self refreshConfirm];
        [self focusCurrentField];
        return;
    }
    // 七个接口都是操作成功才用掉验证码：留着下次直接交（取 token 失败时码根本没交出去，同样留着）。
    [session.codeCache notePageErrorAfterProof:proof];
    [self closeWithSucceeded:NO pageError:error];
}

- (void)closeWithSucceeded:(BOOL)succeeded pageError:(nullable NSError *)error {
    IMProofCompletion completion = self.completion;
    self.completion = nil;
    self.session.sheet = nil;
    [self.view endEditing:YES];
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
        if (completion) { completion(succeeded, error); }
    }];
}

#pragma mark - 下滑关闭

- (BOOL)presentationControllerShouldDismiss:(UIPresentationController *)presentationController {
    return !self.submitting;
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    [self.session.codeCache noteCancelledWithTypedCode:self.codeField.text tabWasSMS:self.tab == IMProofTabSMS && self.tabs.count > 0];
    self.session.sheet = nil;
    IMProofCompletion completion = self.completion;
    self.completion = nil;
    if (completion) { completion(NO, nil); }
}

@end
