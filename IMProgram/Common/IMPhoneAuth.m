//  IMPhoneAuth.m

#import "IMPhoneAuth.h"
#import "IMLocalization.h"
#import "IMTwoStep.h"
#import "IMHTTPService.h" // IMFriendlyMessageForCode

NSInteger const IMErrCodeRateLimited = 100002;
NSInteger const IMErrCodeWrongPassword = 200002;
NSInteger const IMErrCodeSMSUnavailable = 200040;
NSInteger const IMErrCodePhoneInvalid = 200041;
NSInteger const IMErrCodePhoneTaken = 200042;
NSInteger const IMErrCodeSMSCodeInvalid = 200043;
NSInteger const IMErrCodeSMSCodeExpired = 200044;
NSInteger const IMErrCodeSMSSendFailed = 200045;
NSInteger const IMErrCodeSMSDailyCap = 200046;
NSInteger const IMErrCodePhoneNotRegistered = 200047;
NSInteger const IMErrCodePhoneTicketInvalid = 200048;
NSInteger const IMErrCodeProofRequired = 200049;
NSInteger const IMProofRecentAuthMinSec = 15;

NSUInteger const IMSMSCodeLength = 6;
NSInteger const IMSMSResendDefaultSeconds = 60;
NSUInteger const IMPasswordMinLength = 6;
NSString * const IMPhoneDefaultCountryCode = @"86";
NSString * const IMRegisterMethodUsername = @"username";
NSString * const IMRegisterMethodPhone = @"phone";

static NSString * const kIMLoginTabDefaultsKey = @"im.login.tab";

NSString *IMPhoneAuthFriendlyMessage(NSInteger code) {
    if (code < IMErrCodeSMSUnavailable || code > IMErrCodePhoneTicketInvalid) { return nil; }
    return IMFriendlyMessageForCode(code); // 文案表只在 HTTP 层一份
}

#pragma mark - proof

@interface IMIdentityProof ()
@property (nonatomic, assign, readwrite) BOOL isSMS;
@property (nonatomic, assign, readwrite) BOOL isEmpty;
@property (nonatomic, copy, readwrite) NSString *secret;
@end

@implementation IMIdentityProof
+ (instancetype)passwordProof:(NSString *)password {
    IMIdentityProof *p = [IMIdentityProof new];
    p.secret = password ?: @"";
    return p;
}
+ (instancetype)smsProof:(NSString *)code {
    IMIdentityProof *p = [IMIdentityProof new];
    p.isSMS = YES;
    p.secret = code ?: @"";
    return p;
}
+ (instancetype)emptyProof {
    IMIdentityProof *p = [IMIdentityProof new];
    p.isEmpty = YES;
    p.secret = @"";
    return p;
}
- (BOOL)isReusable { return !self.isSMS && !self.isEmpty; }
- (NSDictionary<NSString *, NSString *> *)JSONObject {
    if (self.isEmpty) { return @{}; }
    return self.isSMS ? @{ @"sms_code": self.secret } : @{ @"password": self.secret };
}
- (NSString *)description { // 不带原文
    return self.isEmpty ? @"<proof empty>" : (self.isSMS ? @"<proof sms>" : @"<proof password>");
}
@end

NSDictionary *IMBodyWithProof(NSDictionary *body, IMIdentityProof *proof) {
    if (proof.isEmpty) { return body ?: @{}; }
    NSMutableDictionary *d = [body mutableCopy] ?: [NSMutableDictionary dictionary];
    d[@"proof"] = [proof JSONObject];
    return d;
}

#pragma mark - public-config

@interface IMSMSRegion ()
@property (nonatomic, copy, readwrite) NSString *code;
@property (nonatomic, copy, readwrite) NSString *iso;
@end
@implementation IMSMSRegion
+ (instancetype)regionWithCode:(NSString *)code iso:(NSString *)iso {
    IMSMSRegion *r = [IMSMSRegion new];
    r.code = code ?: @"";
    r.iso = iso ?: @"";
    return r;
}
@end

@interface IMLoginConfig ()
@property (nonatomic, assign, readwrite) BOOL registerEnabled;
@property (nonatomic, assign, readwrite) BOOL smsAvailable;
@property (nonatomic, copy, readwrite) NSArray<IMSMSRegion *> *smsRegions;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *registerMethods;
@end

@implementation IMLoginConfig

+ (instancetype)fallbackConfig {
    IMLoginConfig *c = [IMLoginConfig new];
    c.registerEnabled = YES;
    c.smsAvailable = NO;
    c.smsRegions = @[];
    c.registerMethods = @[IMRegisterMethodUsername];
    return c;
}

+ (instancetype)configFromResponseData:(NSData *)data {
    IMLoginConfig *c = [self fallbackConfig];
    id root = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![root isKindOfClass:NSDictionary.class]) { return c; }
    id code = root[@"code"];
    if (![code isKindOfClass:NSNumber.class] || [code integerValue] != 0) { return c; }
    NSDictionary *d = [root[@"data"] isKindOfClass:NSDictionary.class] ? root[@"data"] : nil;
    if (!d) { return c; }
    if ([d[@"register_enabled"] isKindOfClass:NSNumber.class]) { c.registerEnabled = [d[@"register_enabled"] boolValue]; }
    if ([d[@"sms_available"] isKindOfClass:NSNumber.class]) { c.smsAvailable = [d[@"sms_available"] boolValue]; }
    NSMutableArray<IMSMSRegion *> *regions = [NSMutableArray array];
    for (id r in [d[@"sms_regions"] isKindOfClass:NSArray.class] ? d[@"sms_regions"] : @[]) {
        if (![r isKindOfClass:NSDictionary.class]) { continue; }
        id rc = r[@"code"];
        NSString *cc = [rc isKindOfClass:NSString.class] ? rc : ([rc isKindOfClass:NSNumber.class] ? [rc stringValue] : nil);
        if (cc.length == 0) { continue; }
        [regions addObject:[IMSMSRegion regionWithCode:cc iso:[r[@"iso"] isKindOfClass:NSString.class] ? r[@"iso"] : @""]];
    }
    c.smsRegions = regions;
    if (!c.smsAvailable) { c.smsRegions = @[]; }
    if ([d[@"register_methods"] isKindOfClass:NSArray.class]) {
        NSMutableArray<NSString *> *methods = [NSMutableArray array];
        for (id m in d[@"register_methods"]) { if ([m isKindOfClass:NSString.class]) { [methods addObject:m]; } }
        c.registerMethods = methods;
    }
    return c;
}

@end

#pragma mark - security

@implementation IMLegacyPhone
+ (instancetype)legacyPhoneFromJSON:(id)json {
    if (![json isKindOfClass:NSDictionary.class]) { return nil; }
    NSDictionary *d = json;
    id cc = d[@"country_code"], phone = d[@"phone"], masked = d[@"masked"];
    if (![cc isKindOfClass:NSString.class] || [cc length] == 0 || ![phone isKindOfClass:NSString.class] || [phone length] == 0) {
        return nil;
    }
    IMLegacyPhone *p = [IMLegacyPhone new];
    p.countryCode = cc;
    p.phone = phone;
    p.masked = [masked isKindOfClass:NSString.class] && [masked length] > 0 ? masked : IMPhoneMasked(cc, phone);
    return p;
}
- (NSString *)description { return [NSString stringWithFormat:@"<legacy_phone %@>", self.masked]; } // 不带明文
@end

@implementation IMSecurityState
+ (instancetype)stateFromJSON:(id)json {
    if (![json isKindOfClass:NSDictionary.class]) { return nil; }
    NSDictionary *d = json;
    IMSecurityState *s = [IMSecurityState new];
    s.phoneBound = [d[@"phone_bound"] isKindOfClass:NSNumber.class] && [d[@"phone_bound"] boolValue];
    s.phoneMasked = [d[@"phone_masked"] isKindOfClass:NSString.class] && [d[@"phone_masked"] length] > 0 ? d[@"phone_masked"] : nil;
    s.passwordSet = [d[@"password_set"] isKindOfClass:NSNumber.class] ? [d[@"password_set"] boolValue] : YES;
    s.smsAvailable = [d[@"sms_available"] isKindOfClass:NSNumber.class] && [d[@"sms_available"] boolValue];
    s.recentAuthSec = [d[@"recent_auth_sec"] isKindOfClass:NSNumber.class] ? MAX(0, [d[@"recent_auth_sec"] integerValue]) : 0;
    s.legacyPhone = [IMLegacyPhone legacyPhoneFromJSON:d[@"legacy_phone"]];
    return s;
}
@end

#pragma mark - 登录页

NSArray<NSNumber *> *IMLoginTabsForConfig(IMLoginConfig *config) {
    return config.smsAvailable ? @[@(IMLoginTabSMS), @(IMLoginTabPassword)] : @[@(IMLoginTabPassword)];
}

IMLoginTab IMLoginInitialTab(NSArray<NSNumber *> *tabs, IMLoginTab remembered) {
    if (remembered != IMLoginTabNone && [tabs containsObject:@(remembered)]) { return remembered; }
    return tabs.count > 0 ? (IMLoginTab)tabs.firstObject.integerValue : IMLoginTabPassword;
}

IMLoginTab IMLoginTabAfterConfig(IMLoginTab current, BOOL touched, NSArray<NSNumber *> *tabs, IMLoginTab remembered) {
    if (touched && [tabs containsObject:@(current)]) { return current; }
    return IMLoginInitialTab(tabs, remembered);
}

BOOL IMLoginShowsForgotPassword(IMLoginConfig *config) { return config.smsAvailable; }
BOOL IMLoginShowsUsernameRegister(IMLoginConfig *config) {
    return !config || [config.registerMethods containsObject:IMRegisterMethodUsername];
}
BOOL IMLoginShowsAutoRegisterHint(IMLoginConfig *config) { return [config.registerMethods containsObject:IMRegisterMethodPhone]; }
BOOL IMLoginShowsRegionPicker(IMLoginConfig *config) { return config.smsRegions.count > 1; }

NSString *IMLoginDefaultCountryCode(IMLoginConfig *config) {
    return config.smsRegions.firstObject.code ?: IMPhoneDefaultCountryCode;
}

BOOL IMLoginShouldResetCountryCode(BOOL hostChanged, NSString *current, IMLoginConfig *config) {
    if (hostChanged) { return YES; }
    if (config.smsRegions.count == 0) { return NO; }
    for (IMSMSRegion *r in config.smsRegions) { if ([r.code isEqualToString:current]) { return NO; } }
    return YES;
}

NSString *IMLoginIdentForReset(NSString *countryCode, NSString *phone, NSString *defaultCountryCode) {
    NSString *p = IMPhoneNationalNumber(countryCode, phone);
    if ([p hasPrefix:@"+"]) { return p; } // 粘贴的是别的国家码：已是完整国际号码，不再拼一遍
    return [countryCode isEqualToString:defaultCountryCode] ? p : [NSString stringWithFormat:@"+%@%@", countryCode, p];
}

static BOOL IMLoginTabIsRememberable(NSInteger tab) { return tab == IMLoginTabSMS || tab == IMLoginTabPassword; }

IMLoginTab IMLoginRememberedTab(NSUserDefaults *defaults) {
    id v = [defaults objectForKey:kIMLoginTabDefaultsKey];
    if (![v isKindOfClass:NSNumber.class]) { return IMLoginTabNone; }
    NSInteger t = [v integerValue];
    return IMLoginTabIsRememberable(t) ? (IMLoginTab)t : IMLoginTabNone;
}

void IMLoginRememberTab(NSUserDefaults *defaults, IMLoginTab tab) {
    if (!IMLoginTabIsRememberable(tab)) { return; }
    [defaults setInteger:tab forKey:kIMLoginTabDefaultsKey];
}

NSString *IMSMSRegionTitle(IMSMSRegion *region, NSLocale *locale) {
    NSString *name = region.iso.length > 0 ? [locale localizedStringForCountryCode:region.iso] : nil;
    return [NSString stringWithFormat:@"%@ +%@", name.length > 0 ? name : (region.iso.length > 0 ? region.iso : @""), region.code];
}

#pragma mark - 号码 / 验证码

NSString *IMPhoneNormalize(NSString *raw) {
    if (raw.length == 0) { return @""; }
    NSMutableString *out = [NSMutableString stringWithCapacity:raw.length];
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar c = [raw characterAtIndex:i];
        if (c == '-' || [ws characterIsMember:c]) { continue; }
        [out appendFormat:@"%C", c];
    }
    return out;
}

NSString *IMPhoneNationalNumber(NSString *countryCode, NSString *raw) {
    NSString *p = IMPhoneNormalize(raw);
    if (countryCode.length == 0) { return p; }
    NSString *prefix = [@"+" stringByAppendingString:countryCode];
    return [p hasPrefix:prefix] ? [p substringFromIndex:prefix.length] : p;
}

NSString *IMPhoneMasked(NSString *countryCode, NSString *raw) {
    NSString *p = IMPhoneNormalize(raw);
    if ([p hasPrefix:@"+"]) { p = [p substringFromIndex:1]; }
    NSUInteger n = p.length;
    NSString *body;
    if (n < 7) {
        body = [@"" stringByPaddingToLength:n withString:@"*" startingAtIndex:0];
    } else {
        NSString *stars = [@"" stringByPaddingToLength:n - 7 withString:@"*" startingAtIndex:0];
        body = [NSString stringWithFormat:@"%@%@%@", [p substringToIndex:3], stars, [p substringFromIndex:n - 4]];
    }
    return [NSString stringWithFormat:@"+%@ %@", countryCode ?: @"", body];
}

// 与两步验证同一套 6 位码清洗（含全角数字折算），不另写。
NSString *IMSMSCodeSanitize(NSString *raw) { return IMTwoStepSanitizeCode(raw); }
BOOL IMSMSCodeIsComplete(NSString *code) { return IMTwoStepCodeIsComplete(code); }

NSString *IMNewPasswordErrorKey(NSString *password, NSString *confirm) {
    if (password.length < IMPasswordMinLength) { return @"reset.too_short"; }
    if (![password isEqualToString:confirm ?: @""]) { return @"reset.mismatch"; }
    return nil;
}

#pragma mark - 错误

NSString *IMErrorMessageOrFallback(NSError *error, NSString *fallback) {
    NSString *desc = error.localizedDescription;
    return desc.length > 0 ? desc : fallback;
}

NSString *IMSMSSendErrorMessage(NSInteger code, NSInteger retryAfterSec, NSString *fallback) {
    if (code == IMErrCodeRateLimited) {
        return retryAfterSec > 0 ? IMLocalizedFormat(@"sms.err.too_frequent_secs", (long)retryAfterSec)
                                 : IMLocalized(@"sms.err.too_frequent");
    }
    return IMPhoneAuthFriendlyMessage(code) ?: fallback;
}

NSString *IMSMSSubmitErrorMessage(NSInteger code, NSInteger attemptsLeft, NSString *fallback) {
    if (code == IMErrCodeSMSCodeInvalid && attemptsLeft >= 0) { return IMLocalizedFormat(@"err.200043.left", (long)attemptsLeft); }
    if (code == IMErrCodeWrongPassword) { return IMLocalized(@"err.200002"); }
    return IMPhoneAuthFriendlyMessage(code) ?: fallback;
}

NSInteger IMSMSCountdownAfterFailure(NSInteger code, NSInteger retryAfterSec) {
    if ((code == IMErrCodeRateLimited || code == IMErrCodeSMSCodeExpired) && retryAfterSec > 0) { return retryAfterSec; }
    return -1;
}

BOOL IMProofErrorStaysInSheet(NSInteger code, NSString *field) {
    if ([field isEqualToString:@"code"]) { return NO; }
    if (code == IMErrCodeRateLimited) { return NO; }
    if ([field isEqualToString:@"proof"]) { return YES; }
    return code == IMErrCodeWrongPassword || code == IMErrCodeSMSCodeInvalid || code == IMErrCodeSMSCodeExpired;
}

#pragma mark - 确认身份弹层

NSArray<NSNumber *> *IMProofTabsForState(IMSecurityState *state) {
    if (!state) { return @[@(IMProofTabPassword)]; } // 取不到状态：老账号都有密码
    BOOL sms = state.phoneBound && state.smsAvailable;
    if (state.passwordSet) { return sms ? @[@(IMProofTabPassword), @(IMProofTabSMS)] : @[@(IMProofTabPassword)]; }
    // 没设密码：只能验证码；短信不可用 / 没绑手机时没有可用方式（退回密码页签用户永远过不去）。
    return sms ? @[@(IMProofTabSMS)] : @[];
}

BOOL IMProofShowsSegments(NSArray<NSNumber *> *tabs) { return tabs.count > 1; }

BOOL IMProofSkipsSheet(IMSecurityState *state) { return state != nil && state.recentAuthSec >= IMProofRecentAuthMinSec; }

void IMProofRunWithoutSheet(IMSecurityState *state, IMProofSubmitBlock submit, void (^ask)(void), IMProofCompletion completion) {
    if (!IMProofSkipsSheet(state)) { ask(); return; }
    __block BOOL finished = NO;
    submit([IMIdentityProof emptyProof], ^(NSError *error) {
        if (finished) { return; }
        finished = YES;
        if (!error) { completion(YES, nil); return; }
        if (error.code == IMErrCodeProofRequired) { ask(); return; } // 边界上刚好过期：照常弹层
        completion(NO, error);
    });
}

BOOL IMProofCanConfirm(IMProofTab tab, NSString *password, NSString *code, BOOL busy) {
    if (busy) { return NO; }
    return tab == IMProofTabPassword ? password.length > 0 : IMSMSCodeIsComplete(code);
}

@interface IMProofCodeCache ()
@property (nonatomic, copy, readwrite, nullable) NSString *code;
@end

@implementation IMProofCodeCache
- (void)noteSucceeded { self.code = nil; }
- (void)notePageErrorAfterProof:(IMIdentityProof *)proof {
    if (proof.isSMS && IMSMSCodeIsComplete(proof.secret)) { self.code = proof.secret; }
}
- (void)noteProofRejected:(IMIdentityProof *)proof {
    if (proof.isSMS) { self.code = nil; }
}
- (void)noteCancelledWithTypedCode:(NSString *)typed tabWasSMS:(BOOL)tabWasSMS {
    if (!tabWasSMS) { return; }
    self.code = IMSMSCodeIsComplete(typed) ? typed : nil;
}
- (void)noteResent { self.code = nil; }
@end

#pragma mark - 倒计时

@interface IMResendClock ()
@property (nonatomic, strong, readwrite, nullable) NSDate *deadline;
@property (nonatomic, assign, readwrite) BOOL sentOnce;
@property (nonatomic, copy, readwrite, nullable) NSString *owner;
@end

@implementation IMResendClock
- (void)followTarget:(NSString *)target {
    if ((target == nil && self.owner == nil) || [target isEqualToString:self.owner]) { return; }
    self.owner = target;
    self.deadline = nil;
    self.sentOnce = NO;
}
- (NSInteger)secondsLeftAt:(NSDate *)now {
    if (!self.deadline) { return 0; }
    NSTimeInterval left = [self.deadline timeIntervalSinceDate:now];
    return left <= 0 ? 0 : (NSInteger)ceil(left);
}
- (void)noteSentWithResendAfter:(NSInteger)resendAfter now:(NSDate *)now {
    self.sentOnce = YES;
    self.deadline = [now dateByAddingTimeInterval:resendAfter < 0 ? IMSMSResendDefaultSeconds : resendAfter];
}
- (void)noteFailureCode:(NSInteger)code retryAfter:(NSInteger)retryAfter now:(NSDate *)now {
    NSInteger secs = IMSMSCountdownAfterFailure(code, retryAfter);
    if (secs > 0) { self.deadline = [now dateByAddingTimeInterval:secs]; }
}
@end

NSString *IMSMSSendButtonTitle(NSInteger secondsLeft, BOOL sentOnce) {
    if (secondsLeft > 0) { return IMLocalizedFormat(@"login.sms_code.resend_in", (long)secondsLeft); }
    return IMLocalized(sentOnce ? @"login.sms_code.resend" : @"login.sms_code.send");
}

#pragma mark - 隐私与安全

BOOL IMSecurityShowsPhoneRow(IMSecurityState *state) { return state && (state.phoneBound || state.smsAvailable); }

NSString *IMSecurityPhoneRowValue(IMSecurityState *state) {
    if (!state) { return nil; }
    return state.phoneBound ? (state.phoneMasked ?: @"") : IMLocalized(@"security.phone.unbound");
}

NSString *IMSecurityPasswordRowValue(IMSecurityState *state) {
    if (!state) { return nil; }
    return IMLocalized(state.passwordSet ? @"security.password.set" : @"security.password.unset");
}

IMPhoneRowAction IMSecurityPhoneRowAction(IMSecurityState *state) {
    if (!state.smsAvailable) { return IMPhoneRowActionSMSUnavailable; }
    return state.phoneBound ? IMPhoneRowActionChange : IMPhoneRowActionBind;
}

IMLegacyPhone *IMSecurityLegacyPhonePrompt(IMSecurityState *state) { return state.phoneBound ? nil : state.legacyPhone; }

BOOL IMSecurityPasswordPageIsSet(IMSecurityState *state) { return state != nil && !state.passwordSet; }
BOOL IMSecurityCanChangePasswordBySMS(IMSecurityState *state) { return state.phoneBound && state.smsAvailable; }

IMPasswordProofMode IMSecurityPasswordProofMode(BOOL setMode, BOOL switchedToSMS, IMSecurityState *state) {
    if (setMode) { return IMPasswordProofModeSMS; }
    if (switchedToSMS && IMSecurityCanChangePasswordBySMS(state)) { return IMPasswordProofModeSMS; }
    return IMPasswordProofModeOldPassword;
}

#pragma mark - 用户名

BOOL IMLooksLikePhoneIdentifier(NSString *value) {
    if ([value hasPrefix:@"+"]) { return YES; }
    if (value.length < 5 || value.length > 15) { return NO; }
    return [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
}

BOOL IMStoredUsernameIsTrusted(NSString *username) {
    NSUInteger n = username.length;
    if (n < 5 || n > 32) { return NO; }
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [username characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || c == '_')) { return NO; }
    }
    return !IMLooksLikePhoneIdentifier(username);
}

NSString *IMUsernameAfterLoginResponse(NSString *current, NSString *serverValue, NSString *storedValue, BOOL storedFromServer) {
    if (serverValue.length > 0) { return serverValue; }
    if (storedFromServer && current.length > 0 && [current isEqualToString:storedValue]) { return current; }
    return IMStoredUsernameIsTrusted(current) ? current : nil;
}
