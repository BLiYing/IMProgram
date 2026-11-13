//  IMPhoneBindViewController.m

#import "IMPhoneBindViewController.h"
#import "IMHTTPService+Phone.h"
#import "IMIdentityProofSheet.h"
#import "IMLoginPhoneFields.h" // IMPresentSMSRegionPicker
#import "IMPhoneAuth.h"
#import "IMPublicConfig.h"
#import "IMServerEndpoint.h"
#import "IMSMSCodeField.h"
#import "IMTwoStepViews.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMTheme.h"
#import "UIViewController+IMToast.h"

static CGFloat const kIMCountryCodeWidth = 76;

@interface IMPhoneBindViewController () <UITextFieldDelegate>
@property (nonatomic, strong) IMSecurityState *security;
@property (nonatomic, strong, readwrite) UITextField *phoneField;
@property (nonatomic, strong, readwrite) IMSMSCodeField *codeField;
@property (nonatomic, strong, readwrite) IMProofSession *proofSession;
@property (nonatomic, strong) UIButton *countryButton;
@property (nonatomic, strong) UIView *phoneRow, *codeRow;
@property (nonatomic, copy) NSString *countryCode;
@property (nonatomic, strong, nullable) IMLoginConfig *config;
@property (nonatomic, strong) IMPublicConfig *configFetcher;
/// 点过「绑定」（已预填）：本页不再显示旧号码提示。「不再提示」成功则直接清 security.legacyPhone。
@property (nonatomic, assign) BOOL legacyPrefilled;
@property (nonatomic, assign) BOOL legacyDismissing;
@end

@implementation IMPhoneBindViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID security:(IMSecurityState *)security {
    self = [super initWithHost:host userID:userID];
    if (self) {
        _security = security;
        _countryCode = IMPhoneDefaultCountryCode;
        _proofSession = [[IMProofSession alloc] initWithHost:host userID:userID];
        _proofSession.security = security;
        _configFetcher = [IMPublicConfig new];
    }
    return self;
}

- (BOOL)changing { return self.security.phoneBound; }
- (NSString *)pageTitle { return IMLocalized([self changing] ? @"security.phone.change_title" : @"security.phone.bind_title"); }
- (NSString *)primaryTitle { return IMLocalized(@"security.phone.next"); }
- (BOOL)primaryEnabled {
    return IMPhoneNationalNumber(self.countryCode, self.phoneField.text).length > 0 && IMSMSCodeIsComplete(self.codeField.text) && !self.proofSession.isPresenting;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    self.phoneField = [UITextField new];
    self.phoneField.placeholder = IMLocalized(@"security.phone.new_placeholder");
    self.phoneField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.phoneField.keyboardType = UIKeyboardTypePhonePad;
    self.phoneField.textContentType = UITextContentTypeTelephoneNumber;
    self.phoneField.accessibilityIdentifier = @"phone.new";
    self.phoneField.delegate = self;
    [self.phoneField addTarget:self action:@selector(phoneChanged) forControlEvents:UIControlEventEditingChanged];
    self.phoneRow = [self buildPhoneRow];

    self.codeField = [[IMSMSCodeField alloc] initWithTint:UIColor.systemBlueColor];
    self.codeField.accessibilityIdentifier = @"phone.code";
    self.codeField.delegate = self;
    __weak typeof(self) ws = self;
    self.codeField.onSend = ^{ [ws sendCode]; };
    [self.codeField addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
    self.codeRow = IMTwoStepFieldRow(self.codeField, 44);
    [super viewDidLoad];
    [self phoneChanged];
    [self loadRegions];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.phoneField.isFirstResponder && !self.codeField.isFirstResponder && !self.presentedViewController
        && self.phoneField.text.length == 0) {
        [self.phoneField becomeFirstResponder];
    }
}

/// 国家码框（宽 76，与号码框间距 8；只开放一个地区时不可点）+ 号码框。
- (UIView *)buildPhoneRow {
    UIButton *cc = [UIButton buttonWithType:UIButtonTypeSystem];
    cc.translatesAutoresizingMaskIntoConstraints = NO;
    cc.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [cc setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    [cc setTitleColor:UIColor.labelColor forState:UIControlStateDisabled];
    cc.accessibilityIdentifier = @"phone.country_code";
    [cc addTarget:self action:@selector(pickRegion) forControlEvents:UIControlEventTouchUpInside];
    self.countryButton = cc;
    [self refreshCountryButton];
    UIView *sep = [UIView new];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = UIColor.separatorColor;
    self.phoneField.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *row = [UIView new];
    [row addSubview:cc]; [row addSubview:sep]; [row addSubview:self.phoneField];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [cc.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [cc.widthAnchor constraintEqualToConstant:kIMCountryCodeWidth],
        [cc.topAnchor constraintEqualToAnchor:row.topAnchor], [cc.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [sep.leadingAnchor constraintEqualToAnchor:cc.trailingAnchor],
        [sep.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [sep.topAnchor constraintEqualToAnchor:row.topAnchor constant:10],
        [sep.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-10],
        [self.phoneField.leadingAnchor constraintEqualToAnchor:sep.trailingAnchor constant:8],
        [self.phoneField.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [self.phoneField.topAnchor constraintEqualToAnchor:row.topAnchor], [self.phoneField.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    ]];
    return row;
}

- (void)refreshCountryButton {
    [self.countryButton setTitle:[@"+" stringByAppendingString:self.countryCode] forState:UIControlStateNormal];
    self.countryButton.enabled = IMLoginShowsRegionPicker(self.config);
}

/// 开放地区（多于一个才出选择器）。拉不到保持默认 +86。
- (void)loadRegions {
    __weak typeof(self) ws = self;
    [self.configFetcher fetchConfigWithScheme:IMServerEndpoint.shared.scheme host:self.host completion:^(IMLoginConfig *config, BOOL failed) {
        __strong typeof(ws) self = ws;
        if (!self || failed) { return; }
        self.config = config;
        if (IMLoginShouldResetCountryCode(NO, self.countryCode, config)) {
            self.countryCode = IMLoginDefaultCountryCode(config);
            // 旧号码预填的国家码不在开放地区里：号码不能挂到别的国家码下（那是另一个人的号码），一起清掉。
            if (self.legacyPrefilled) { self.phoneField.text = @""; }
        }
        [self refreshCountryButton];
        [self phoneChanged];
    }];
}

- (void)pickRegion {
    __weak typeof(self) ws = self;
    IMPresentSMSRegionPicker(self, self.config, self.countryButton, ^(NSString *code) {
        ws.countryCode = code;
        [ws refreshCountryButton];
        [ws phoneChanged];
    });
}

#pragma mark - 渲染

- (NSArray<IMTwoStepSection *> *)buildSections {
    IMTwoStepSection *legacy = [self legacyPromptSection];
    IMTwoStepSection *s = [IMTwoStepSection sectionWithRows:@[[IMTwoStepRow rowWithView:self.phoneRow onTap:nil],
                                                              [IMTwoStepRow rowWithView:self.codeRow onTap:nil]]
                                                     footer:[NSString stringWithFormat:@"%@\n%@",
                                                             IMLocalized([self changing] ? @"security.phone.change_footer" : @"security.phone.bind_footer"),
                                                             IMLocalized(@"security.phone.next_hint")]];
    if ([self changing] && self.security.phoneMasked.length > 0) {
        s.header = IMLocalizedFormat(@"security.phone.current", self.security.phoneMasked);
    }
    return legacy ? @[legacy, s] : @[s];
}

#pragma mark - 资料里的旧号码（PHONE_AUTH_DESIGN §15.1）

/// 资料里曾自填的旧号码：非 nil 时页顶显示「是否绑定为登录手机号」提示。
- (nullable IMLegacyPhone *)legacyPhone { return self.legacyPrefilled ? nil : IMSecurityLegacyPhonePrompt(self.security); }

/// 提示文案 + 「绑定」「不再提示」两个文字链行；没有旧号码时 nil。
- (nullable IMTwoStepSection *)legacyPromptSection {
    IMLegacyPhone *legacy = self.legacyPhone;
    if (!legacy) { return nil; }
    __weak typeof(self) ws = self;
    IMTwoStepRow *prompt = [IMTwoStepRow rowWithView:IMTwoStepCenteredTextRow(IMLocalizedFormat(@"security.phone.legacy_prompt", legacy.masked),
                                                                              IMTheme.textPrimary) onTap:nil];
    UIView *bindView = IMTwoStepCenteredTextRow(IMLocalized(@"security.phone.legacy_bind"), IMTheme.accent);
    bindView.accessibilityIdentifier = @"phone.legacy.bind";
    UIView *dismissView = IMTwoStepCenteredTextRow(IMLocalized(@"security.phone.legacy_dismiss"), IMTheme.textSecondary);
    dismissView.accessibilityIdentifier = @"phone.legacy.dismiss";
    IMTwoStepRow *bind = [IMTwoStepRow rowWithView:bindView onTap:^{ [ws legacyBindTapped]; }];
    IMTwoStepRow *dismiss = [IMTwoStepRow rowWithView:dismissView onTap:^{ [ws legacyDismissTapped]; }];
    return [IMTwoStepSection sectionWithRows:@[prompt, bind, dismiss] footer:nil];
}

/// 「绑定」：国家码 + 号码预填进下面的表单，收起提示；之后照常发验证码 + 确认身份。
- (void)legacyBindTapped {
    IMLegacyPhone *legacy = self.legacyPhone;
    if (!legacy) { return; }
    IMLogUI(@"phone_legacy_prefill phone=%@", legacy.masked);
    self.legacyPrefilled = YES;
    self.countryCode = legacy.countryCode;
    self.phoneField.text = legacy.phone;
    [self refreshCountryButton];
    [self phoneChanged];
    [self reloadSections];
    [self.codeField becomeFirstResponder];
}

/// 「不再提示」：DELETE /users/me/legacy-phone 成功才收起；失败吐司、提示留着。
- (void)legacyDismissTapped {
    if (!self.legacyPhone || self.legacyDismissing) { return; }
    self.legacyDismissing = YES;
    __weak typeof(self) ws = self;
    void (^failed)(NSError *) = ^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        IMLogWarnWithTag(IMLogTagUI, @"phone_legacy_dismiss_failed code=%ld", (long)error.code);
        self.legacyDismissing = NO;
        [self im_showToast:IMLocalized(@"common.action_failed")];
    };
    [self withToken:^(NSString *token) {
        [IMHTTPService.sharedService dismissLegacyPhoneWithToken:token completion:^(NSError *error) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (error) { failed(error); return; }
            IMLogUI(@"phone_legacy_dismissed");
            self.legacyDismissing = NO;
            self.security.legacyPhone = nil; // 隐私与安全页持有同一份状态，一起清
            [self reloadSections];
        }];
    } failure:failed];
}

#pragma mark - 输入

/// 倒计时按号码计：换号码（或国家码）就清上一个号码的截止时刻。
- (void)phoneChanged {
    NSString *phone = IMPhoneNationalNumber(self.countryCode, self.phoneField.text);
    [self.codeField.clock followTarget:[NSString stringWithFormat:@"%@:%@", self.countryCode, phone]];
    self.codeField.sendAllowed = phone.length > 0;
    [self fieldChanged];
}

- (void)fieldChanged {
    if (!self.errorLabel.hidden) { [self showError:nil]; } // 重新给一次机会，不清空输入
    [self refreshPrimary];
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    if (f == self.phoneField) { [self.codeField becomeFirstResponder]; }
    else if (self.primaryButton.enabled) { [self primaryButtonTapped]; }
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    dispatch_async(dispatch_get_main_queue(), ^{ [self scrollPrimaryButtonIntoView]; });
}

#pragma mark - 发码（新号码，bind 场景）

- (void)sendCode {
    NSString *cc = self.countryCode, *phone = IMPhoneNationalNumber(self.countryCode, self.phoneField.text);
    if (phone.length == 0) { return; }
    [self.codeField beginSending];
    [self showError:nil];
    __weak typeof(self) ws = self;
    [self withToken:^(NSString *token) {
        [IMHTTPService.sharedService sendSMSCodeForScene:@"bind" countryCode:cc phone:phone token:token
                                              completion:^(IMSMSSendResult *result, NSError *error) {
            [ws codeSent:result error:error target:[NSString stringWithFormat:@"%@:%@", cc, phone]];
        }];
    } failure:^(NSError *error) { [ws codeSent:nil error:error target:nil]; }];
}

- (void)codeSent:(nullable IMSMSSendResult *)result error:(nullable NSError *)error target:(nullable NSString *)target {
    BOOL sameNumber = target == nil || [target isEqualToString:self.codeField.clock.owner]; // 发码途中改了号码：结果不记到新号码头上
    NSString *failure = [self.codeField applySendResult:result error:error sameTarget:sameNumber];
    if (result && sameNumber) {
        [self.codeField becomeFirstResponder];
    } else if (error) {
        IMLogWarnWithTag(IMLogTagUI, @"phone_bind_send_failed code=%ld", (long)error.code);
        [self showError:failure];
        if (error.code == IMErrCodePhoneTaken || error.code == IMErrCodePhoneInvalid) { [self markErrorView:self.phoneRow]; }
    }
}

#pragma mark - 下一步：确认身份 → 提交

- (void)primaryTapped {
    NSString *cc = self.countryCode, *phone = IMPhoneNationalNumber(self.countryCode, self.phoneField.text), *code = self.codeField.text ?: @"";
    BOOL changing = [self changing];
    [self showError:nil];
    __weak typeof(self) ws = self;
    __block NSString *bound = nil;
    [self.proofSession presentFrom:self request:^(NSString *token, IMIdentityProof *proof, void (^finish)(NSError *)) {
        [IMHTTPService.sharedService bindPhoneWithToken:token proof:proof countryCode:cc phone:phone code:code
                                             completion:^(NSString *masked, NSError *error) {
            bound = masked;
            finish(error);
        }];
    } completion:^(BOOL succeeded, NSError *pageError) {
        if (succeeded) { [ws finishBound:bound changing:changing]; }
        else if (pageError) { [ws showPageError:pageError]; }
        [ws refreshPrimary];
    }];
    [self refreshPrimary];
}

- (void)finishBound:(NSString *)masked changing:(BOOL)changing {
    IMLogUI(@"phone_%@ phone=%@", changing ? @"changed" : @"bound", masked ?: @"-");
    if (self.onBound) { self.onBound(masked ?: @""); }
    [self popToFlowRootWithToast:IMLocalized(changing ? @"security.phone.toast_changed" : @"security.phone.toast_bound")];
}

/// 新号码那边的错：红字 + 描红对应行；输入一律保留（改对了直接重交，旧号码那枚验证码仍有效、弹层会预填）。
- (void)showPageError:(NSError *)error {
    IMLogWarnWithTag(IMLogTagUI, @"phone_bind_failed code=%ld field=%@", (long)error.code, IMSMSFieldFromError(error) ?: @"-");
    [self showError:IMSMSSubmitErrorMessage(error.code, IMSMSAttemptsLeftFromError(error),
                                            IMErrorMessageOrFallback(error, IMLocalized(@"common.action_failed")))];
    if (error.code == IMErrCodePhoneTaken || error.code == IMErrCodePhoneInvalid) {
        [self markErrorView:self.phoneRow];
    } else if (error.code == IMErrCodeSMSCodeInvalid || error.code == IMErrCodeSMSCodeExpired) {
        if (error.code == IMErrCodeSMSCodeExpired) { self.codeField.text = @""; } // 已作废的码留着无意义
        [self markErrorView:self.codeRow];
    }
}

@end
