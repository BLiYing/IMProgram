//  IMTwoStep.m

#import "IMTwoStep.h"
#import "IMLocalization.h"
#import "IMHTTPService+Account.h" // IMParseDeleteAt：秒 / 毫秒 / ISO 容错解析

NSInteger const IMErrCodeTwoStepRequired = 200020;
NSInteger const IMErrCodeTwoStepCodeInvalid = 200021;
NSInteger const IMErrCodeTwoStepTicketInvalid = 200022;
NSInteger const IMErrCodeTwoStepNotEnabled = 200023;
NSInteger const IMErrCodeTwoStepAlreadyEnabled = 200024;
NSInteger const IMErrCodeTwoStepUnavailable = 200025;
NSUInteger const IMTwoStepRecoveryCodeLength = 10;
NSUInteger const IMTwoStepRecoveryInputMaxLength = 12;
NSTimeInterval const IMTwoStepReplayHintWindow = 35;

#pragma mark - 输入清洗

NSString *IMTwoStepSanitizeCode(NSString *raw) {
    if (raw.length == 0) { return @""; }
    NSMutableString *out = [NSMutableString stringWithCapacity:6];
    [raw enumerateSubstringsInRange:NSMakeRange(0, raw.length) options:NSStringEnumerationByComposedCharacterSequences
                         usingBlock:^(NSString *ch, NSRange r, NSRange er, BOOL *stop) {
        unichar c = [ch characterAtIndex:0];
        if (ch.length == 1 && c >= '0' && c <= '9') { [out appendString:ch]; }
        else if (ch.length == 1 && c >= 0xFF10 && c <= 0xFF19) { [out appendFormat:@"%c", (char)('0' + (c - 0xFF10))]; } // 全角数字
        if (out.length >= 6) { *stop = YES; }
    }];
    return out;
}

BOOL IMTwoStepCodeIsComplete(NSString *code) {
    return code.length == 6 && [IMTwoStepSanitizeCode(code) isEqualToString:code];
}

NSString *IMTwoStepNormalizeRecovery(NSString *raw) {
    if (raw.length == 0) { return @""; }
    NSMutableString *s = [[raw lowercaseString] mutableCopy];
    for (NSString *dash in @[@"-", @"‐", @"‑", @"‒", @"–", @"—", @"−"]) {
        [s replaceOccurrencesOfString:dash withString:@"" options:0 range:NSMakeRange(0, s.length)];
    }
    return [[s componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
}

BOOL IMTwoStepRecoveryIsComplete(NSString *raw) {
    return IMTwoStepNormalizeRecovery(raw).length == IMTwoStepRecoveryCodeLength;
}

NSString *IMTwoStepExtractRecoveryCode(NSString *text) {
    if (text.length == 0) { return nil; }
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 前后不能紧挨字母数字（避免从长词里截一段）；两半之间允许一个连字符 / 空白。字符集去掉易混的 0 1 i l o。
        re = [NSRegularExpression regularExpressionWithPattern:@"(?<![a-z0-9])([a-hj-km-np-z2-9]{5})[\\s\\-\u2010-\u2014]?([a-hj-km-np-z2-9]{5})(?![a-z0-9])"
                                                       options:0 error:NULL];
    });
    NSString *lower = [text lowercaseString];
    NSTextCheckingResult *m = [re firstMatchInString:lower options:0 range:NSMakeRange(0, lower.length)];
    if (!m) { return nil; }
    return [[lower substringWithRange:[m rangeAtIndex:1]] stringByAppendingString:[lower substringWithRange:[m rangeAtIndex:2]]];
}

NSString *IMTwoStepFormatRecovery(NSString *normalized) {
    if (normalized.length != IMTwoStepRecoveryCodeLength) { return normalized ?: @""; }
    return [NSString stringWithFormat:@"%@-%@", [normalized substringToIndex:5], [normalized substringFromIndex:5]];
}

BOOL IMTwoStepEditLooksLikePaste(NSString *current, NSRange range, NSString *replacement) {
    if (replacement.length > 1) { return YES; }
    if ([replacement rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) { return YES; }
    NSString *base = current ?: @"";
    return NSMaxRange(range) <= base.length && base.length - range.length + replacement.length > IMTwoStepRecoveryInputMaxLength;
}

BOOL IMTwoStepRecoveryAllowsEdit(NSString *current, NSRange range, NSString *replacement, BOOL marked) {
    if (marked) { return YES; } // 组词期间不干预
    NSString *base = current ?: @"";
    if (NSMaxRange(range) > base.length) { return YES; }
    NSUInteger after = base.length - range.length + replacement.length;
    return after <= IMTwoStepRecoveryInputMaxLength || replacement.length == 0;
}

#pragma mark - 展示

NSString *IMTwoStepGroupSecret(NSString *secret, NSUInteger groupSize, NSUInteger groupsPerLine) {
    NSString *clean = [[[secret ?: @"" stringByReplacingOccurrencesOfString:@" " withString:@""]
                        stringByReplacingOccurrencesOfString:@"-" withString:@""]
                       stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    if (groupSize == 0 || clean.length == 0) { return clean; }
    NSMutableString *out = [NSMutableString string];
    NSUInteger groupIndex = 0;
    for (NSUInteger i = 0; i < clean.length; i += groupSize, groupIndex++) {
        if (groupIndex > 0) {
            BOOL newLine = groupsPerLine > 0 && groupIndex % groupsPerLine == 0;
            [out appendString:newLine ? @"\n" : @" "];
        }
        [out appendString:[clean substringWithRange:NSMakeRange(i, MIN(groupSize, clean.length - i))]];
    }
    return out;
}

NSString *IMTwoStepRecoveryRemainingText(NSInteger remaining) {
    return IMLocalizedFormat(@"twostep.recovery.remaining", [NSString stringWithFormat:@"%ld", (long)MAX(0, remaining)]);
}

BOOL IMTwoStepRecoveryIsLow(NSInteger remaining) {
    return remaining >= 0 && remaining <= 2;
}

NSString *IMTwoStepRecoveryFooter(NSInteger remaining) {
    return IMTwoStepRecoveryIsLow(remaining) ? IMLocalized(@"twostep.recovery.low_footer") : nil;
}

NSString *IMTwoStepRowValueText(NSNumber *enabled) {
    if (!enabled) { return nil; }
    return IMLocalized(enabled.boolValue ? @"twostep.status.on" : @"twostep.status.off");
}

NSString *IMTwoStepRecoveryClipboardText(NSArray<NSString *> *codes) {
    return [codes componentsJoinedByString:@"\n"];
}

NSString *IMTwoStepRecoveryFileText(NSArray<NSString *> *codes) {
    return [NSString stringWithFormat:@"%@\n\n%@\n", IMLocalized(@"twostep.codes.file_header"), IMTwoStepRecoveryClipboardText(codes)];
}

NSArray<NSString *> *IMTwoStepParseRecoveryCodes(id raw) {
    if (![raw isKindOfClass:NSArray.class]) { return @[]; }
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id item in (NSArray *)raw) {
        if ([item isKindOfClass:NSString.class] && [item length] > 0) { [out addObject:item]; }
    }
    return out;
}

#pragma mark - 错误文案

NSString *IMTwoStepErrorMessage(NSInteger code, IMTwoStepErrorContext context, NSInteger attemptsLeft,
                                BOOL recentlyEnabled, NSString *fallback) {
    switch (code) {
        case 200002: return IMLocalized(@"twostep.error.password_wrong");
        case 100002: return IMLocalized(@"twostep.error.rate_limited");
        case IMErrCodeTwoStepAlreadyEnabled: return IMLocalized(@"twostep.error.already_enabled");
        case IMErrCodeTwoStepUnavailable: return IMLocalized(@"twostep.error.unavailable");
        case IMErrCodeTwoStepNotEnabled: return IMLocalized(@"twostep.error.not_enabled");
        case IMErrCodeTwoStepTicketInvalid:
            return IMLocalized(context == IMTwoStepErrorContextLogin ? @"twostep.error.login_expired" : @"twostep.error.expired");
        case IMErrCodeTwoStepCodeInvalid: {
            NSString *base;
            if (context == IMTwoStepErrorContextLogin) {
                base = (attemptsLeft >= 1 && attemptsLeft <= 2)
                    ? IMLocalizedFormat(@"twostep.error.attempts_left", [NSString stringWithFormat:@"%ld", (long)attemptsLeft])
                    : IMLocalized(@"twostep.error.code_invalid_short");
            } else {
                base = IMLocalized(@"twostep.error.code_invalid");
            }
            BOOL replayRelevant = (context == IMTwoStepErrorContextLogin || context == IMTwoStepErrorContextManage);
            if (recentlyEnabled && replayRelevant) {
                return [base stringByAppendingFormat:@"\n%@", IMLocalized(@"twostep.bind.wait_next")];
            }
            return base;
        }
        default: return fallback;
    }
}

BOOL IMTwoStepErrorEndsFlow(NSInteger code, IMTwoStepErrorContext context) {
    return code == IMErrCodeTwoStepTicketInvalid &&
        (context == IMTwoStepErrorContextLogin || context == IMTwoStepErrorContextBind);
}

#pragma mark - 状态机 / 交互条件

IMTwoStepLoginAction IMTwoStepLoginActionForError(NSInteger code, BOOL recoveryMode) {
    if (code == IMErrCodeTwoStepTicketInvalid) { return IMTwoStepLoginActionExpired; }
    return recoveryMode ? IMTwoStepLoginActionShowError : IMTwoStepLoginActionRetryCode;
}

BOOL IMTwoStepShouldAutoSubmit(NSString *code, BOOL busy) {
    return !busy && IMTwoStepCodeIsComplete(code);
}

BOOL IMTwoStepShouldInterceptLeave(BOOL onCodesPage, BOOL completed) {
    return onCodesPage && !completed;
}

BOOL IMTwoStepCanFinish(BOOL savedChecked) { return savedChecked; }

BOOL IMTwoStepCanSubmitVerify(NSString *code, BOOL useRecovery) {
    return useRecovery ? IMTwoStepRecoveryIsComplete(code) : IMTwoStepCodeIsComplete(code);
}

static NSDate *sEnabledAt;

void IMTwoStepMarkEnabledNow(void) {
    @synchronized ([IMTwoStepState class]) { sEnabledAt = [NSDate date]; }
}

BOOL IMTwoStepRecentlyEnabled(NSDate *now) {
    @synchronized ([IMTwoStepState class]) {
        return sEnabledAt && [now timeIntervalSinceDate:sEnabledAt] >= 0
            && [now timeIntervalSinceDate:sEnabledAt] < IMTwoStepReplayHintWindow;
    }
}

#pragma mark - 状态模型

@implementation IMTwoStepState

+ (instancetype)stateFromJSON:(id)json {
    if (![json isKindOfClass:NSDictionary.class]) { return nil; }
    NSDictionary *d = json;
    IMTwoStepState *s = [IMTwoStepState new];
    s.enabled = [d[@"enabled"] respondsToSelector:@selector(boolValue)] && [d[@"enabled"] boolValue];
    s.enabledAt = IMParseDeleteAt(d[@"enabled_at"]);
    id rem = d[@"recovery_remaining"];
    s.recoveryRemaining = [rem isKindOfClass:NSNumber.class] ? [rem integerValue] : -1;
    return s;
}

- (NSString *)enabledSinceText {
    if (!self.enabledAt) { return nil; }
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = IMLocalization.shared.locale;
    f.dateStyle = NSDateFormatterLongStyle;
    f.timeStyle = NSDateFormatterNoStyle;
    return IMLocalizedFormat(@"twostep.on.since", [f stringFromDate:self.enabledAt]);
}

@end
