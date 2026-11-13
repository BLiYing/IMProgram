//  IMEmailLoginTests.m
//  邮箱登录（EMAIL_LOGIN_DESIGN / PROTOCOL §7.2）：纯规则（预检 / 脱敏 / 错误码映射 / 倒计时 / 状态解析）、REST 编码、
//  日志脱敏、系统通知渲染、设置搜索登记、各页行为。app-hosted；HTTP 用 NSURLProtocol 桩。

#import <XCTest/XCTest.h>

#import "IMEmailLogin.h"
#import "IMTwoStep.h"
#import "IMLocalization.h"
#import "IMSysEventFormatter.h"
#import "IMHTTPLogFormatter.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Email.h"
#import "IMHTTPService+Account.h"
#import "IMEmailLoginViewController.h"
#import "IMEmailFormViewController.h"
#import "IMEmailCodeViewController.h"
#import "IMEmailUnbindViewController.h"
#import "IMLoginViewController.h"
#import "IMPrivacySecurityViewController.h"
#import "IMSettingsSearchRegistry.h"
#import "IMSettingsRouter.h"

#pragma mark - HTTP 桩

@interface IMEmailStub : NSURLProtocol
@property (class, nonatomic, copy) NSDictionary *response;
@property (class, nonatomic, copy) NSString *lastPath;
@property (class, nonatomic, copy) NSString *lastMethod;
@property (class, nonatomic, copy) NSDictionary *lastBody;
@end
@implementation IMEmailStub
static NSDictionary *eResp; static NSString *ePath; static NSString *eMethod; static NSDictionary *eBody;
+ (NSDictionary *)response { return eResp; }
+ (void)setResponse:(NSDictionary *)v { eResp = v; }
+ (NSString *)lastPath { return ePath; }
+ (void)setLastPath:(NSString *)v { ePath = v; }
+ (NSString *)lastMethod { return eMethod; }
+ (void)setLastMethod:(NSString *)v { eMethod = v; }
+ (NSDictionary *)lastBody { return eBody; }
+ (void)setLastBody:(NSDictionary *)v { eBody = v; }
+ (BOOL)canInitWithRequest:(NSURLRequest *)r {
    NSString *p = r.URL.path;
    return [p hasPrefix:@"/api/v1/users/me/email"] || [p isEqualToString:@"/api/v1/account/restore"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    ePath = self.request.URL.path;
    eMethod = self.request.HTTPMethod;
    NSData *body = self.request.HTTPBody;
    if (!body && self.request.HTTPBodyStream) {
        NSInputStream *in = self.request.HTTPBodyStream;
        NSMutableData *buf = [NSMutableData data];
        uint8_t tmp[1024];
        [in open];
        NSInteger n;
        while ((n = [in read:tmp maxLength:sizeof tmp]) > 0) { [buf appendBytes:tmp length:(NSUInteger)n]; }
        [in close];
        body = buf;
    }
    id obj = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
    eBody = [obj isKindOfClass:NSDictionary.class] ? obj : nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:eResp ?: @{ @"code": @0, @"data": @{} } options:0 error:NULL];
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                     headerFields:@{ @"Content-Type": @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface IMLoginViewController (EmailTestAccess)
- (void)registerTabTapped;
- (void)backToLoginTapped;
@end
@interface IMEmailFormViewController (EmailTestAccess)
- (BOOL)textFieldShouldReturn:(UITextField *)textField;
@end

@interface IMEmailCodeViewController (EmailTestAccess)
- (void)handleVerify:(IMEmailState *)bound error:(NSError *)error;
@end
@interface IMEmailFormViewController (EmailTestSend)
- (void)handleSend:(IMEmailSendResult *)result error:(NSError *)error email:(NSString *)email proof:(IMIdentityProof *)proof;
@end

@interface IMEmailLoginTests : XCTestCase
@end

@implementation IMEmailLoginTests {
    NSString *_savedHost;
}

- (void)setUp {
    [super setUp];
    [IMLocalization.shared setPreference:IMLanguagePrefZhHans];
    _savedHost = IMHTTPService.sharedService.host;
    IMHTTPService.sharedService.host = @"127.0.0.1:59393";
    eResp = nil; ePath = nil; eMethod = nil; eBody = nil;
    [NSURLProtocol registerClass:IMEmailStub.class];
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:IMEmailStub.class];
    [IMHTTPService.sharedService invalidateToken];
    IMHTTPService.sharedService.host = _savedHost;
    [IMLocalization.shared setPreference:IMLanguagePrefZhHans];
    [super tearDown];
}

#pragma mark - 邮箱预检 / 脱敏

- (void)test_预检_合规 {
    XCTAssertTrue(IMEmailPrecheck(@"a@b.com"));
    XCTAssertTrue(IMEmailPrecheck(@"  Alice+tag@Example.co.uk \n"), @"首尾空白先去掉");
    XCTAssertTrue(IMEmailPrecheck(@"a.b@c.d"));
}
- (void)test_预检_不合规 {
    for (NSString *bad in @[@"", @"   ", @"ab.com", @"a@b", @"a@@b.com", @"a@b@c.com", @"@b.com", @"a@.com", @"a@b.", @"a b@c.com",
                            @"a@b .com", @"a\t@b.com", @"a@b.com\nx@y.com"]) {
        XCTAssertFalse(IMEmailPrecheck(bad), @"应拒绝：%@", bad);
    }
    XCTAssertFalse(IMEmailPrecheck(nil));
}
- (void)test_预检_长度上限254 {
    NSString *domain = @"@example.com";
    NSString *ok = [[@"" stringByPaddingToLength:254 - domain.length withString:@"a" startingAtIndex:0] stringByAppendingString:domain];
    XCTAssertEqual(ok.length, 254u);
    XCTAssertTrue(IMEmailPrecheck(ok));
    XCTAssertFalse(IMEmailPrecheck([@"a" stringByAppendingString:ok]), @"255 位拒绝");
}
- (void)test_脱敏 {
    XCTAssertEqualObjects(IMEmailMasked(@"alice@gmail.com"), @"a***@gmail.com");
    XCTAssertEqualObjects(IMEmailMasked(@"a@gmail.com"), @"*@gmail.com", @"local 只有 1 位整个 *");
    XCTAssertEqualObjects(IMEmailMasked(@"nonsense"), @"***");
    XCTAssertEqualObjects(IMEmailMasked(nil), @"***");
    XCTAssertFalse([IMEmailMasked(@"alice@gmail.com") containsString:@"lice"]);
}
- (void)test_请求lang跟随App语言 {
    XCTAssertEqualObjects(IMEmailAPILang(), @"zh-Hans");
    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    XCTAssertEqualObjects(IMEmailAPILang(), @"en");
}

#pragma mark - 错误码 → 文案

- (void)test_错误码映射_文案键 {
    XCTAssertEqualObjects(IMEmailErrorMessage(200002, -1, -1, @"fb"), IMLocalized(@"email.err.password"));
    XCTAssertEqualObjects(IMEmailErrorMessage(200030, -1, -1, @"fb"), IMLocalized(@"email.err.invalid"));
    XCTAssertEqualObjects(IMEmailErrorMessage(200031, -1, -1, @"fb"), IMLocalized(@"email.err.taken"));
    XCTAssertEqualObjects(IMEmailErrorMessage(200033, -1, -1, @"fb"), IMLocalized(@"email.code.expired"));
    XCTAssertEqualObjects(IMEmailErrorMessage(200034, -1, -1, @"fb"), IMLocalized(@"email.err.not_bound"));
    XCTAssertEqualObjects(IMEmailErrorMessage(200035, -1, -1, @"fb"), IMLocalized(@"email.err.same"));
    XCTAssertEqualObjects(IMEmailErrorMessage(200036, -1, -1, @"fb"), IMLocalized(@"email.err.unavailable"));
    XCTAssertEqualObjects(IMEmailErrorMessage(200037, -1, -1, @"fb"), IMLocalized(@"email.err.send_failed"));
    XCTAssertEqualObjects(IMEmailErrorMessage(999999, -1, -1, @"fb"), @"fb", @"未知码回退");
    XCTAssertEqualObjects(IMEmailErrorMessage(200033, -1, -1, @"fb"), @"验证码已失效，请重新发送");
}
- (void)test_错误码_验证码错_剩余次数只在1到2显示 {
    XCTAssertEqualObjects(IMEmailErrorMessage(200032, -1, -1, nil), @"验证码不正确");
    XCTAssertEqualObjects(IMEmailErrorMessage(200032, 4, -1, nil), @"验证码不正确");
    XCTAssertEqualObjects(IMEmailErrorMessage(200032, 3, -1, nil), @"验证码不正确");
    XCTAssertEqualObjects(IMEmailErrorMessage(200032, 2, -1, nil), @"验证码不正确，还可尝试 2 次");
    XCTAssertEqualObjects(IMEmailErrorMessage(200032, 1, -1, nil), @"验证码不正确，还可尝试 1 次");
    XCTAssertEqualObjects(IMEmailErrorMessage(200032, 0, -1, nil), @"验证码不正确", @"0 次时行已被删，200033 才会出现；不显示「还可尝试 0 次」");
}
- (void)test_错误码_限流_有秒数才带秒数 {
    XCTAssertEqualObjects(IMEmailErrorMessage(100002, -1, 42, nil), @"发送过于频繁，请 42 秒后再试");
    XCTAssertEqualObjects(IMEmailErrorMessage(100002, -1, -1, nil), @"发送过于频繁，请稍后再试");
    XCTAssertEqualObjects(IMEmailErrorMessage(100002, -1, 0, nil), @"发送过于频繁，请稍后再试");
    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    XCTAssertTrue([IMEmailErrorMessage(100002, -1, 42, nil) containsString:@"42"]);
}
- (void)test_错误高亮落点与验证码页动作 {
    XCTAssertEqual(IMEmailFormTargetForError(200002), IMEmailFormTargetNone, @"密码改由确认身份弹层收，表单不再描红密码");
    XCTAssertEqual(IMEmailFormTargetForError(200030), IMEmailFormTargetEmail);
    XCTAssertEqual(IMEmailFormTargetForError(200031), IMEmailFormTargetEmail);
    XCTAssertEqual(IMEmailFormTargetForError(200035), IMEmailFormTargetEmail);
    XCTAssertEqual(IMEmailFormTargetForError(200037), IMEmailFormTargetNone);
    XCTAssertEqual(IMEmailCodeActionForError(200032), IMEmailCodeActionClearAndRefocus);
    XCTAssertEqual(IMEmailCodeActionForError(200033), IMEmailCodeActionExpired);
    XCTAssertEqual(IMEmailCodeActionForError(200031), IMEmailCodeActionShowError);
    XCTAssertEqual(IMEmailCodeActionForError(100002), IMEmailCodeActionShowError);
}

#pragma mark - 倒计时

- (void)test_倒计时_剩余向上取整_到点为0 {
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1000];
    XCTAssertEqual(IMEmailResendRemaining([now dateByAddingTimeInterval:59.2], now), 60);
    XCTAssertEqual(IMEmailResendRemaining([now dateByAddingTimeInterval:1], now), 1);
    XCTAssertEqual(IMEmailResendRemaining(now, now), 0);
    XCTAssertEqual(IMEmailResendRemaining([now dateByAddingTimeInterval:-5], now), 0);
    XCTAssertEqual(IMEmailResendRemaining(nil, now), 0);
}
- (void)test_倒计时_截止时刻_默认60_服务端秒数优先_0即刻可发 {
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1000];
    XCTAssertEqual(IMEmailResendRemaining(IMEmailResendDeadline(-1, now), now), 60);
    XCTAssertEqual(IMEmailResendRemaining(IMEmailResendDeadline(42, now), now), 42);
    XCTAssertEqual(IMEmailResendRemaining(IMEmailResendDeadline(0, now), now), 0);
}
- (void)test_倒计时_文案 {
    XCTAssertEqualObjects(IMEmailResendTitle(59), @"重新发送（59s）");
    XCTAssertEqualObjects(IMEmailResendTitle(0), @"重新发送");
}
- (void)test_自动提交_复用两步验证清洗与满位判定 {
    XCTAssertTrue(IMEmailShouldAutoSubmit(@"123456", NO));
    XCTAssertFalse(IMEmailShouldAutoSubmit(@"123456", YES), @"在途不重复提交");
    XCTAssertFalse(IMEmailShouldAutoSubmit(@"12345", NO));
}

#pragma mark - 状态解析

- (void)test_状态解析_已绑定_未绑定_不可用 {
    IMEmailState *bound = [IMEmailState stateFromJSON:@{ @"available": @YES, @"bound": @YES, @"email": @"a@b.com", @"verified_at": @1793318400000 }];
    XCTAssertTrue(bound.available); XCTAssertTrue(bound.bound);
    XCTAssertEqualObjects(bound.email, @"a@b.com");
    XCTAssertEqualWithAccuracy(bound.verifiedAt.timeIntervalSince1970, 1793318400, 1);
    XCTAssertTrue([[bound boundSinceText] hasPrefix:@"绑定于 2026"], @"%@", [bound boundSinceText]);
    IMEmailState *secs = [IMEmailState stateFromJSON:@{ @"bound": @YES, @"email": @"a@b.com", @"verified_at": @1793318400 }];
    XCTAssertEqualWithAccuracy(secs.verifiedAt.timeIntervalSince1970, 1793318400, 1, @"秒级时间戳也认");
    IMEmailState *unbound = [IMEmailState stateFromJSON:@{ @"available": @NO, @"bound": @NO }];
    XCTAssertFalse(unbound.available); XCTAssertFalse(unbound.bound); XCTAssertNil(unbound.email);
    XCTAssertFalse([IMEmailState stateFromJSON:@{ @"bound": @YES }].bound, @"bound 缺 email 当未绑定");
    XCTAssertNil([IMEmailState stateFromJSON:@"x"]);
    XCTAssertNil([IMEmailState boundStateFromVerifyJSON:@{}]);
}
- (void)test_隐私页右值 {
    XCTAssertNil(IMEmailRowValueText(nil), @"未加载留空");
    XCTAssertEqualObjects(IMEmailRowValueText([IMEmailState stateFromJSON:@{ @"bound": @NO }]), @"未绑定");
    XCTAssertEqualObjects(IMEmailRowValueText([IMEmailState stateFromJSON:@{ @"bound": @YES, @"email": @"a@b.com" }]), @"a@b.com");
}

#pragma mark - REST 编码

- (void)test_REST_四个接口的路径_方法_请求体 {
    NSString *t = @"tok";
    XCTestExpectation *e = [self expectationWithDescription:@"all"];
    eResp = @{ @"code": @0, @"data": @{ @"available": @YES, @"bound": @YES, @"email": @"a@b.com", @"verified_at": @1793318400000 } };
    [IMHTTPService.sharedService fetchEmailStateWithToken:t completion:^(IMEmailState *state, NSError *error) {
        XCTAssertEqualObjects(ePath, @"/api/v1/users/me/email");
        XCTAssertEqualObjects(eMethod, @"GET");
        XCTAssertTrue(state.bound);
        eResp = @{ @"code": @0, @"data": @{ @"expires_in": @600, @"resend_after": @45 } };
        [IMHTTPService.sharedService sendEmailCodeWithToken:t email:@"x@y.com" proof:[IMIdentityProof passwordProof:@"pw"] completion:^(IMEmailSendResult *r, NSError *e2) {
            XCTAssertEqualObjects(ePath, @"/api/v1/users/me/email/send-code");
            XCTAssertEqualObjects(eMethod, @"POST");
            XCTAssertEqualObjects(eBody, (@{ @"email": @"x@y.com", @"proof": @{ @"password": @"pw" }, @"lang": @"zh-Hans" }));
            XCTAssertEqual(r.resendAfter, 45); XCTAssertEqual(r.expiresIn, 600);
            [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
            eResp = @{ @"code": @0, @"data": @{ @"email": @"x@y.com", @"verified_at": @1793318400000 } };
            [IMHTTPService.sharedService verifyEmailWithToken:t email:@"x@y.com" code:@"012345" completion:^(IMEmailState *b, NSError *e3) {
                XCTAssertEqualObjects(ePath, @"/api/v1/users/me/email/verify");
                XCTAssertEqualObjects(eBody, (@{ @"email": @"x@y.com", @"code": @"012345", @"lang": @"en" }), @"码是字符串、前导 0 保留、lang 跟 App 语言");
                XCTAssertEqualObjects(b.email, @"x@y.com"); XCTAssertTrue(b.bound);
                eResp = @{ @"code": @0, @"data": @{ @"ok": @YES } };
                [IMHTTPService.sharedService unbindEmailWithToken:t proof:[IMIdentityProof smsProof:@"123456"] completion:^(NSError *e4) {
                    XCTAssertEqualObjects(ePath, @"/api/v1/users/me/email/unbind");
                    XCTAssertEqualObjects(eBody, (@{ @"proof": @{ @"sms_code": @"123456" } }));
                    XCTAssertNil(e4);
                    [e fulfill];
                }];
            }];
        }];
    }];
    [self waitForExpectations:@[e] timeout:10];
}

- (void)test_REST_错误保留业务码并带attempts_left与retry_after {
    XCTestExpectation *e = [self expectationWithDescription:@"err"];
    eResp = @{ @"code": @200032, @"message": @"wrong", @"data": @{ @"attempts_left": @2 } };
    [IMHTTPService.sharedService verifyEmailWithToken:@"t" email:@"a@b.com" code:@"111111" completion:^(IMEmailState *b, NSError *err) {
        XCTAssertNil(b);
        XCTAssertEqual(err.code, 200032);
        XCTAssertEqual(IMEmailAttemptsLeftFromError(err), 2);
        XCTAssertEqual(IMEmailRetryAfterFromError(err), -1);
        eResp = @{ @"code": @100002, @"message": @"slow", @"data": @{ @"retry_after_sec": @42 } };
        [IMHTTPService.sharedService sendEmailCodeWithToken:@"t" email:@"a@b.com" proof:[IMIdentityProof passwordProof:@"p"] completion:^(IMEmailSendResult *r, NSError *err2) {
            XCTAssertEqual(err2.code, 100002);
            XCTAssertEqual(IMEmailRetryAfterFromError(err2), 42);
            eResp = @{ @"code": @200033, @"message": @"exp", @"data": @{ @"retry_after_sec": @0 } };
            [IMHTTPService.sharedService verifyEmailWithToken:@"t" email:@"a@b.com" code:@"111111" completion:^(IMEmailState *b3, NSError *err3) {
                XCTAssertEqual(IMEmailRetryAfterFromError(err3), 0, @"0 = 现在就能重发，要和「没给」(-1) 区分");
                [e fulfill];
            }];
        }];
    }];
    [self waitForExpectations:@[e] timeout:10];
}

- (void)test_REST_信封缺code当失败_不当成功 {
    XCTestExpectation *e = [self expectationWithDescription:@"nocode"];
    eResp = @{ @"data": @{} };
    [IMHTTPService.sharedService unbindEmailWithToken:@"t" proof:[IMIdentityProof passwordProof:@"p"] completion:^(NSError *err) {
        XCTAssertNotNil(err);
        [e fulfill];
    }];
    [self waitForExpectations:@[e] timeout:10];
}

- (void)test_restore_冷静期恢复账号_邮箱登录名原样透传 {
    XCTestExpectation *e = [self expectationWithDescription:@"restore"];
    eResp = @{ @"code": @0, @"data": @{} };
    [IMHTTPService.sharedService restoreAccountWithUsername:@"Alice@Example.com" password:@"pw" completion:^(NSError *err) {
        XCTAssertEqualObjects(ePath, @"/api/v1/account/restore");
        XCTAssertEqualObjects(eBody, (@{ @"username": @"Alice@Example.com", @"password": @"pw" }), @"不改大小写、不做校验");
        [e fulfill];
    }];
    [self waitForExpectations:@[e] timeout:10];
}

#pragma mark - 日志脱敏

- (void)test_日志_邮箱与验证码与密码脱敏 {
    NSDictionary *req = @{ @"email": @"alice@gmail.com", @"password": @"pw123", @"code": @"482911", @"lang": @"en" };
    NSDictionary *resp = @{ @"code": @0, @"data": @{ @"email": @"alice@gmail.com", @"verified_at": @1793318400000 } };
    for (NSNumber *business in @[@YES, @NO]) {
        NSDictionary *a = IMHTTPSanitizedJSONObject(req, business.boolValue);
        XCTAssertEqualObjects(a[@"email"], @"a***@gmail.com");
        XCTAssertEqualObjects(a[@"password"], @"***");
        XCTAssertEqualObjects(a[@"code"], @"***");
        XCTAssertEqualObjects(a[@"lang"], @"en");
        XCTAssertEqualObjects(IMHTTPSanitizedJSONObject(resp, business.boolValue)[@"data"][@"email"], @"a***@gmail.com");
        XCTAssertEqualObjects(IMHTTPSanitizedJSONObject(resp, business.boolValue)[@"code"], @0);
    }
    NSDictionary *login = IMHTTPSanitizedJSONObject(@{ @"username": @"alice@gmail.com", @"password": @"x" }, YES);
    XCTAssertEqualObjects(login[@"username"], @"a***@gmail.com", @"登录名填邮箱时同样脱敏");
    XCTAssertEqualObjects(IMHTTPSanitizedJSONObject(@{ @"username": @"alice_01" }, YES)[@"username"], @"alice_01", @"普通用户名原样");
    NSData *raw = [NSJSONSerialization dataWithJSONObject:req options:0 error:NULL];
    NSString *line = IMHTTPLogBody(raw, @"application/json", YES);
    for (NSString *secret in @[@"alice@gmail.com", @"pw123", @"482911"]) {
        XCTAssertFalse([line containsString:secret], @"日志泄露 %@", secret);
    }
}

#pragma mark - 系统通知渲染

- (void)test_通知_绑定_更换_解绑_中英 {
    NSDictionary *args = @{ @"email_masked": @"a***@gmail.com", @"at": @"2026-10-30T10:00:00Z", @"device": @"iPhone 17" };
    for (NSString *ev in @[@"email_bound", @"email_changed"]) {
        NSString *zh = IMTextForNoticeSysEvent(ev, args);
        XCTAssertNotNil(zh, @"%@", ev);
        NSArray *lines = [zh componentsSeparatedByString:@"\n"];
        XCTAssertEqual(lines.count, 3u);
        XCTAssertTrue([lines[0] containsString:@"a***@gmail.com"], @"%@", lines[0]);
        XCTAssertFalse([lines[0] containsString:@"%"], @"占位符必须被替换：%@", lines[0]);
        XCTAssertTrue([lines[1] containsString:@"iPhone 17"]);
        XCTAssertEqualObjects(lines[2], IMLocalized(([NSString stringWithFormat:@"sys.notice.%@.footer", ev])));
    }
    XCTAssertTrue([IMTextForNoticeSysEvent(@"email_bound", args) containsString:@"绑定登录邮箱"]);
    XCTAssertTrue([IMTextForNoticeSysEvent(@"email_changed", args) containsString:@"更换"]);
    NSString *un = IMTextForNoticeSysEvent(@"email_unbound", @{ @"at": @"2026-10-30T10:00:00Z", @"device": @"iPhone 17" });
    XCTAssertEqual([un componentsSeparatedByString:@"\n"].count, 3u);
    XCTAssertTrue([un containsString:@"解除"], @"%@", un);
    XCTAssertEqual([IMTextForNoticeSysEvent(@"email_unbound", @{ @"at": @"2026-10-30T10:00:00Z" }) componentsSeparatedByString:@"\n"].count, 2u,
                   @"无 device 不出设备行");
    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    NSString *en = IMTextForNoticeSysEvent(@"email_bound", args);
    XCTAssertTrue([en containsString:@"a***@gmail.com"], @"%@", en);
    XCTAssertNil(IMTextForNoticeSysEvent(@"email_unknown", args), @"未识别事件回退 content");
}

#pragma mark - 设置搜索 / 路由 / 登录页

- (void)test_设置搜索登记邮箱登录 {
    IMSettingsSearchEntry *hit = nil;
    for (IMSettingsSearchEntry *e in [IMSettingsSearchRegistry allEntries]) { if ([e.entryID isEqualToString:@"privacy.emailLogin"]) { hit = e; } }
    XCTAssertNotNil(hit);
    XCTAssertEqualObjects(hit.path, (@[IMLocalized(@"settings.row.privacy"), IMLocalized(@"ps.row.email_login")]));
    XCTAssertEqualObjects(hit.route, (@[@"privacy", @"privacy/emailLogin"]));
    NSArray *found = [IMSettingsSearchRegistry filterEntries:[IMSettingsSearchRegistry allEntries] keyword:@"邮箱"];
    XCTAssertTrue([[found valueForKey:@"entryID"] containsObject:@"privacy.emailLogin"]);
    NSArray *vcs = [IMSettingsRouter viewControllersForRoute:@[@"privacy", @"privacy/emailLogin"] host:@"h" userID:@"u1"];
    XCTAssertEqual(vcs.count, 2u);
    XCTAssertTrue([vcs.lastObject isKindOfClass:IMEmailLoginViewController.class]);
}

- (void)test_隐私页邮箱登录行已转活 {
    IMPrivacySecurityViewController *vc = [[IMPrivacySecurityViewController alloc] initWithHost:@"h" userID:@"u1"];
    [vc loadViewIfNeeded];
    id row = nil;
    for (id group in [vc valueForKey:@"groups"]) {
        for (id r in [group valueForKey:@"rows"]) { if ([[r valueForKey:@"title"] isEqualToString:IMLocalized(@"ps.row.email_login")]) { row = r; } }
    }
    XCTAssertNotNil(row);
    XCTAssertFalse([[row valueForKey:@"isPlaceholder"] boolValue], @"去掉灰置占位 / comingSoon");
    XCTAssertEqualObjects([row valueForKey:@"systemImage"], @"envelope.fill");
    XCTAssertEqualObjects([row valueForKey:@"rowId"], @"emailLogin");
}

- (void)test_登录页_登录态占位符是用户名或邮箱_注册态不变_键盘ASCII {
    IMLoginViewController *vc = [IMLoginViewController new];
    [vc loadViewIfNeeded];
    UITextField *user = [vc valueForKey:@"userIDField"];
    XCTAssertEqualObjects(user.placeholder, IMLocalized(@"login.ident.placeholder"), @"密码登录：用户名 / 邮箱 / 手机号");
    XCTAssertEqual(user.keyboardType, UIKeyboardTypeASCIICapable);
    [vc registerTabTapped];
    XCTAssertEqualObjects(user.placeholder, IMLocalized(@"login.username.placeholder"), @"注册页不接受邮箱，仍是用户名规则");
    XCTAssertEqual(user.keyboardType, UIKeyboardTypeASCIICapable);
    [vc backToLoginTapped];
    XCTAssertEqualObjects(user.placeholder, IMLocalized(@"login.ident.placeholder"));
}

#pragma mark - 页面

- (void)test_填邮箱页_输入框属性_预检失败不发请求且不清空 {
    IMEmailFormViewController *vc = [[IMEmailFormViewController alloc] initWithHost:@"127.0.0.1:59393" userID:@"u1" change:NO currentEmail:nil];
    [vc loadViewIfNeeded];
    UITextField *em = vc.emailField;
    XCTAssertEqual(em.keyboardType, UIKeyboardTypeEmailAddress);
    XCTAssertEqual(em.autocapitalizationType, UITextAutocapitalizationTypeNone);
    XCTAssertEqual(em.autocorrectionType, UITextAutocorrectionTypeNo);
    XCTAssertEqual(em.spellCheckingType, UITextSpellCheckingTypeNo);
    XCTAssertEqualObjects(em.textContentType, UITextContentTypeEmailAddress);
    XCTAssertEqualObjects(vc.title, @"绑定邮箱");
    XCTAssertFalse(vc.primaryButton.enabled, @"填了邮箱才可点（身份确认在弹层里）");
    em.text = @"alice@example";
    [em sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertTrue(vc.primaryButton.enabled);
    ePath = nil;
    [vc.primaryButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertEqualObjects(vc.errorLabel.text, @"邮箱格式不正确");
    XCTAssertFalse(vc.errorLabel.superview.hidden);
    XCTAssertNil(ePath, @"预检不过不发请求");
    XCTAssertEqualObjects(em.text, @"alice@example", @"输入不清空");
    XCTAssertFalse(vc.busy);
    vc.emailField.text = @"alice@example.com";
    [em sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertTrue(vc.errorLabel.superview.hidden, @"重新输入后红字消失");
    XCTAssertEqual(vc.errorLabel.text.length, 0u);
}

- (void)test_更换邮箱页_标题与footer不同 {
    IMEmailFormViewController *bind = [[IMEmailFormViewController alloc] initWithHost:@"h" userID:@"u" change:NO currentEmail:nil];
    IMEmailFormViewController *chg = [[IMEmailFormViewController alloc] initWithHost:@"h" userID:@"u" change:YES currentEmail:@"a@b.com"];
    [bind loadViewIfNeeded]; [chg loadViewIfNeeded];
    XCTAssertEqualObjects(bind.title, @"绑定邮箱");
    XCTAssertEqualObjects(chg.title, @"更换邮箱");
    XCTAssertEqualObjects(bind.primaryButton.currentTitle, @"发送验证码");
    XCTAssertEqualObjects(chg.primaryButton.currentTitle, @"发送验证码");
    NSArray *bs = [bind valueForKey:@"sections"], *cs = [chg valueForKey:@"sections"];
    XCTAssertEqualObjects([bs.firstObject valueForKey:@"footer"], IMLocalized(@"email.bind.footer"));
    XCTAssertEqualObjects([cs.firstObject valueForKey:@"footer"], IMLocalized(@"email.change.footer"));
}

- (void)test_验证码页_复用两步验证码框_清洗_Timer随页面生命周期 {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
    IMEmailCodeViewController *vc = [[IMEmailCodeViewController alloc] initWithHost:@"h" userID:@"u" email:@"a@b.com" proof:[IMIdentityProof passwordProof:@"pw"]
                                                            proofSession:nil resendDeadline:deadline];
    [vc loadViewIfNeeded];
    XCTAssertEqual(vc.codeField.keyboardType, UIKeyboardTypeNumberPad);
    XCTAssertEqualObjects(vc.codeField.textContentType, UITextContentTypeOneTimeCode);
    XCTAssertTrue([vc.resendLabel.text hasPrefix:@"重新发送（"], @"%@", vc.resendLabel.text);
    XCTAssertEqualObjects(vc.resendLabel.textColor, UIColor.tertiaryLabelColor, @"倒计时中灰色");
    XCTAssertFalse(vc.countdownRunning);
    [vc viewWillAppear:NO];
    XCTAssertTrue(vc.countdownRunning, @"在屏且倒计时中 → Timer 在跑");
    [vc viewWillDisappear:NO];
    XCTAssertFalse(vc.countdownRunning, @"离开页面销毁 Timer");
    [vc viewWillAppear:NO];
    XCTAssertTrue(vc.countdownRunning, @"回到页面按截止时刻重建");
    [vc viewWillDisappear:NO];
    vc.codeField.text = @"12 34";
    [vc.codeField sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqualObjects(vc.codeField.text, @"1234", @"清洗复用 IMTwoStepSanitizeCode");
}

- (void)test_验证码页_无倒计时时不起Timer_文案恢复 {
    IMEmailCodeViewController *vc = [[IMEmailCodeViewController alloc] initWithHost:@"h" userID:@"u" email:@"a@b.com" proof:[IMIdentityProof passwordProof:@"pw"]
                                                            proofSession:nil resendDeadline:[NSDate dateWithTimeIntervalSinceNow:-1]];
    [vc loadViewIfNeeded];
    [vc viewWillAppear:NO];
    XCTAssertFalse(vc.countdownRunning);
    XCTAssertEqualObjects(vc.resendLabel.text, @"重新发送");
    XCTAssertEqualObjects(vc.resendLabel.textColor, UIColor.systemBlueColor);
    [vc viewWillDisappear:NO];
}

- (void)test_根页_未绑定_available为false时主按钮置灰并提示 {
    IMEmailLoginViewController *vc = [[IMEmailLoginViewController alloc] initWithHost:@"h" userID:@"u"];
    [vc loadViewIfNeeded];
    IMEmailState *s = [IMEmailState stateFromJSON:@{ @"available": @NO, @"bound": @NO }];
    [vc applyState:s];
    XCTAssertEqualObjects(vc.primaryButton.currentTitle, @"绑定邮箱");
    XCTAssertFalse(vc.primaryButton.enabled);
    __block UILabel *hero = nil;
    [self collectLabelsIn:vc.tableView.tableHeaderView into:^(UILabel *l) { if ([l.text isEqualToString:@"邮件服务暂未启用"]) { hero = l; } }];
    XCTAssertNotNil(hero, @"available:false → 说明下追加「邮件服务暂未启用」");
    [vc applyState:[IMEmailState stateFromJSON:@{ @"available": @YES, @"bound": @NO }]];
    XCTAssertTrue(vc.primaryButton.enabled);
}

- (void)test_根页_已绑定_邮箱_更换_解绑 {
    IMEmailLoginViewController *vc = [[IMEmailLoginViewController alloc] initWithHost:@"h" userID:@"u"];
    [vc loadViewIfNeeded];
    [vc applyState:[IMEmailState stateFromJSON:@{ @"available": @NO, @"bound": @YES, @"email": @"alice@example.com", @"verified_at": @1793318400000 }]];
    XCTAssertTrue(vc.primaryButton.hidden, @"已绑定无主按钮");
    NSMutableArray *texts = [NSMutableArray array];
    [self collectLabelsIn:vc.tableView.tableHeaderView into:^(UILabel *l) { [texts addObject:l.text ?: @""]; }];
    XCTAssertTrue([texts containsObject:@"alice@example.com"]);
    XCTAssertTrue([[texts componentsJoinedByString:@"|"] containsString:@"绑定于"]);
    NSArray *sections = [vc valueForKey:@"sections"];
    XCTAssertEqual(sections.count, 2u, @"更换邮箱 / 解除绑定两组；available:false 时已绑定账号仍可解绑");
    XCTAssertEqualObjects([sections.lastObject valueForKey:@"footer"], IMLocalized(@"email.bound.footer"));
}

- (void)test_解绑页_红按钮_身份确认在弹层里 {
    IMEmailUnbindViewController *vc = [[IMEmailUnbindViewController alloc] initWithHost:@"h" userID:@"u"];
    [vc loadViewIfNeeded];
    XCTAssertEqualObjects(vc.primaryButton.currentTitle, @"解除绑定");
    XCTAssertEqualObjects(vc.primaryButton.backgroundColor, UIColor.systemRedColor);
    XCTAssertTrue(vc.primaryButton.enabled, @"页面上不再有密码框，直接可点（确认后弹确认身份弹层）");
    XCTAssertNotNil(vc.proofSession);
}

- (IMEmailCodeViewController *)loadedCodePage {
    IMEmailCodeViewController *vc = [[IMEmailCodeViewController alloc] initWithHost:@"h" userID:@"u" email:@"a@b.com" proof:[IMIdentityProof passwordProof:@"pw"]
                                                            proofSession:nil resendDeadline:[NSDate dateWithTimeIntervalSinceNow:-1]];
    [vc loadViewIfNeeded];
    return vc;
}

- (void)test_验证码页_码错清空重聚焦_带剩余次数_密码仍留着供重发 {
    IMEmailCodeViewController *vc = [self loadedCodePage];
    vc.codeField.text = @"111111";
    NSError *err = IMErrorByAttachingEmailInfo([NSError errorWithDomain:@"t" code:200032 userInfo:nil], @{ @"data": @{ @"attempts_left": @2 } });
    [vc handleVerify:nil error:err];
    XCTAssertEqualObjects(vc.codeField.text, @"", @"满 6 位被拒，清空");
    XCTAssertEqualObjects([vc valueForKey:@"inlineError"], @"验证码不正确，还可尝试 2 次");
    NSArray *secs = [vc valueForKey:@"sections"];
    XCTAssertEqual(secs.count, 3u, @"码框 / 重新发送 / 更换邮箱三组");
    XCTAssertEqualObjects([secs[0] valueForKey:@"footer"], @"验证码不正确，还可尝试 2 次", @"红字是码框组的 footer，紧贴码框、在重发行之上");
    XCTAssertEqualObjects([secs[0] valueForKey:@"footerColor"], UIColor.systemRedColor);
    XCTAssertTrue(vc.errorLabel.superview.hidden, @"表尾红字不用（会落在重发行之下）");
    XCTAssertNotNil([vc valueForKey:@"proof"], @"交过的是密码：留着供重发");
    XCTAssertFalse(vc.busy);
}

- (void)test_验证码页_失效按retry_after重建倒计时 {
    IMEmailCodeViewController *vc = [self loadedCodePage];
    vc.codeField.text = @"111111";
    NSError *err = IMErrorByAttachingEmailInfo([NSError errorWithDomain:@"t" code:200033 userInfo:nil], @{ @"data": @{ @"retry_after_sec": @30 } });
    [vc handleVerify:nil error:err];
    XCTAssertEqualObjects([vc valueForKey:@"inlineError"], @"验证码已失效，请重新发送");
    NSArray *secs = [vc valueForKey:@"sections"];
    XCTAssertEqual(secs.count, 3u, @"码框 / 重新发送 / 更换邮箱三组");
    XCTAssertEqualObjects([secs[0] valueForKey:@"footer"], @"验证码已失效，请重新发送", @"红字是码框组的 footer，紧贴码框、在重发行之上");
    XCTAssertEqualObjects([secs[0] valueForKey:@"footerColor"], UIColor.systemRedColor);
    XCTAssertTrue(vc.errorLabel.superview.hidden, @"表尾红字不用（会落在重发行之下）");
    XCTAssertEqualObjects(vc.codeField.text, @"");
    NSInteger left = IMEmailResendRemaining(vc.resendDeadline, [NSDate date]);
    XCTAssertTrue(left > 25 && left <= 30, @"%ld", (long)left);
}

- (void)test_验证码页_绑定成功丢弃密码 {
    IMEmailCodeViewController *vc = [self loadedCodePage];
    [vc handleVerify:[IMEmailState boundStateFromVerifyJSON:@{ @"email": @"a@b.com", @"verified_at": @1793318400000 }] error:nil];
    XCTAssertNil([vc valueForKey:@"proof"], @"流程结束后密码不留内存");
}

- (void)test_验证码页_重发在途时满6位不自动提交 {
    IMEmailCodeViewController *vc = [self loadedCodePage];
    [vc setValue:@YES forKey:@"resending"];
    vc.codeField.text = @"123456";
    [vc.codeField sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertFalse(vc.busy, @"重发在途时提交的是即将作废的旧码，不自动提交");
}

- (void)test_验证码页_交的是短信验证码时不留证明_重发再弹层 {
    IMEmailCodeViewController *vc = [[IMEmailCodeViewController alloc] initWithHost:@"h" userID:@"u" email:@"a@b.com"
                                                                              proof:[IMIdentityProof smsProof:@"123456"]
                                                                       proofSession:nil resendDeadline:[NSDate date]];
    [vc loadViewIfNeeded];
    XCTAssertNil([vc valueForKey:@"proof"], @"验证码已被发信用掉，不能复用");
}

- (void)collectLabelsIn:(UIView *)view into:(void (^)(UILabel *))block {
    if ([view isKindOfClass:UILabel.class]) { block((UILabel *)view); }
    for (UIView *sub in view.subviews) { [self collectLabelsIn:sub into:block]; }
}

@end
