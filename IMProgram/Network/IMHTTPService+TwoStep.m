//  IMHTTPService+TwoStep.m

#import "IMHTTPService+TwoStep.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"

NSString * const IMErrorTwoStepTicketKey = @"im_twostep_ticket";
NSString * const IMErrorTwoStepAttemptsLeftKey = @"im_twostep_attempts_left";

NSError *IMErrorByAttachingTwoStepInfo(NSError *error, NSDictionary *body) {
    NSDictionary *data = [body[@"data"] isKindOfClass:NSDictionary.class] ? body[@"data"] : nil;
    if (!error || !data) { return error; }
    NSString *ticket = [data[@"ticket"] isKindOfClass:NSString.class] ? data[@"ticket"] : nil;
    NSNumber *left = [data[@"attempts_left"] isKindOfClass:NSNumber.class] ? data[@"attempts_left"] : nil;
    if (ticket.length == 0 && !left) { return error; }
    NSMutableDictionary *info = [error.userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
    if (ticket.length > 0) { info[IMErrorTwoStepTicketKey] = ticket; }
    if (left) { info[IMErrorTwoStepAttemptsLeftKey] = left; }
    return [NSError errorWithDomain:error.domain code:error.code userInfo:info];
}

@implementation IMTwoStepSetup
@end

@implementation IMHTTPService (TwoStep)

/// 发请求并整包解信封：code != 0 → 带业务码的错误（附 ticket / attempts_left）；信封缺 code 当失败，不当成功。
- (void)runTwoStepRequest:(nullable NSURLRequest *)req
               completion:(void (^)(id _Nullable data, NSError *_Nullable error))completion {
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
        err = IMErrorByAttachingTwoStepInfo(err, body);
        [self callOnMain:^{ completion(nil, err); }];
    }];
}

- (void)fetchTwoStepStateWithToken:(NSString *)token
                        completion:(void (^)(IMTwoStepState *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/two-step" method:@"GET" token:token body:nil];
    [self runTwoStepRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        IMTwoStepState *state = [IMTwoStepState stateFromJSON:data];
        completion(state, state ? nil : [self errorWithMessage:IMLocalized(@"common.action_failed")]);
    }];
}

- (void)setupTwoStepWithToken:(NSString *)token password:(NSString *)password
                   completion:(void (^)(IMTwoStepSetup *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/two-step/setup" method:@"POST" token:token
                                                     body:@{ @"password": password ?: @"" }];
    [self runTwoStepRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *d = [data isKindOfClass:NSDictionary.class] ? data : nil;
        NSString *secret = [d[@"secret"] isKindOfClass:NSString.class] ? d[@"secret"] : nil;
        NSString *uri = [d[@"otpauth_uri"] isKindOfClass:NSString.class] ? d[@"otpauth_uri"] : nil;
        if (secret.length == 0 || uri.length == 0) {
            completion(nil, [self errorWithMessage:IMLocalized(@"common.action_failed")]);
            return;
        }
        IMTwoStepSetup *setup = [IMTwoStepSetup new];
        setup.secret = secret;
        setup.otpauthURI = uri;
        setup.expiresIn = [d[@"expires_in"] respondsToSelector:@selector(doubleValue)] ? [d[@"expires_in"] doubleValue] : 1800;
        completion(setup, nil);
    }];
}

/// enable / recovery-codes 共用：成功体 {recovery_codes:[…]}，空列表当失败（用户拿不到码就不能算开启成功）。
- (void)recoveryCodesFromRequest:(NSURLRequest *)req completion:(void (^)(NSArray<NSString *> *, NSError *))completion {
    [self runTwoStepRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSArray<NSString *> *codes = IMTwoStepParseRecoveryCodes([data isKindOfClass:NSDictionary.class] ? data[@"recovery_codes"] : nil);
        completion(codes.count > 0 ? codes : nil, codes.count > 0 ? nil : [self errorWithMessage:IMLocalized(@"common.action_failed")]);
    }];
}

- (void)enableTwoStepWithToken:(NSString *)token code:(NSString *)code
                    completion:(void (^)(NSArray<NSString *> *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/two-step/enable" method:@"POST" token:token
                                                     body:@{ @"code": code ?: @"" }];
    [self recoveryCodesFromRequest:req completion:completion];
}

- (void)disableTwoStepWithToken:(NSString *)token password:(NSString *)password code:(NSString *)code
                     completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/two-step/disable" method:@"POST" token:token
                                                     body:@{ @"password": password ?: @"", @"code": code ?: @"" }];
    [self runTwoStepRequest:req completion:^(id data, NSError *error) { completion(error); }];
}

- (void)regenerateRecoveryCodesWithToken:(NSString *)token password:(NSString *)password code:(NSString *)code
                              completion:(void (^)(NSArray<NSString *> *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/two-step/recovery-codes" method:@"POST" token:token
                                                     body:@{ @"password": password ?: @"", @"code": code ?: @"" }];
    [self recoveryCodesFromRequest:req completion:completion];
}

- (void)loginTwoStepWithTicket:(NSString *)ticket code:(NSString *)code
                    completion:(void (^)(NSString *, NSString *, NSError *))completion {
    NSMutableURLRequest *req = [self postRequestToPath:@"/api/v1/login/two-step"
                                                  body:@{ @"ticket": ticket ?: @"", @"code": code ?: @"" }];
    [self runTwoStepRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        NSDictionary *d = [data isKindOfClass:NSDictionary.class] ? data : nil;
        NSString *token = [d[@"token"] isKindOfClass:NSString.class] ? d[@"token"] : nil;
        if (token.length == 0) {
            completion(nil, nil, [self errorWithMessage:IMLocalized(@"login.error.login_failed")]);
            return;
        }
        [self adoptLoginSuccessData:d token:token fallbackUserID:@""];
        completion(token, self.lastLoginUserID, nil);
    }];
}

@end
