//  IMHTTPService+Email.m

#import "IMHTTPService+Email.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"

NSString * const IMErrorEmailAttemptsLeftKey = @"im_email_attempts_left";
NSString * const IMErrorEmailRetryAfterKey = @"im_email_retry_after";

NSError *IMErrorByAttachingEmailInfo(NSError *error, NSDictionary *body) {
    NSDictionary *data = [body[@"data"] isKindOfClass:NSDictionary.class] ? body[@"data"] : nil;
    if (!error || !data) { return error; }
    NSNumber *left = [data[@"attempts_left"] isKindOfClass:NSNumber.class] ? data[@"attempts_left"] : nil;
    NSNumber *retry = [data[@"retry_after_sec"] isKindOfClass:NSNumber.class] ? data[@"retry_after_sec"] : nil;
    if (!left && !retry) { return error; }
    NSMutableDictionary *info = [error.userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
    if (left) { info[IMErrorEmailAttemptsLeftKey] = left; }
    if (retry) { info[IMErrorEmailRetryAfterKey] = retry; }
    return [NSError errorWithDomain:error.domain code:error.code userInfo:info];
}

static NSInteger IMEmailIntFromError(NSError *error, NSString *key) {
    id v = error.userInfo[key];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : -1;
}
NSInteger IMEmailAttemptsLeftFromError(NSError *error) { return IMEmailIntFromError(error, IMErrorEmailAttemptsLeftKey); }
NSInteger IMEmailRetryAfterFromError(NSError *error) { return IMEmailIntFromError(error, IMErrorEmailRetryAfterKey); }

@implementation IMEmailSendResult
@end

@implementation IMHTTPService (Email)

/// 发请求并整包解信封：code != 0 → 带业务码的错误（附 attempts_left / retry_after_sec）；信封缺 code 当失败，不当成功。
- (void)runEmailRequest:(nullable NSURLRequest *)req completion:(void (^)(id _Nullable data, NSError *_Nullable error))completion {
    if (!req) {
        [self callOnMain:^{ completion(nil, [self errorWithMessage:IMLocalized(@"net.error.invalid_server")]); }];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self runRequest:req completion:^(NSDictionary *body, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) { [self callOnMain:^{ completion(nil, error); }]; return; }
        BOOL hasCode = [body[@"code"] isKindOfClass:NSNumber.class] || [body[@"code"] isKindOfClass:NSString.class];
        NSInteger code = hasCode ? [body[@"code"] integerValue] : -1;
        if (code == 0) { [self callOnMain:^{ completion(body[@"data"], nil); }]; return; }
        NSError *err = [self errorWithCode:code message:[self messageFrom:body fallback:IMLocalized(@"common.action_failed")]];
        err = IMErrorByAttachingEmailInfo(err, body);
        [self callOnMain:^{ completion(nil, err); }];
    }];
}

- (void)fetchEmailStateWithToken:(NSString *)token completion:(void (^)(IMEmailState *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/email" method:@"GET" token:token body:nil];
    [self runEmailRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        IMEmailState *state = [IMEmailState stateFromJSON:data];
        completion(state, state ? nil : [self errorWithMessage:IMLocalized(@"common.action_failed")]);
    }];
}

- (void)sendEmailCodeWithToken:(NSString *)token email:(NSString *)email password:(NSString *)password
                    completion:(void (^)(IMEmailSendResult *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/email/send-code" method:@"POST" token:token
                                                     body:@{ @"email": email ?: @"", @"password": password ?: @"",
                                                             @"lang": IMEmailAPILang() }];
    [self runEmailRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *d = [data isKindOfClass:NSDictionary.class] ? data : nil;
        IMEmailSendResult *r = [IMEmailSendResult new];
        r.expiresIn = [d[@"expires_in"] respondsToSelector:@selector(integerValue)] ? [d[@"expires_in"] integerValue] : 600;
        r.resendAfter = [d[@"resend_after"] respondsToSelector:@selector(integerValue)] ? [d[@"resend_after"] integerValue]
                                                                                       : IMEmailResendDefaultSeconds;
        completion(r, nil);
    }];
}

- (void)verifyEmailWithToken:(NSString *)token email:(NSString *)email code:(NSString *)code
                  completion:(void (^)(IMEmailState *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/email/verify" method:@"POST" token:token
                                                     body:@{ @"email": email ?: @"", @"code": code ?: @"",
                                                             @"lang": IMEmailAPILang() }];
    [self runEmailRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        IMEmailState *bound = [IMEmailState boundStateFromVerifyJSON:data];
        completion(bound, bound ? nil : [self errorWithMessage:IMLocalized(@"common.action_failed")]);
    }];
}

- (void)unbindEmailWithToken:(NSString *)token password:(NSString *)password completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/email/unbind" method:@"POST" token:token
                                                     body:@{ @"password": password ?: @"" }];
    [self runEmailRequest:req completion:^(id data, NSError *error) { completion(error); }];
}

@end
