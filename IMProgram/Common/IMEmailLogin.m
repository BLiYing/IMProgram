//  IMEmailLogin.m

#import "IMEmailLogin.h"
#import "IMLocalization.h"
#import "IMTwoStep.h"

NSInteger const IMErrCodeEmailInvalid = 200030;
NSInteger const IMErrCodeEmailTaken = 200031;
NSInteger const IMErrCodeEmailCodeInvalid = 200032;
NSInteger const IMErrCodeEmailCodeExpired = 200033;
NSInteger const IMErrCodeEmailNotBound = 200034;
NSInteger const IMErrCodeEmailUnchanged = 200035;
NSInteger const IMErrCodeEmailUnavailable = 200036;
NSInteger const IMErrCodeEmailSendFailed = 200037;
NSUInteger const IMEmailMaxLength = 254;
NSInteger const IMEmailResendDefaultSeconds = 60;

#pragma mark - 邮箱

NSString *IMEmailTrim(NSString *raw) {
    return [(raw ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

BOOL IMEmailPrecheck(NSString *raw) {
    NSString *s = IMEmailTrim(raw);
    if (s.length == 0 || s.length > IMEmailMaxLength) { return NO; }
    if ([s rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) { return NO; }
    NSArray<NSString *> *parts = [s componentsSeparatedByString:@"@"];
    if (parts.count != 2 || parts[0].length == 0) { return NO; }
    NSString *domain = parts[1];
    return [domain containsString:@"."] && ![domain hasPrefix:@"."] && ![domain hasSuffix:@"."];
}

NSString *IMEmailMasked(NSString *email) {
    NSRange at = [email ?: @"" rangeOfString:@"@" options:NSBackwardsSearch];
    if (at.location == NSNotFound || at.location == 0) { return @"***"; }
    NSString *local = [email substringToIndex:at.location];
    NSString *domain = [email substringFromIndex:at.location];
    NSString *head = local.length > 1 ? [[local substringToIndex:1] stringByAppendingString:@"***"] : @"*";
    return [head stringByAppendingString:domain];
}

NSString *IMEmailAPILang(void) {
    return [IMLocalization.shared.language isEqualToString:IMLanguagePrefEnglish] ? @"en" : @"zh-Hans";
}

#pragma mark - 错误

NSString *IMEmailErrorMessage(NSInteger code, NSInteger attemptsLeft, NSInteger retryAfterSec, NSString *fallback) {
    switch (code) {
        case 200002: return IMLocalized(@"email.err.password");
        case 200030: return IMLocalized(@"email.err.invalid");
        case 200031: return IMLocalized(@"email.err.taken");
        case 200032:
            if (attemptsLeft >= 1 && attemptsLeft <= 2) {
                return IMLocalizedFormat(@"email.code.wrong_left", [NSString stringWithFormat:@"%ld", (long)attemptsLeft]);
            }
            return IMLocalized(@"email.code.wrong");
        case 200033: return IMLocalized(@"email.code.expired");
        case 200034: return IMLocalized(@"email.err.not_bound");
        case 200035: return IMLocalized(@"email.err.same");
        case 200036: return IMLocalized(@"email.err.unavailable");
        case 200037: return IMLocalized(@"email.err.send_failed");
        case 100002:
            if (retryAfterSec > 0) {
                return IMLocalizedFormat(@"email.err.too_frequent_secs", [NSString stringWithFormat:@"%ld", (long)retryAfterSec]);
            }
            return IMLocalized(@"email.err.too_frequent");
        default: return fallback;
    }
}

IMEmailFormTarget IMEmailFormTargetForError(NSInteger code) {
    switch (code) {
        case 200002: return IMEmailFormTargetPassword;
        case 200030: case 200031: case 200035: return IMEmailFormTargetEmail;
        default: return IMEmailFormTargetNone;
    }
}

IMEmailCodeAction IMEmailCodeActionForError(NSInteger code) {
    if (code == IMErrCodeEmailCodeInvalid) { return IMEmailCodeActionClearAndRefocus; }
    if (code == IMErrCodeEmailCodeExpired) { return IMEmailCodeActionExpired; }
    return IMEmailCodeActionShowError;
}

#pragma mark - 重发倒计时

NSInteger IMEmailResendRemaining(NSDate *deadline, NSDate *now) {
    if (!deadline) { return 0; }
    NSTimeInterval left = [deadline timeIntervalSinceDate:now];
    return left > 0 ? (NSInteger)ceil(left) : 0;
}

NSDate *IMEmailResendDeadline(NSInteger serverSeconds, NSDate *now) {
    NSInteger secs = serverSeconds < 0 ? IMEmailResendDefaultSeconds : serverSeconds;
    return [now dateByAddingTimeInterval:secs];
}

NSString *IMEmailResendTitle(NSInteger remaining) {
    if (remaining > 0) {
        return IMLocalizedFormat(@"email.code.resend_wait", [NSString stringWithFormat:@"%ld", (long)remaining]);
    }
    return IMLocalized(@"email.code.resend");
}

BOOL IMEmailShouldAutoSubmit(NSString *code, BOOL busy) {
    return !busy && IMTwoStepCodeIsComplete(code);
}

#pragma mark - 状态模型

NSDate *IMEmailDateFromTimestamp(double ts) {
    return [NSDate dateWithTimeIntervalSince1970:ts > 1e11 ? ts / 1000.0 : ts];
}

@implementation IMEmailState

+ (instancetype)stateFromJSON:(id)json {
    if (![json isKindOfClass:NSDictionary.class]) { return nil; }
    NSDictionary *d = json;
    IMEmailState *s = [IMEmailState new];
    s.available = [d[@"available"] respondsToSelector:@selector(boolValue)] ? [d[@"available"] boolValue] : YES;
    NSString *email = [d[@"email"] isKindOfClass:NSString.class] ? d[@"email"] : nil;
    s.bound = [d[@"bound"] respondsToSelector:@selector(boolValue)] && [d[@"bound"] boolValue] && email.length > 0;
    if (s.bound) {
        s.email = email;
        if ([d[@"verified_at"] respondsToSelector:@selector(doubleValue)] && [d[@"verified_at"] doubleValue] > 0) {
            s.verifiedAt = IMEmailDateFromTimestamp([d[@"verified_at"] doubleValue]);
        }
    }
    return s;
}

+ (instancetype)boundStateFromVerifyJSON:(id)json {
    NSDictionary *d = [json isKindOfClass:NSDictionary.class] ? json : nil;
    NSString *email = [d[@"email"] isKindOfClass:NSString.class] ? d[@"email"] : nil;
    if (email.length == 0) { return nil; }
    IMEmailState *s = [IMEmailState new];
    s.available = YES;
    s.bound = YES;
    s.email = email;
    if ([d[@"verified_at"] respondsToSelector:@selector(doubleValue)] && [d[@"verified_at"] doubleValue] > 0) {
        s.verifiedAt = IMEmailDateFromTimestamp([d[@"verified_at"] doubleValue]);
    }
    return s;
}

- (NSString *)boundSinceText {
    if (!self.verifiedAt) { return nil; }
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = IMLocalization.shared.locale;
    f.dateStyle = NSDateFormatterLongStyle;
    f.timeStyle = NSDateFormatterNoStyle;
    return IMLocalizedFormat(@"email.bound.since", [f stringFromDate:self.verifiedAt]);
}

@end

NSString *IMEmailRowValueText(IMEmailState *state) {
    if (!state) { return nil; }
    return state.bound ? state.email : IMLocalized(@"email.status.unbound");
}
