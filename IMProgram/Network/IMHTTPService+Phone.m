//  IMHTTPService+Phone.m

#import "IMHTTPService+Phone.h"
#import "IMHTTPService+Private.h"
#import "IMHTTPService+Account.h"
#import "IMHTTPService+TwoStep.h"
#import "IMEmailLogin.h"
#import "IMLocalization.h"
#import "IMSessionStore.h"
#import "IMUserCard.h"
#import "IMLog.h"

NSString * const IMErrorSMSAttemptsLeftKey = @"im_sms_attempts_left";
NSString * const IMErrorSMSRetryAfterKey = @"im_sms_retry_after";
NSString * const IMErrorSMSFieldKey = @"im_sms_field";
NSString * const IMErrorRestoreTicketKey = @"im_restore_ticket";

NSError *IMErrorByAttachingPhoneInfo(NSError *error, NSDictionary *body) {
    NSDictionary *data = [body[@"data"] isKindOfClass:NSDictionary.class] ? body[@"data"] : nil;
    if (!error || !data) { return error; }
    NSMutableDictionary *info = [error.userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
    if ([data[@"attempts_left"] isKindOfClass:NSNumber.class]) { info[IMErrorSMSAttemptsLeftKey] = data[@"attempts_left"]; }
    if ([data[@"retry_after_sec"] isKindOfClass:NSNumber.class]) { info[IMErrorSMSRetryAfterKey] = data[@"retry_after_sec"]; }
    if ([data[@"field"] isKindOfClass:NSString.class]) { info[IMErrorSMSFieldKey] = data[@"field"]; }
    if ([data[@"restore_ticket"] isKindOfClass:NSString.class] && [data[@"restore_ticket"] length] > 0) {
        info[IMErrorRestoreTicketKey] = data[@"restore_ticket"];
    }
    return [NSError errorWithDomain:error.domain code:error.code userInfo:info];
}

static NSInteger IMPhoneIntFromError(NSError *error, NSString *key) {
    id v = error.userInfo[key];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : -1;
}
NSInteger IMSMSAttemptsLeftFromError(NSError *error) { return IMPhoneIntFromError(error, IMErrorSMSAttemptsLeftKey); }
NSInteger IMSMSRetryAfterFromError(NSError *error) {
    id v = error.userInfo[IMErrorSMSRetryAfterKey];
    return [v respondsToSelector:@selector(doubleValue)] ? (NSInteger)ceil([v doubleValue]) : -1;
}
NSString *IMSMSFieldFromError(NSError *error) {
    id v = error.userInfo[IMErrorSMSFieldKey];
    return [v isKindOfClass:NSString.class] ? v : nil;
}

@implementation IMSMSSendResult
@end

@implementation IMSMSLoginResult
@end

@implementation IMHTTPService (Phone)

static IMSMSSendResult *IMSMSSendResultFrom(id data) {
    NSDictionary *d = [data isKindOfClass:NSDictionary.class] ? data : nil;
    IMSMSSendResult *r = [IMSMSSendResult new];
    r.resendAfter = [d[@"resend_after"] respondsToSelector:@selector(integerValue)] ? [d[@"resend_after"] integerValue] : -1;
    r.expiresIn = [d[@"expires_in"] respondsToSelector:@selector(integerValue)] ? [d[@"expires_in"] integerValue] : 300;
    r.phoneMasked = [d[@"phone_masked"] isKindOfClass:NSString.class] ? d[@"phone_masked"] : nil;
    return r;
}

- (void)sendSMSCodeForScene:(NSString *)scene countryCode:(NSString *)countryCode phone:(NSString *)phone
                      token:(NSString *)token completion:(void (^)(IMSMSSendResult *, NSError *))completion {
    NSDictionary *body = @{ @"scene": scene ?: @"", @"country_code": countryCode ?: @"",
                            @"phone": IMPhoneNationalNumber(countryCode, phone), @"lang": IMEmailAPILang() };
    NSMutableURLRequest *req = token.length > 0
        ? [self authedRequestForPath:@"/api/v1/sms/send-code" method:@"POST" token:token body:body]
        : [self postRequestToPath:@"/api/v1/sms/send-code" body:body];
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) {
        IMLogHTTP(@"sms_send scene=%@ phone=%@ err=%ld", scene, IMPhoneMasked(countryCode, phone), (long)error.code);
        completion(error ? nil : IMSMSSendResultFrom(data), error);
    }];
}

/// 登录成功体（/login/sms、/register/phone）→ 走与密码登录同一条收尾；need_register 时只带票。
- (void)handleSMSLoginData:(id)data error:(NSError *)error completion:(void (^)(IMSMSLoginResult *, NSError *))completion {
    if (error) { completion(nil, error); return; }
    NSDictionary *d = [data isKindOfClass:NSDictionary.class] ? data : nil;
    IMSMSLoginResult *r = [IMSMSLoginResult new];
    if ([d[@"need_register"] isKindOfClass:NSNumber.class] && [d[@"need_register"] boolValue]) {
        NSString *ticket = [d[@"register_ticket"] isKindOfClass:NSString.class] ? d[@"register_ticket"] : nil;
        if (ticket.length == 0) { completion(nil, [self errorWithMessage:IMLocalized(@"login.error.login_failed")]); return; }
        r.needRegister = YES;
        r.registerTicket = ticket;
        completion(r, nil);
        return;
    }
    NSString *token = [d[@"token"] isKindOfClass:NSString.class] ? d[@"token"] : nil;
    if (token.length == 0) { completion(nil, [self errorWithMessage:IMLocalized(@"login.error.login_failed")]); return; }
    [self adoptLoginSuccessData:d token:token fallbackUserID:@""];
    r.token = token;
    r.userID = self.lastLoginUserID;
    r.username = [d[@"username"] isKindOfClass:NSString.class] && [d[@"username"] length] > 0 ? d[@"username"] : nil;
    completion(r, nil);
}

- (void)loginWithSMSCountryCode:(NSString *)countryCode phone:(NSString *)phone code:(NSString *)code
                     completion:(void (^)(IMSMSLoginResult *, NSError *))completion {
    NSMutableDictionary *body = [[self deviceFields] mutableCopy];
    body[@"country_code"] = countryCode ?: @"";
    body[@"phone"] = IMPhoneNationalNumber(countryCode, phone);
    body[@"code"] = code ?: @"";
    __weak typeof(self) ws = self;
    [self runEnvelopeRequest:[self postRequestToPath:@"/api/v1/login/sms" body:body] completion:^(id data, NSError *error) {
        [ws handleSMSLoginData:data error:error completion:completion];
    }];
}

- (void)registerPhoneWithTicket:(NSString *)ticket nickname:(NSString *)nickname
                     completion:(void (^)(IMSMSLoginResult *, NSError *))completion {
    NSMutableDictionary *body = [[self deviceFields] mutableCopy];
    body[@"register_ticket"] = ticket ?: @"";
    body[@"nickname"] = nickname ?: @"";
    __weak typeof(self) ws = self;
    [self runEnvelopeRequest:[self postRequestToPath:@"/api/v1/register/phone" body:body] completion:^(id data, NSError *error) {
        [ws handleSMSLoginData:data error:error completion:completion];
    }];
}

- (void)resetPasswordWithCountryCode:(NSString *)countryCode phone:(NSString *)phone code:(NSString *)code
                         newPassword:(NSString *)newPassword completion:(void (^)(NSError *))completion {
    NSDictionary *body = @{ @"country_code": countryCode ?: @"", @"phone": IMPhoneNationalNumber(countryCode, phone),
                            @"code": code ?: @"", @"new_password": newPassword ?: @"" };
    [self runEnvelopeRequest:[self postRequestToPath:@"/api/v1/password/reset" body:body] completion:^(id data, NSError *error) {
        completion(error);
    }];
}

- (void)restoreAccountWithTicket:(NSString *)ticket completion:(void (^)(NSError *))completion {
    [self runEnvelopeRequest:[self postRequestToPath:@"/api/v1/account/restore" body:@{ @"restore_ticket": ticket ?: @"" }]
               completion:^(id data, NSError *error) { completion(error); }];
}

- (void)fetchSecurityStateWithToken:(NSString *)token completion:(void (^)(IMSecurityState *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/security" method:@"GET" token:token body:nil];
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        IMSecurityState *s = [IMSecurityState stateFromJSON:data];
        completion(s, s ? nil : [self errorWithMessage:IMLocalized(@"common.action_failed")]);
    }];
}

- (void)dismissLegacyPhoneWithToken:(NSString *)token completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/legacy-phone" method:@"DELETE" token:token body:nil];
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) { completion(error); }];
}

- (void)sendVerifyCodeWithToken:(NSString *)token completion:(void (^)(IMSMSSendResult *, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/verify-code" method:@"POST" token:token
                                                     body:@{ @"lang": IMEmailAPILang() }];
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) {
        completion(error ? nil : IMSMSSendResultFrom(data), error);
    }];
}

- (void)updatePasswordWithToken:(NSString *)token proof:(IMIdentityProof *)proof newPassword:(NSString *)newPassword
                     completion:(void (^)(NSError *))completion {
    NSDictionary *body = @{ @"proof": [proof JSONObject], @"new_password": newPassword ?: @"" };
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/password" method:@"POST" token:token body:body];
    __weak typeof(self) ws = self;
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) {
        // 修改已有密码时服务端轮换本机续期凭据（PROTOCOL §11 token/refresh）：必须就地换掉，否则下次冷启动续期被拒。
        NSString *fresh = [data isKindOfClass:NSDictionary.class] && [data[@"refresh_token"] isKindOfClass:NSString.class]
            ? data[@"refresh_token"] : nil;
        if (!error && fresh.length > 0) {
            ws.refreshToken = fresh;
            [IMSessionStore saveRefreshToken:fresh];
        }
        completion(error);
    }];
}

- (void)bindPhoneWithToken:(NSString *)token proof:(IMIdentityProof *)proof countryCode:(NSString *)countryCode
                     phone:(NSString *)phone code:(NSString *)code completion:(void (^)(NSString *, NSError *))completion {
    NSDictionary *body = IMBodyWithProof(@{ @"country_code": countryCode ?: @"",
                                            @"phone": IMPhoneNationalNumber(countryCode, phone), @"code": code ?: @"" }, proof);
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/phone" method:@"POST" token:token body:body];
    [self runEnvelopeRequest:req completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSString *masked = [data isKindOfClass:NSDictionary.class] && [data[@"phone_masked"] isKindOfClass:NSString.class]
            ? data[@"phone_masked"] : IMPhoneMasked(countryCode, phone);
        [NSNotificationCenter.defaultCenter postNotificationName:IMMyProfileDidChangeNotification object:nil];
        completion(masked, nil);
    }];
}

- (void)repairStoredUsernameIfNeeded {
    NSString *uid = IMSessionStore.userID;
    if (uid.length == 0 || IMSessionStore.usernameFromServer || IMStoredUsernameIsTrusted(IMSessionStore.username)) { return; }
    // **不先清空**：老版本升级上来、没有 refresh token 只靠 legacyPassword 的安装，重登只能拿这个旧值当登录名
    // （服务端认手机号 / 邮箱登录）；清空后回退到内部 ID 必败，而且以后每次冷启动都这样。旧值在内存与磁盘里都原样保留，
    // 只在 /users/me 拿到服务端 username 后覆盖保存（saveHost 同时置 usernameFromServer，下次不再进来）。
    NSString *host = IMSessionStore.host ?: @"";
    IMLogWarnWithTag(IMLogTagApp, @"stored_username_untrusted → 拉 /users/me 校正");
    __weak typeof(self) ws = self;
    [self loginWithUserID:uid completion:^(NSString *token, NSError *error) {
        if (token.length == 0) { return; }
        [ws myProfileWithToken:token completion:^(IMUserCard *card, NSError *err) {
            __strong typeof(ws) self = ws;
            if (!self || card.username.length == 0 || ![IMSessionStore.userID isEqualToString:uid]) { return; }
            self.username = card.username;
            [IMSessionStore saveHost:IMSessionStore.host ?: host userID:uid username:card.username];
        }];
    }];
}

@end
