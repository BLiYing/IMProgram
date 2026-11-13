//  IMHTTPService+Email.m

#import "IMHTTPService+Email.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"
#import "IMHTTPService+Phone.h"

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

- (void)fetchEmailStateWithToken:(NSString *)token completion:(void (^)(IMEmailState *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/email" method:@"GET" token:token body:nil];
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        IMEmailState *state = [IMEmailState stateFromJSON:data];
        completion(state, state ? nil : [self errorWithMessage:IMLocalized(@"common.action_failed")]);
    }];
}

- (void)sendEmailCodeWithToken:(NSString *)token email:(NSString *)email proof:(IMIdentityProof *)proof
                    completion:(void (^)(IMEmailSendResult *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/email/send-code" method:@"POST" token:token
                                                     body:@{ @"email": email ?: @"", @"proof": [proof JSONObject],
                                                             @"lang": IMEmailAPILang() }];
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) {
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
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        IMEmailState *bound = [IMEmailState boundStateFromVerifyJSON:data];
        completion(bound, bound ? nil : [self errorWithMessage:IMLocalized(@"common.action_failed")]);
    }];
}

- (void)unbindEmailWithToken:(NSString *)token proof:(IMIdentityProof *)proof completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/email/unbind" method:@"POST" token:token
                                                     body:@{ @"proof": [proof JSONObject] }];
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) { completion(error); }];
}

@end
