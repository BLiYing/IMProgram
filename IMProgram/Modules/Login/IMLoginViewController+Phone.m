//  IMLoginViewController+Phone.m
//  登录页的手机号部分（PHONE_AUTH_DESIGN §4 §5 §7.3，交互稿 1-1 / 1-3 / 1-4）：
//  public-config → 页签 / 链接 / 地区；验证码登录即注册（四种结果：登录成功 / 200020 两步验证 / 200005 冷静期 / need_register 完善资料）；
//  完善资料；忘记密码。规则全部来自 Common/IMPhoneAuth（纯函数），网络在 IMHTTPService+Phone。
//  **日志不写完整号码 / 验证码 / 票据。**

#import "IMLoginViewController+Private.h"
#import "IMHTTPService+Phone.h"
#import "IMHTTPService+Account.h"
#import "IMHTTPService+TwoStep.h"
#import "IMLoginPhoneFields.h"
#import "IMLoginSubpageViews.h"
#import "IMPublicConfig.h"
#import "IMServerEndpoint.h"
#import "IMLocalization.h"
#import "IMTheme.h"
#import "IMLog.h"

@implementation IMLoginViewController (Phone)

#pragma mark - 构造

- (void)setupPhoneViews {
    __weak typeof(self) ws = self;
    self.publicConfig = [IMPublicConfig new];
    self.smsFields = [[IMLoginPhoneFields alloc] initWithIdentifierPrefix:@"login"];
    self.smsFields.onEdit = ^{ ws.touched = YES; };
    self.smsFields.onRegionTap = ^{ [ws pickRegionForFields:ws.smsFields]; };
    self.smsFields.codeField.onSend = ^{ [ws sendCodeForFields:ws.smsFields scene:@"login"]; };
    for (UITextField *f in @[self.smsFields.phoneField, self.smsFields.codeField]) {
        [f addTarget:self action:@selector(fieldDidBeginEditing:) forControlEvents:UIControlEventEditingDidBegin];
    }

    self.smsLoginButton = [self buttonTitle:IMLocalized(@"login.sms.submit") config:[UIButtonConfiguration filledButtonConfiguration]
                                     action:@selector(smsLoginTapped)];
    self.smsLoginButton.accessibilityIdentifier = @"login.submit_sms";
    self.autoRegisterHintLabel = [UILabel new];
    self.autoRegisterHintLabel.font = [UIFont systemFontOfSize:13];
    self.autoRegisterHintLabel.textColor = UIColor.secondaryLabelColor;
    self.autoRegisterHintLabel.textAlignment = NSTextAlignmentCenter;
    self.autoRegisterHintLabel.numberOfLines = 0;
    self.autoRegisterHintLabel.text = IMLocalized(@"login.sms.auto_register_hint");

    self.forgotButton = [self linkTitle:IMLocalized(@"login.forgot_password") action:@selector(forgotPasswordTapped)];
    self.forgotButton.accessibilityIdentifier = @"login.forgot_password";
    self.usernameRegisterButton = [self linkTitle:IMLocalized(@"login.register_username") action:@selector(registerTabTapped)];
    self.usernameRegisterButton.accessibilityIdentifier = @"login.register_username";
    UIView *spacer = [UIView new];
    self.linksRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.forgotButton, spacer, self.usernameRegisterButton]];
    self.linksRow.alignment = UIStackViewAlignmentCenter;

    self.completeView = [IMLoginCompleteProfileView new];
    self.completeView.onSubmit = ^(NSString *nickname) { [ws submitCompleteProfile:nickname]; };
    self.completeView.onBack = ^{ [ws leaveSubpage]; };
    self.resetView = [IMLoginResetPasswordView new];
    self.resetView.onSubmit = ^{ [ws submitReset]; };
    self.resetView.onBack = ^{ [ws leaveSubpage]; };
    self.resetView.phoneFields.onRegionTap = ^{ [ws pickRegionForFields:ws.resetView.phoneFields]; };
    self.resetView.phoneFields.codeField.onSend = ^{ [ws sendCodeForFields:ws.resetView.phoneFields scene:@"reset"]; };
    for (UITextField *f in @[self.resetView.phoneFields.phoneField, self.resetView.phoneFields.codeField,
                             self.resetView.passwordField, self.resetView.confirmField, self.completeView.nicknameField]) {
        [f addTarget:self action:@selector(fieldDidBeginEditing:) forControlEvents:UIControlEventEditingDidBegin];
    }
}

/// 15 regular accent 文字链（「忘记密码？」「用户名注册」）。
- (UIButton *)linkTitle:(NSString *)title action:(SEL)action {
    UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
    cfg.baseForegroundColor = IMTheme.accent;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(6, 0, 6, 0);
    cfg.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attrs) {
        NSMutableDictionary *m = [attrs mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:15];
        return m;
    };
    return [self buttonTitle:title config:cfg action:action];
}

#pragma mark - public-config

- (void)reloadLoginConfigHostChanged:(BOOL)hostChanged {
    [self reloadLoginConfigHostChanged:hostChanged keepRegisterClosed:NO];
}

- (void)reloadLoginConfigAfterRegisterClosed {
    [self reloadLoginConfigHostChanged:NO keepRegisterClosed:YES];
}

/// keepRegisterClosed=YES：提交注册刚被服务端回 200007——这是权威结论，配置结果回来后（哪怕是失败兜底的「开放」）仍标记关闭；
/// 配置的其余部分（验证码页签 / 忘记密码 / 地区）照常落下，loginConfig 不会因此一直是 nil。
- (void)reloadLoginConfigHostChanged:(BOOL)hostChanged keepRegisterClosed:(BOOL)keepRegisterClosed {
    NSString *scheme = nil, *host = nil;
    if (![IMServerEndpoint parseInput:[self trimmed:self.hostInput] scheme:&scheme host:&host]) {
        [self.publicConfig cancel];
        [self applyLoginConfig:IMLoginConfig.fallbackConfig host:nil hostChanged:hostChanged];
        if (keepRegisterClosed) { [self applyRegisterClosed:YES]; }
        return;
    }
    __weak typeof(self) ws = self;
    [self.publicConfig fetchConfigWithScheme:scheme host:host completion:^(IMLoginConfig *config, BOOL failed) {
        // 拉不到：已有本地址的结论就保留（瞬时失败不该把页签翻回去），从没拉到过才用老服务端口径。
        BOOL keepCurrent = failed && ws.loginConfig && [ws.configHost isEqualToString:host] && !hostChanged;
        if (!keepCurrent) { [ws applyLoginConfig:config host:host hostChanged:hostChanged]; }
        if (keepRegisterClosed) { [ws applyRegisterClosed:YES]; }
    }];
}

- (void)applyLoginConfig:(IMLoginConfig *)config host:(nullable NSString *)host hostChanged:(BOOL)hostChanged {
    BOOL changedHost = hostChanged || (self.configHost && host && ![self.configHost isEqualToString:host]);
    self.loginConfig = config;
    self.configHost = host;
    BOOL pickable = IMLoginShowsRegionPicker(config);
    for (IMLoginPhoneFields *fields in @[self.smsFields, self.resetView.phoneFields]) {
        fields.regionPickable = pickable;
        // 重载配置不重置用户选的国家码，除非换了服务器或该地区下线。
        if (IMLoginShouldResetCountryCode(changedHost, fields.countryCode, config)) { fields.countryCode = IMLoginDefaultCountryCode(config); }
    }
    self.tab = IMLoginTabAfterConfig(self.tab, self.touched, IMLoginTabsForConfig(config),
                                     IMLoginRememberedTab(NSUserDefaults.standardUserDefaults));
    [self applyRegisterClosed:!config.registerEnabled];
    if (!self.currentSubpage) { [self applyMode]; }
    if (!IMLoginShowsForgotPassword(config) && self.currentSubpage == self.resetView) { [self leaveSubpage]; }
}

/// 注册关闭：注册页显示内联提示并禁用提交；开放则还原（请求在途时按钮仍由 setBusy: 管）。
- (void)applyRegisterClosed:(BOOL)closed {
    self.registerClosed = closed;
    self.registerClosedLabel.hidden = !(closed && self.registerMode);
    self.registerButton.enabled = !closed && !self.submitting;
}

- (void)pickRegionForFields:(IMLoginPhoneFields *)fields {
    if (self.presentedViewController) { return; }
    __weak typeof(self) ws = self;
    IMPresentSMSRegionPicker(self, self.loginConfig, fields.countryButton, ^(NSString *code) {
        ws.touched = YES;
        fields.countryCode = code;
    });
}

#pragma mark - 发码（login / reset，免鉴权）

- (void)sendCodeForFields:(IMLoginPhoneFields *)fields scene:(NSString *)scene {
    BOOL reset = [scene isEqualToString:@"reset"];
    NSString *phone = fields.normalizedPhone, *cc = fields.countryCode, *target = fields.targetKey;
    if (phone.length == 0) { [self showPhoneError:IMLocalized(@"login.error.phone_required") reset:reset]; return; }
    NSString *host = [self resolvedHostOrShowError];
    if (host.length == 0) { return; }
    IMHTTPService.sharedService.host = host;
    [self showPhoneError:nil reset:reset];
    [fields.codeField beginSending];
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService sendSMSCodeForScene:scene countryCode:cc phone:phone token:nil
                                          completion:^(IMSMSSendResult *result, NSError *error) {
        BOOL same = [fields.codeField.clock.owner isEqualToString:target]; // 发码途中改了号码：结果不记到新号码头上
        NSString *failure = [fields.codeField applySendResult:result error:error sameTarget:same];
        if (result && same) {
            [fields.codeField becomeFirstResponder];
        } else if (error) {
            IMLogWarnWithTag(IMLogTagUI, @"login_sms_send_failed scene=%@ code=%ld", scene, (long)error.code);
            [ws showPhoneError:failure reset:reset];
        }
    }];
}

- (void)showPhoneError:(nullable NSString *)message reset:(BOOL)reset {
    if (reset) { [self.resetView showError:message]; } else { [self showError:message ?: @""]; }
}

#pragma mark - 验证码登录即注册

- (void)smsLoginTapped {
    IMLoginPhoneFields *f = self.smsFields;
    if (f.normalizedPhone.length == 0) { [self showError:IMLocalized(@"login.error.phone_required")]; return; }
    NSString *code = f.codeField.text ?: @"";
    if (code.length == 0) { [self showError:IMLocalized(@"login.error.code_required")]; return; }
    if (!IMSMSCodeIsComplete(code)) { [self showError:IMLocalized(@"login.sms_code.six_digits")]; return; }
    NSString *host = [self resolvedHostOrShowError];
    if (host.length == 0) { return; }
    [self.view endEditing:YES];
    [self showError:@""];
    [self setBusy:YES activeButton:self.smsLoginButton];
    [self prepareServiceWithHost:host password:@""];
    NSString *cc = f.countryCode, *phone = f.normalizedPhone;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService loginWithSMSCountryCode:cc phone:phone code:code completion:^(IMSMSLoginResult *result, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        [self setBusy:NO activeButton:self.smsLoginButton];
        if (result.needRegister) {
            IMLogUI(@"login_sms_need_register phone=%@", IMPhoneMasked(cc, phone));
            self.registerTicket = result.registerTicket;
            self.registerHost = host;
            [self enterSubpage:self.completeView];
            [self.completeView resetWithMaskedPhone:IMPhoneMasked(cc, phone)];
            [self.completeView.nicknameField becomeFirstResponder];
            return;
        }
        if (result.token.length > 0 && result.userID.length > 0) {
            IMLogUI(@"login_sms_ok");
            [self enterAppWithHost:host userID:result.userID username:result.username rememberTab:IMLoginTabSMS];
            return;
        }
        [self handleSMSLoginError:error host:host];
    }];
}

- (void)handleSMSLoginError:(NSError *)error host:(NSString *)host {
    IMLogWarnWithTag(IMLogTagUI, @"login_sms_failed code=%ld", (long)error.code);
    NSString *ticket = error.userInfo[IMErrorTwoStepTicketKey];
    if (error.code == IMErrCodeTwoStepRequired && ticket.length > 0) {
        self.smsFields.codeField.text = @""; // 码已被这次登录用掉
        [self beginTwoStepWithTicket:ticket host:host tab:IMLoginTabSMS];
        return;
    }
    if (error.code == IMErrCodeAccountPendingDeletion) {
        NSString *restore = error.userInfo[IMErrorRestoreTicketKey];
        if (restore.length == 0) { [self showError:IMLocalized(@"err.200005")]; return; } // 没票：沿用密码恢复
        [self promptRestoreWithTicket:restore deleteAt:error.userInfo[IMErrorDeleteAtKey]];
        return;
    }
    if (error.code == IMErrCodeSMSCodeExpired) { self.smsFields.codeField.text = @""; }
    if (error.code == IMErrCodeSMSCodeExpired || error.code == IMErrCodeRateLimited) {
        [self.smsFields.codeField.clock noteFailureCode:error.code retryAfter:IMSMSRetryAfterFromError(error) now:[NSDate date]];
        [self.smsFields.codeField refreshSendButton];
    }
    [self showError:IMSMSSubmitErrorMessage(error.code, IMSMSAttemptsLeftFromError(error),
                                            IMErrorMessageOrFallback(error, IMLocalized(@"login.error.login_failed")))];
}

/// 验证码登录命中冷静期且带 restore_ticket：弹恢复确认；恢复成功后**不**自动重发验证码（会撞 60 秒间隔），提示重新获取。
- (void)promptRestoreWithTicket:(NSString *)ticket deleteAt:(nullable NSDate *)deleteAt {
    __weak typeof(self) ws = self;
    [self presentRestoreConfirmWithDeleteAt:deleteAt onConfirm:^{
        [ws setBusy:YES activeButton:ws.smsLoginButton];
        [IMHTTPService.sharedService restoreAccountWithTicket:ticket completion:^(NSError *error) {
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            [self setBusy:NO activeButton:self.smsLoginButton];
            self.smsFields.codeField.text = @""; // 那枚码已被登录用掉
            if (error) {
                [self showError:IMSMSSubmitErrorMessage(error.code, -1, error.localizedDescription)];
                return;
            }
            IMLogUI(@"login_sms_restored");
            [self showNotice:IMLocalized(@"account.restore.sms_done")];
        }];
    }];
}

#pragma mark - 完善资料

- (void)submitCompleteProfile:(NSString *)nickname {
    NSString *ticket = self.registerTicket, *host = self.registerHost;
    if (ticket.length == 0 || host.length == 0) { [self leaveSubpage]; return; }
    self.completeView.busy = YES;
    [self.completeView showError:nil];
    IMHTTPService.sharedService.host = host;
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService registerPhoneWithTicket:ticket nickname:nickname completion:^(IMSMSLoginResult *result, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || ![self.registerTicket isEqualToString:ticket]) { return; } // 已离开子页
        self.completeView.busy = NO;
        if (result.token.length > 0 && result.userID.length > 0) {
            IMLogUI(@"register_phone_ok");
            self.registerTicket = nil;
            [self enterAppWithHost:host userID:result.userID username:result.username rememberTab:IMLoginTabSMS];
            return;
        }
        IMLogWarnWithTag(IMLogTagUI, @"register_phone_failed code=%ld", (long)error.code);
        NSString *msg = IMSMSSubmitErrorMessage(error.code, -1, IMErrorMessageOrFallback(error, IMLocalized(@"login.error.register_failed")));
        if (error.code == IMErrCodePhoneTicketInvalid || error.code == IMErrCodePhoneTaken) { // 票过期 / 号码被抢注：回登录页
            [self leaveSubpage];
            self.smsFields.codeField.text = @"";
            [self showError:msg];
            return;
        }
        [self.completeView showError:msg]; // 昵称不合规等：票没被消耗，改了直接重交
    }];
}

#pragma mark - 忘记密码

- (void)forgotPasswordTapped {
    if (self.submitting || !IMLoginShowsForgotPassword(self.loginConfig)) { return; }
    IMLoginPhoneFields *rf = self.resetView.phoneFields;
    if (rf.normalizedPhone.length == 0 && self.smsFields.normalizedPhone.length > 0) { // 从验证码登录带号码过来
        rf.countryCode = self.smsFields.countryCode;
        rf.phoneField.text = self.smsFields.phoneField.text;
        [rf.phoneField sendActionsForControlEvents:UIControlEventEditingChanged];
    }
    [self.resetView resetPasswords];
    [self enterSubpage:self.resetView];
    [(rf.normalizedPhone.length > 0 ? rf.codeField : rf.phoneField) becomeFirstResponder];
}

- (void)submitReset {
    IMLoginResetPasswordView *v = self.resetView;
    IMLoginPhoneFields *f = v.phoneFields;
    NSString *code = f.codeField.text ?: @"";
    NSString *localErr = f.normalizedPhone.length == 0 ? @"login.error.phone_required"
                       : code.length == 0 ? @"login.error.code_required"
                       : !IMSMSCodeIsComplete(code) ? @"login.sms_code.six_digits"
                       : IMNewPasswordErrorKey(v.passwordField.text, v.confirmField.text);
    if (localErr) { [v showError:IMLocalized(localErr)]; return; }
    NSString *host = [self resolvedHostOrShowError];
    if (host.length == 0) { return; }
    IMHTTPService.sharedService.host = host;
    NSString *cc = f.countryCode, *phone = f.normalizedPhone, *password = v.passwordField.text;
    [self.view endEditing:YES];
    v.busy = YES;
    [v showError:nil];
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService resetPasswordWithCountryCode:cc phone:phone code:code newPassword:password completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        v.busy = NO;
        if (!error) {
            IMLogUI(@"password_reset_ok phone=%@", IMPhoneMasked(cc, phone));
            [self finishResetWithCountryCode:cc phone:phone];
            return;
        }
        IMLogWarnWithTag(IMLogTagUI, @"password_reset_failed code=%ld", (long)error.code);
        if (error.code == IMErrCodeSMSCodeExpired) { f.codeField.text = @""; }
        [v showError:IMSMSSubmitErrorMessage(error.code, IMSMSAttemptsLeftFromError(error),
                                             IMErrorMessageOrFallback(error, IMLocalized(@"common.action_failed")))];
    }];
}

/// 重设成功：回密码登录页签并预填登录名（非默认地区带 +国家码），清掉重设表单（含号码与验证码）。
- (void)finishResetWithCountryCode:(NSString *)cc phone:(NSString *)phone {
    [self.resetView resetPasswords];
    [self.resetView.phoneFields clearInputs];
    [self leaveSubpage];
    self.registerMode = NO;
    self.touched = YES;
    self.tab = IMLoginTabPassword;
    [self applyMode];
    self.userIDField.text = IMLoginIdentForReset(cc, phone, IMLoginDefaultCountryCode(self.loginConfig));
    self.passwordField.text = @"";
    [self showNotice:IMLocalized(@"reset.done")];
    [self.passwordField becomeFirstResponder];
}

@end
