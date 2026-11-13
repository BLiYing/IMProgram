//  IMPhoneAuthTests.m
//  手机号与短信验证码（PHONE_AUTH_DESIGN / PROTOCOL §7.3）：纯规则（登录页页签 / 链接 / 地区、确认身份弹层页签与错误落点、
//  隐私与安全两行、没用掉的验证码缓存、按号码计的倒计时、本机用户名可信判定、错误文案）、系统通知新事件、日志脱敏、
//  网络层请求体与错误附加值（NSURLProtocol 桩，只拦本测试专用 host）、确认身份弹层与登录页的可见性接线。

#import <XCTest/XCTest.h>
#import "IMPhoneAuth.h"
#import "IMHTTPService+Phone.h"
#import "IMHTTPService+Account.h"
#import "IMHTTPService+TwoStep.h"
#import "IMHTTPLogFormatter.h"
#import "IMSysEventFormatter.h"
#import "IMIdentityProofSheet.h"
#import "IMLiquidSegmentedControl.h"
#import "IMSMSCodeField.h"
#import "IMLoginViewController.h"
#import "IMLoginPhoneFields.h"
#import "IMLocalization.h"

static NSString * const kIMPhoneTestHost = @"127.0.0.1:59395";

#pragma mark - HTTP 桩

@interface IMPhoneStub : NSURLProtocol
@end
@implementation IMPhoneStub
static NSDictionary *pResp; static NSString *pPath; static NSDictionary *pBody;
+ (BOOL)canInitWithRequest:(NSURLRequest *)r {
    return [r.URL.host isEqualToString:@"127.0.0.1"] && r.URL.port.integerValue == 59395;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    pPath = self.request.URL.path;
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
    pBody = [obj isKindOfClass:NSDictionary.class] ? obj : nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:pResp ?: @{ @"code": @0, @"data": @{} } options:0 error:NULL];
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                     headerFields:@{ @"Content-Type": @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface IMLoginViewController (PhoneTestAccess)
@property (nonatomic, strong, nullable) IMLoginConfig *loginConfig;
@property (nonatomic, assign) IMLoginTab tab;
@property (nonatomic, assign) BOOL touched;
- (void)applyLoginConfig:(IMLoginConfig *)config host:(nullable NSString *)host hostChanged:(BOOL)hostChanged;
@end

@interface IMPhoneAuthTests : XCTestCase
@end

@implementation IMPhoneAuthTests {
    NSString *_savedHost;
    NSString *_savedUsername;
}

- (void)setUp {
    [super setUp];
    [IMLocalization.shared setPreference:IMLanguagePrefZhHans];
    _savedHost = IMHTTPService.sharedService.host;
    _savedUsername = IMHTTPService.sharedService.username;
    pResp = nil; pPath = nil; pBody = nil;
    [NSURLProtocol registerClass:IMPhoneStub.class];
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:IMPhoneStub.class];
    IMHTTPService.sharedService.host = _savedHost;
    IMHTTPService.sharedService.username = _savedUsername;
    [super tearDown];
}

- (IMLoginConfig *)configWith:(NSDictionary *)data {
    NSData *raw = [NSJSONSerialization dataWithJSONObject:@{ @"code": @0, @"data": data } options:0 error:NULL];
    return [IMLoginConfig configFromResponseData:raw];
}

- (IMSecurityState *)security:(BOOL)pwd phone:(BOOL)phone sms:(BOOL)sms {
    IMSecurityState *s = [IMSecurityState new];
    s.passwordSet = pwd; s.phoneBound = phone; s.smsAvailable = sms;
    s.phoneMasked = phone ? @"+86 136****0001" : nil;
    return s;
}

#pragma mark - public-config

- (void)test_配置解析_新字段与老服务端口径 {
    IMLoginConfig *c = [self configWith:@{ @"register_enabled": @YES, @"sms_available": @YES,
                                           @"sms_regions": @[ @{ @"code": @"86", @"iso": @"CN" }, @{ @"code": @"60", @"iso": @"MY" } ],
                                           @"register_methods": @[ @"username", @"phone" ] }];
    XCTAssertTrue(c.smsAvailable);
    XCTAssertEqual(c.smsRegions.count, 2u);
    XCTAssertEqualObjects(c.smsRegions[1].code, @"60");
    XCTAssertEqualObjects(c.registerMethods, (@[ @"username", @"phone" ]));
    IMLoginConfig *old = [self configWith:@{ @"register_enabled": @NO }];
    XCTAssertFalse(old.smsAvailable, @"老服务端没有字段 = 短信不可用");
    XCTAssertFalse(old.registerEnabled);
    XCTAssertEqualObjects(old.registerMethods, @[ @"username" ], @"老服务端 = 可用户名注册");
    IMLoginConfig *bad = [IMLoginConfig configFromResponseData:[@"<html>" dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertFalse(bad.smsAvailable); XCTAssertTrue(bad.registerEnabled);
    IMLoginConfig *off = [self configWith:@{ @"sms_available": @NO, @"sms_regions": @[ @{ @"code": @"86", @"iso": @"CN" } ] }];
    XCTAssertEqual(off.smsRegions.count, 0u, @"短信不可用时不出地区");
}

#pragma mark - 登录页规则

- (void)test_登录页_页签_默认与配置晚到 {
    IMLoginConfig *sms = [self configWith:@{ @"sms_available": @YES, @"sms_regions": @[ @{ @"code": @"86", @"iso": @"CN" } ],
                                             @"register_methods": @[ @"username", @"phone" ] }];
    IMLoginConfig *noSMS = [self configWith:@{ @"sms_available": @NO, @"register_methods": @[ @"username" ] }];
    XCTAssertEqualObjects(IMLoginTabsForConfig(sms), (@[ @(IMLoginTabSMS), @(IMLoginTabPassword) ]));
    XCTAssertEqualObjects(IMLoginTabsForConfig(noSMS), @[ @(IMLoginTabPassword) ]);
    XCTAssertEqualObjects(IMLoginTabsForConfig(nil), @[ @(IMLoginTabPassword) ], @"还没取到 = 老服务端口径");
    XCTAssertEqual(IMLoginInitialTab(IMLoginTabsForConfig(sms), IMLoginTabNone), IMLoginTabSMS, @"短信可用默认验证码登录");
    XCTAssertEqual(IMLoginInitialTab(IMLoginTabsForConfig(sms), IMLoginTabPassword), IMLoginTabPassword, @"记住上次的页签");
    XCTAssertEqual(IMLoginInitialTab(IMLoginTabsForConfig(noSMS), IMLoginTabSMS), IMLoginTabPassword, @"记着验证码但短信不可用");
    XCTAssertEqual(IMLoginTabAfterConfig(IMLoginTabPassword, YES, IMLoginTabsForConfig(sms), IMLoginTabNone), IMLoginTabPassword,
                   @"用户已动过：配置晚到不再切页签");
    XCTAssertEqual(IMLoginTabAfterConfig(IMLoginTabPassword, NO, IMLoginTabsForConfig(sms), IMLoginTabNone), IMLoginTabSMS);
    XCTAssertEqual(IMLoginTabAfterConfig(IMLoginTabSMS, YES, IMLoginTabsForConfig(noSMS), IMLoginTabNone), IMLoginTabPassword, @"当前页签已不可见");
}

- (void)test_登录页_链接_提示_地区 {
    IMLoginConfig *both = [self configWith:@{ @"sms_available": @YES, @"sms_regions": @[ @{ @"code": @"86", @"iso": @"CN" } ],
                                              @"register_methods": @[ @"username", @"phone" ] }];
    IMLoginConfig *phoneOnly = [self configWith:@{ @"sms_available": @YES, @"register_methods": @[ @"phone" ],
                                                   @"sms_regions": @[ @{ @"code": @"86", @"iso": @"CN" }, @{ @"code": @"60", @"iso": @"MY" } ] }];
    IMLoginConfig *noSMS = [self configWith:@{ @"sms_available": @NO, @"register_methods": @[ @"username" ] }];
    XCTAssertTrue(IMLoginShowsForgotPassword(both));
    XCTAssertFalse(IMLoginShowsForgotPassword(noSMS), @"短信不可用不显示「忘记密码？」");
    XCTAssertFalse(IMLoginShowsForgotPassword(nil));
    XCTAssertTrue(IMLoginShowsUsernameRegister(both));
    XCTAssertFalse(IMLoginShowsUsernameRegister(phoneOnly), @"register_methods 不含 username 不显示");
    XCTAssertTrue(IMLoginShowsUsernameRegister(nil), @"取不到按可注册");
    XCTAssertTrue(IMLoginShowsAutoRegisterHint(both));
    XCTAssertFalse(IMLoginShowsAutoRegisterHint(noSMS));
    XCTAssertFalse(IMLoginShowsRegionPicker(both), @"一个地区：固定 +86 不可点");
    XCTAssertTrue(IMLoginShowsRegionPicker(phoneOnly));
    XCTAssertEqualObjects(IMLoginDefaultCountryCode(nil), @"86");
    XCTAssertFalse(IMLoginShouldResetCountryCode(NO, @"60", phoneOnly), @"重载配置不重置用户选的国家码");
    XCTAssertTrue(IMLoginShouldResetCountryCode(YES, @"60", phoneOnly), @"换了服务器");
    XCTAssertTrue(IMLoginShouldResetCountryCode(NO, @"60", both), @"该地区下线");
    XCTAssertFalse(IMLoginShouldResetCountryCode(NO, @"60", noSMS), @"开放地区为空不动");
    XCTAssertEqualObjects(IMLoginIdentForReset(@"86", @"136 3333-0001", @"86"), @"13633330001");
    XCTAssertEqualObjects(IMLoginIdentForReset(@"60", @"123456789", @"86"), @"+60123456789", @"非默认地区带 +国家码");
    XCTAssertEqualObjects(IMLoginIdentForReset(@"44", @"+447700900123", @"86"), @"+447700900123", @"已带 + 不再拼一遍");
    XCTAssertEqualObjects(IMLoginIdentForReset(@"44", @"+44 7700 900123", @"86"), @"+447700900123");
    XCTAssertEqualObjects(IMLoginIdentForReset(@"86", @"+86 136 3333 0001", @"86"), @"13633330001", @"默认地区去掉粘贴的 +86");
    XCTAssertEqualObjects(IMLoginIdentForReset(@"86", @"+447700900123", @"86"), @"+447700900123", @"别的国家码原样");
}

- (void)test_记住页签_只认两种值 {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:@"im.phone.tests"];
    [d removePersistentDomainForName:@"im.phone.tests"];
    XCTAssertEqual(IMLoginRememberedTab(d), IMLoginTabNone);
    IMLoginRememberTab(d, IMLoginTabPassword);
    XCTAssertEqual(IMLoginRememberedTab(d), IMLoginTabPassword);
    IMLoginRememberTab(d, IMLoginTabNone);
    XCTAssertEqual(IMLoginRememberedTab(d), IMLoginTabPassword, @"None 不写、不覆盖已记的值");
    [d setInteger:7 forKey:@"im.login.tab"];
    XCTAssertEqual(IMLoginRememberedTab(d), IMLoginTabNone);
    [d removePersistentDomainForName:@"im.phone.tests"];
}

#pragma mark - 号码 / 验证码

- (void)test_号码打码与清洗 {
    XCTAssertEqualObjects(IMPhoneNormalize(@" 136 3333-0001 "), @"13633330001");
    XCTAssertEqualObjects(IMPhoneMasked(@"86", @"136 3333 0001"), @"+86 136****0001");
    XCTAssertEqualObjects(IMPhoneMasked(@"60", @"123456789"), @"+60 123**6789");
    XCTAssertEqualObjects(IMPhoneMasked(@"86", @"12345"), @"+86 *****", @"太短整体打码");
    XCTAssertEqualObjects(IMPhoneNationalNumber(@"86", @"+86 136 3333-0001"), @"13633330001", @"粘贴带当前国家码：去掉前缀");
    XCTAssertEqualObjects(IMPhoneNationalNumber(@"44", @"+44 7700 900123"), @"7700900123");
    XCTAssertEqualObjects(IMPhoneNationalNumber(@"86", @"136 3333-0001"), @"13633330001", @"本地号码同 IMPhoneNormalize");
    XCTAssertEqualObjects(IMPhoneNationalNumber(@"86", @"+44 7700900123"), @"+447700900123", @"别的国家码原样交给服务端");
    XCTAssertEqualObjects(IMPhoneNationalNumber(@"1", @"+1 415 555 0100"), @"4155550100");
    XCTAssertEqualObjects(IMPhoneNationalNumber(nil, @"+86 13633330001"), @"+8613633330001", @"没有国家码不动");
    XCTAssertEqualObjects(IMPhoneMasked(@"86", IMPhoneNationalNumber(@"86", @"+86 136 3333 0001")), @"+86 136****0001",
                          @"去掉前缀后打码才对");
    XCTAssertEqualObjects(IMSMSCodeSanitize(@"验证码 12-34 56 78"), @"123456");
    XCTAssertEqualObjects(IMSMSCodeSanitize(@"１２３４５６"), @"123456", @"全角数字转半角（与两步验证同一清洗）");
    XCTAssertTrue(IMSMSCodeIsComplete(IMSMSCodeSanitize(@"１２３４５６")));
    XCTAssertTrue(IMSMSCodeIsComplete(@"000000"));
    XCTAssertFalse(IMSMSCodeIsComplete(@"00000"));
    XCTAssertFalse(IMSMSCodeIsComplete(@"00000a"));
    XCTAssertEqualObjects(IMNewPasswordErrorKey(@"12345", @"12345"), @"reset.too_short");
    XCTAssertEqualObjects(IMNewPasswordErrorKey(@"123456", @"123457"), @"reset.mismatch");
    XCTAssertNil(IMNewPasswordErrorKey(@"123456", @"123456"));
}

- (void)test_错误文案 {
    XCTAssertEqualObjects(IMSMSSubmitErrorMessage(200043, 3, @"fb"), @"验证码不正确，还可尝试 3 次");
    XCTAssertEqualObjects(IMSMSSubmitErrorMessage(200043, -1, @"fb"), IMLocalized(@"err.200043"));
    XCTAssertEqualObjects(IMSMSSubmitErrorMessage(200047, -1, @"fb"), IMLocalized(@"err.200047"));
    XCTAssertEqualObjects(IMSMSSubmitErrorMessage(999999, -1, @"fb"), @"fb");
    XCTAssertEqualObjects(IMSMSSendErrorMessage(100002, 42, @"fb"), @"发送过于频繁，请 42 秒后再试");
    XCTAssertEqualObjects(IMSMSSendErrorMessage(100002, -1, @"fb"), IMLocalized(@"sms.err.too_frequent"));
    XCTAssertEqualObjects(IMPhoneAuthFriendlyMessage(200048), IMLocalized(@"err.200048"));
    XCTAssertNil(IMPhoneAuthFriendlyMessage(200039));
    XCTAssertEqualObjects(IMFriendlyMessageForCode(200041), IMLocalized(@"err.200041"), @"HTTP 层统一映射");
    XCTAssertEqual(IMSMSCountdownAfterFailure(100002, 30), 30);
    XCTAssertEqual(IMSMSCountdownAfterFailure(200044, 12), 12);
    XCTAssertEqual(IMSMSCountdownAfterFailure(200044, 0), -1);
    XCTAssertEqual(IMSMSCountdownAfterFailure(200043, 30), -1);
}

#pragma mark - 确认身份弹层规则

- (void)test_弹层页签 {
    XCTAssertEqualObjects(IMProofTabsForState([self security:YES phone:YES sms:YES]), (@[ @(IMProofTabPassword), @(IMProofTabSMS) ]));
    XCTAssertEqualObjects(IMProofTabsForState([self security:NO phone:YES sms:YES]), @[ @(IMProofTabSMS) ], @"没设密码只有验证码");
    XCTAssertEqualObjects(IMProofTabsForState([self security:YES phone:NO sms:YES]), @[ @(IMProofTabPassword) ], @"没绑手机只有密码");
    XCTAssertEqualObjects(IMProofTabsForState([self security:YES phone:YES sms:NO]), @[ @(IMProofTabPassword) ], @"短信不可用只有密码");
    XCTAssertEqualObjects(IMProofTabsForState([self security:NO phone:YES sms:NO]), @[], @"没设密码 + 短信不可用：没有可用方式");
    XCTAssertEqualObjects(IMProofTabsForState([self security:NO phone:NO sms:YES]), @[], @"没设密码 + 没绑手机：没有可用方式");
    XCTAssertEqualObjects(IMProofTabsForState(nil), @[ @(IMProofTabPassword) ], @"取不到状态：老账号都有密码 → 密码");
    XCTAssertFalse(IMProofShowsSegments(@[ @(IMProofTabSMS) ]));
    XCTAssertTrue(IMProofShowsSegments(@[ @(IMProofTabPassword), @(IMProofTabSMS) ]));
    XCTAssertTrue(IMProofCanConfirm(IMProofTabPassword, @"x", nil, NO));
    XCTAssertFalse(IMProofCanConfirm(IMProofTabPassword, @"x", nil, YES), @"提交中");
    XCTAssertFalse(IMProofCanConfirm(IMProofTabSMS, nil, @"12345", NO));
    XCTAssertTrue(IMProofCanConfirm(IMProofTabSMS, nil, @"123456", NO));
}

- (void)test_弹层错误落点 {
    XCTAssertTrue(IMProofErrorStaysInSheet(200002, nil), @"密码错留在弹层");
    XCTAssertTrue(IMProofErrorStaysInSheet(200043, nil));
    XCTAssertTrue(IMProofErrorStaysInSheet(200044, nil));
    XCTAssertTrue(IMProofErrorStaysInSheet(200040, @"proof"), @"field=proof 一律弹层");
    XCTAssertFalse(IMProofErrorStaysInSheet(200040, nil), @"200040 不带 field → 页面");
    XCTAssertFalse(IMProofErrorStaysInSheet(200043, @"code"), @"新号码那个码错 → 页面");
    XCTAssertFalse(IMProofErrorStaysInSheet(100002, nil), @"100002 一律页面");
    XCTAssertFalse(IMProofErrorStaysInSheet(100002, @"proof"), @"100002 一律页面");
    XCTAssertFalse(IMProofErrorStaysInSheet(100103, nil), @"群主阻断 → 页面");
    XCTAssertFalse(IMProofErrorStaysInSheet(200042, nil));
}

- (void)test_没用掉的验证码缓存 {
    IMProofCodeCache *c = [IMProofCodeCache new];
    IMIdentityProof *sms = [IMIdentityProof smsProof:@"123456"], *pwd = [IMIdentityProof passwordProof:@"pw"];
    [c notePageErrorAfterProof:sms];
    XCTAssertEqualObjects(c.code, @"123456", @"页面错误：码仍有效，记下");
    [c notePageErrorAfterProof:pwd];
    XCTAssertEqualObjects(c.code, @"123456", @"交的是密码：缓存不动");
    [c noteProofRejected:pwd];
    XCTAssertEqualObjects(c.code, @"123456", @"密码错不影响缓存的码");
    [c noteProofRejected:sms];
    XCTAssertNil(c.code, @"服务端判错过的码不保留");
    [c noteCancelledWithTypedCode:@"654321" tabWasSMS:YES];
    XCTAssertEqualObjects(c.code, @"654321", @"取消时输完整的码记下");
    [c noteCancelledWithTypedCode:@"6543" tabWasSMS:YES];
    XCTAssertNil(c.code, @"输了一半的不留");
    [c noteCancelledWithTypedCode:@"111111" tabWasSMS:YES];
    [c noteCancelledWithTypedCode:@"" tabWasSMS:NO];
    XCTAssertEqualObjects(c.code, @"111111", @"停在密码页签取消：不动");
    [c noteResent];
    XCTAssertNil(c.code, @"重新获取后旧码作废");
    [c notePageErrorAfterProof:sms];
    [c noteSucceeded];
    XCTAssertNil(c.code, @"操作成功即清");
}

- (void)test_倒计时按号码计 {
    IMResendClock *clock = [IMResendClock new];
    NSDate *t0 = [NSDate dateWithTimeIntervalSince1970:1000];
    [clock followTarget:@"86:13633330001"];
    XCTAssertEqual([clock secondsLeftAt:t0], 0);
    [clock noteSentWithResendAfter:60 now:t0];
    XCTAssertTrue(clock.sentOnce);
    XCTAssertEqual([clock secondsLeftAt:[t0 dateByAddingTimeInterval:0.5]], 60, @"向上取整");
    [clock followTarget:@"86:13633330001"];
    XCTAssertEqual([clock secondsLeftAt:t0], 60, @"同一号码不动");
    [clock followTarget:@"86:13633330002"];
    XCTAssertEqual([clock secondsLeftAt:t0], 0, @"换号码清本地截止时刻");
    XCTAssertFalse(clock.sentOnce);
    [clock noteSentWithResendAfter:-1 now:t0];
    XCTAssertEqual([clock secondsLeftAt:t0], 60, @"服务端没给按 60");
    [clock noteFailureCode:100002 retryAfter:17 now:t0];
    XCTAssertEqual([clock secondsLeftAt:t0], 17, @"以服务端 retry_after_sec 为准");
    [clock noteFailureCode:200045 retryAfter:99 now:t0];
    XCTAssertEqual([clock secondsLeftAt:t0], 17, @"其它失败不动");
    XCTAssertEqualObjects(IMSMSSendButtonTitle(52, YES), @"52 秒后重发");
    XCTAssertEqualObjects(IMSMSSendButtonTitle(0, NO), IMLocalized(@"login.sms_code.send"));
    XCTAssertEqualObjects(IMSMSSendButtonTitle(0, YES), IMLocalized(@"login.sms_code.resend"));
}

#pragma mark - 隐私与安全

- (void)test_隐私与安全两行 {
    XCTAssertFalse(IMSecurityShowsPhoneRow(nil), @"状态未知不显示");
    XCTAssertFalse(IMSecurityShowsPhoneRow([self security:YES phone:NO sms:NO]), @"短信不可用且没绑定：没法绑");
    XCTAssertTrue(IMSecurityShowsPhoneRow([self security:YES phone:YES sms:NO]), @"已绑定仍显示");
    XCTAssertTrue(IMSecurityShowsPhoneRow([self security:YES phone:NO sms:YES]));
    XCTAssertEqualObjects(IMSecurityPhoneRowValue([self security:YES phone:YES sms:YES]), @"+86 136****0001");
    XCTAssertEqualObjects(IMSecurityPhoneRowValue([self security:YES phone:NO sms:YES]), @"未绑定");
    XCTAssertEqualObjects(IMSecurityPasswordRowValue([self security:NO phone:YES sms:YES]), @"未设置");
    XCTAssertEqualObjects(IMSecurityPasswordRowValue([self security:YES phone:YES sms:YES]), @"已设置");
    XCTAssertNil(IMSecurityPasswordRowValue(nil));
    XCTAssertEqual(IMSecurityPhoneRowAction([self security:YES phone:NO sms:YES]), IMPhoneRowActionBind);
    XCTAssertEqual(IMSecurityPhoneRowAction([self security:YES phone:YES sms:YES]), IMPhoneRowActionChange);
    XCTAssertEqual(IMSecurityPhoneRowAction([self security:YES phone:YES sms:NO]), IMPhoneRowActionSMSUnavailable);
    XCTAssertTrue(IMSecurityPasswordPageIsSet([self security:NO phone:YES sms:YES]));
    XCTAssertFalse(IMSecurityPasswordPageIsSet(nil), @"未知按修改");
    XCTAssertEqual(IMSecurityPasswordProofMode(YES, NO, nil), IMPasswordProofModeSMS, @"设置只能验证码");
    XCTAssertEqual(IMSecurityPasswordProofMode(NO, YES, [self security:YES phone:YES sms:YES]), IMPasswordProofModeSMS);
    XCTAssertEqual(IMSecurityPasswordProofMode(NO, YES, [self security:YES phone:NO sms:YES]), IMPasswordProofModeOldPassword,
                   @"没绑手机切不过去");
    IMSecurityState *parsed = [IMSecurityState stateFromJSON:@{ @"phone_bound": @YES, @"phone_masked": @"+86 136****0001",
                                                                @"password_set": @NO, @"sms_available": @YES }];
    XCTAssertTrue(parsed.phoneBound); XCTAssertFalse(parsed.passwordSet); XCTAssertTrue(parsed.smsAvailable);
    XCTAssertTrue([IMSecurityState stateFromJSON:@{}].passwordSet, @"缺 password_set 按有密码");
    XCTAssertNil([IMSecurityState stateFromJSON:@[]]);
}

#pragma mark - 本机用户名

- (void)test_本机用户名可信判定 {
    XCTAssertTrue(IMStoredUsernameIsTrusted(@"ua1b2c3d4e"));
    XCTAssertTrue(IMStoredUsernameIsTrusted(@"user1001"));
    XCTAssertFalse(IMStoredUsernameIsTrusted(@"13633330001"), @"手机号形态");
    XCTAssertFalse(IMStoredUsernameIsTrusted(@"+8613633330001"));
    XCTAssertFalse(IMStoredUsernameIsTrusted(@"alice@example.com"), @"邮箱");
    XCTAssertFalse(IMStoredUsernameIsTrusted(@"Alice1"), @"大写不合规则");
    XCTAssertFalse(IMStoredUsernameIsTrusted(nil));
    XCTAssertTrue(IMStoredUsernameIsTrusted(@"1234567890123456"), @"16 位纯数字不是手机号形态");
}

- (void)test_登录响应后的用户名_续期不带username时保留服务端发的纯数字用户名 {
    XCTAssertEqualObjects(IMUsernameAfterLoginResponse(@"13633330001", @"ua1b2c3d4e", @"13633330001", NO), @"ua1b2c3d4e",
                          @"响应带 username 一律用它");
    XCTAssertEqualObjects(IMUsernameAfterLoginResponse(@"12345678", nil, @"12345678", YES), @"12345678",
                          @"/token/refresh 不带 username：本机存的是服务端发的纯数字用户名 → 保留");
    XCTAssertEqualObjects(IMUsernameAfterLoginResponse(@"12345678", @"", @"12345678", YES), @"12345678");
    XCTAssertNil(IMUsernameAfterLoginResponse(@"12345678", nil, @"12345678", NO), @"老版本存的纯数字值没有服务端标记 → 按形态过滤");
    XCTAssertNil(IMUsernameAfterLoginResponse(@"13633330001", nil, @"user1001", YES), @"内存值不是存着的那个 → 按形态过滤");
    XCTAssertEqualObjects(IMUsernameAfterLoginResponse(@"user1001", nil, nil, NO), @"user1001", @"形态可信照留");
    XCTAssertNil(IMUsernameAfterLoginResponse(nil, nil, nil, YES));
}

#pragma mark - 系统通知 / 日志

- (void)test_系统通知新事件 {
    NSString *at = @"2026-11-13T10:00:00Z";
    NSString *set = IMTextForNoticeSysEvent(@"password_set", @{ @"at": at, @"device": @"iPhone 17" });
    XCTAssertEqual([set componentsSeparatedByString:@"\n"].count, 3u, @"%@", set);
    XCTAssertTrue([set containsString:@"设置了登录密码"]);
    NSString *reset = IMTextForNoticeSysEvent(@"password_reset", @{ @"at": at, @"device": @"x" });
    XCTAssertEqual([reset componentsSeparatedByString:@"\n"].count, 2u, @"password_reset 没有设备行");
    NSString *bound = IMTextForNoticeSysEvent(@"phone_bound", @{ @"at": at, @"phone_masked": @"+86 136****0001" });
    XCTAssertTrue([bound containsString:@"+86 136****0001"]);
    XCTAssertEqual([bound componentsSeparatedByString:@"\n"].count, 2u);
    NSString *changed = IMTextForNoticeSysEvent(@"phone_changed", @{ @"at": at, @"phone_masked": @"+86 136****0002", @"device": @"d" });
    XCTAssertTrue([changed containsString:@"更换为 +86 136****0002"]);
    XCTAssertEqual([changed componentsSeparatedByString:@"\n"].count, 3u);
}

- (void)test_日志脱敏_验证码_票据_新旧密码_手机号登录名 {
    NSDictionary *safe = IMHTTPSanitizedJSONObject(@{ @"proof": @{ @"sms_code": @"123456" }, @"new_password": @"n", @"old_password": @"o",
                                                     @"register_ticket": @"RT", @"restore_ticket": @"ST", @"phone": @"13633330001",
                                                     @"username": @"13633330001", @"country_code": @"86", @"phone_masked": @"+86 136****0001" }, YES);
    XCTAssertEqualObjects(safe[@"proof"][@"sms_code"], @"***");
    XCTAssertEqualObjects(safe[@"new_password"], @"***");
    XCTAssertEqualObjects(safe[@"old_password"], @"***");
    XCTAssertEqualObjects(safe[@"register_ticket"], @"***");
    XCTAssertEqualObjects(safe[@"restore_ticket"], @"***");
    XCTAssertEqualObjects(safe[@"phone"], @"***");
    XCTAssertEqualObjects(safe[@"username"], @"***", @"手机号当登录名也要遮");
    XCTAssertEqualObjects(safe[@"country_code"], @"86");
    XCTAssertEqualObjects(safe[@"phone_masked"], @"+86 136****0001", @"已打码的原样保留");
    NSDictionary *uname = IMHTTPSanitizedJSONObject(@{ @"username": @"user1001", @"uid": @"1234567890" }, YES);
    XCTAssertEqualObjects(uname[@"username"], @"user1001", @"普通用户名不遮");
    XCTAssertEqualObjects(uname[@"uid"], @"1234567890", @"内部 uid 不误打码");
    NSDictionary *spaced = IMHTTPSanitizedJSONObject(@{ @"username": @"136 3333-0001" }, YES);
    XCTAssertEqualObjects(spaced[@"username"], @"***", @"带空格 / 短横线的号码也要遮");
}

#pragma mark - 网络层

- (void)wait:(void (^)(XCTestExpectation *e))block {
    XCTestExpectation *e = [self expectationWithDescription:@"req"];
    block(e);
    [self waitForExpectations:@[e] timeout:10];
}

- (void)test_HTTP_验证码登录_需要完善资料只带票 {
    IMHTTPService.sharedService.host = kIMPhoneTestHost;
    pResp = @{ @"code": @0, @"data": @{ @"need_register": @YES, @"register_ticket": @"RT1", @"expires_in": @600 } };
    __block IMSMSLoginResult *res = nil;
    [self wait:^(XCTestExpectation *e) {
        [IMHTTPService.sharedService loginWithSMSCountryCode:@"86" phone:@"136 3333 0001" code:@"000000"
                                                  completion:^(IMSMSLoginResult *r, NSError *err) { res = r; [e fulfill]; }];
    }];
    XCTAssertEqualObjects(pPath, @"/api/v1/login/sms");
    XCTAssertEqualObjects(pBody[@"phone"], @"13633330001", @"去掉空格");
    XCTAssertEqualObjects(pBody[@"country_code"], @"86");
    XCTAssertEqualObjects(pBody[@"code"], @"000000");
    XCTAssertNotNil(pBody[@"device_id"]);
    XCTAssertTrue(res.needRegister);
    XCTAssertEqualObjects(res.registerTicket, @"RT1");
    XCTAssertNil(res.token);
}

- (void)test_HTTP_完善资料成功_本机用户名只认服务端 {
    IMHTTPService.sharedService.host = kIMPhoneTestHost;
    IMHTTPService.sharedService.username = @"13633330001"; // 模拟残留的输入值
    pResp = @{ @"code": @0, @"data": @{ @"token": @"tok-p", @"uid": @"1000077", @"expires_in": @3600, @"username": @"uabc12345" } };
    __block IMSMSLoginResult *res = nil;
    __block NSString *path = nil; __block NSDictionary *body = nil;
    [self wait:^(XCTestExpectation *e) {
        [IMHTTPService.sharedService registerPhoneWithTicket:@"RT1" nickname:@"小明"
                                                  completion:^(IMSMSLoginResult *r, NSError *err) {
            res = r; path = pPath; body = pBody; // 登录收尾会顺手拉 /users/me 预热昵称，先把这次的请求记下来
            [e fulfill];
        }];
    }];
    XCTAssertEqualObjects(path, @"/api/v1/register/phone");
    XCTAssertEqualObjects(body[@"register_ticket"], @"RT1");
    XCTAssertEqualObjects(body[@"nickname"], @"小明");
    XCTAssertEqualObjects(res.userID, @"1000077");
    XCTAssertEqualObjects(res.username, @"uabc12345");
    XCTAssertEqualObjects(IMHTTPService.sharedService.username, @"uabc12345", @"登录成功响应的 username 覆盖本机值");
    [IMHTTPService.sharedService invalidateToken];
}

- (void)test_HTTP_冷静期带恢复票_两步验证带ticket {
    IMHTTPService.sharedService.host = kIMPhoneTestHost;
    pResp = @{ @"code": @200005, @"message": @"pending", @"data": @{ @"delete_at": @1792000000000, @"restore_ticket": @"ST9",
                                                                     @"restore_expires_in": @600 } };
    __block NSError *err = nil;
    [self wait:^(XCTestExpectation *e) {
        [IMHTTPService.sharedService loginWithSMSCountryCode:@"86" phone:@"13633330001" code:@"000000"
                                                  completion:^(IMSMSLoginResult *r, NSError *er) { err = er; [e fulfill]; }];
    }];
    XCTAssertEqual(err.code, IMErrCodeAccountPendingDeletion);
    XCTAssertEqualObjects(err.userInfo[IMErrorRestoreTicketKey], @"ST9");
    XCTAssertNotNil(err.userInfo[IMErrorDeleteAtKey]);
    pResp = @{ @"code": @200020, @"message": @"2fa", @"data": @{ @"ticket": @"TT", @"methods": @[ @"totp" ] } };
    [self wait:^(XCTestExpectation *e) {
        [IMHTTPService.sharedService loginWithSMSCountryCode:@"86" phone:@"13633330001" code:@"000000"
                                                  completion:^(IMSMSLoginResult *r, NSError *er) { err = er; [e fulfill]; }];
    }];
    XCTAssertEqual(err.code, IMErrCodeTwoStepRequired);
    XCTAssertEqualObjects(err.userInfo[IMErrorTwoStepTicketKey], @"TT");
    [self wait:^(XCTestExpectation *e) {
        [IMHTTPService.sharedService restoreAccountWithTicket:@"ST9" completion:^(NSError *er) { [e fulfill]; }];
    }];
    XCTAssertEqualObjects(pBody, @{ @"restore_ticket": @"ST9" });
}

- (void)test_HTTP_绑定手机号_proof请求体与field落点 {
    IMHTTPService.sharedService.host = kIMPhoneTestHost;
    pResp = @{ @"code": @200043, @"message": @"bad", @"data": @{ @"attempts_left": @4, @"field": @"code" } };
    __block NSError *err = nil;
    [self wait:^(XCTestExpectation *e) {
        [IMHTTPService.sharedService bindPhoneWithToken:@"t" proof:[IMIdentityProof smsProof:@"111111"] countryCode:@"86"
                                                  phone:@"13633330002" code:@"222222"
                                             completion:^(NSString *m, NSError *er) { err = er; [e fulfill]; }];
    }];
    XCTAssertEqualObjects(pPath, @"/api/v1/users/me/phone");
    XCTAssertEqualObjects(pBody, (@{ @"proof": @{ @"sms_code": @"111111" }, @"country_code": @"86",
                                     @"phone": @"13633330002", @"code": @"222222" }));
    XCTAssertEqual(IMSMSAttemptsLeftFromError(err), 4);
    XCTAssertEqualObjects(IMSMSFieldFromError(err), @"code");
    XCTAssertFalse(IMProofErrorStaysInSheet(err.code, IMSMSFieldFromError(err)), @"新号码的码错 → 页面，弹层收起");
    pResp = @{ @"code": @0, @"data": @{ @"phone_masked": @"+86 136****0002" } };
    __block NSString *masked = nil;
    [self wait:^(XCTestExpectation *e) {
        [IMHTTPService.sharedService bindPhoneWithToken:@"t" proof:[IMIdentityProof passwordProof:@"pw"] countryCode:@"86"
                                                  phone:@"13633330002" code:@"000000"
                                             completion:^(NSString *m, NSError *er) { masked = m; [e fulfill]; }];
    }];
    XCTAssertEqualObjects(masked, @"+86 136****0002");
    XCTAssertEqualObjects(pBody[@"proof"], @{ @"password": @"pw" });
}

- (void)test_HTTP_设置密码_发码_安全状态 {
    IMHTTPService.sharedService.host = kIMPhoneTestHost;
    pResp = @{ @"code": @0, @"data": @{ @"ok": @YES } };
    [self wait:^(XCTestExpectation *e) {
        [IMHTTPService.sharedService updatePasswordWithToken:@"t" proof:[IMIdentityProof smsProof:@"000000"] newPassword:@"abc123"
                                                  completion:^(NSError *er) { XCTAssertNil(er); [e fulfill]; }];
    }];
    XCTAssertEqualObjects(pPath, @"/api/v1/users/me/password");
    XCTAssertEqualObjects(pBody, (@{ @"proof": @{ @"sms_code": @"000000" }, @"new_password": @"abc123" }));
    pResp = @{ @"code": @0, @"data": @{ @"expires_in": @300, @"resend_after": @60, @"phone_masked": @"+86 136****0001" } };
    __block IMSMSSendResult *sent = nil;
    [self wait:^(XCTestExpectation *e) {
        [IMHTTPService.sharedService sendVerifyCodeWithToken:@"t" completion:^(IMSMSSendResult *r, NSError *er) { sent = r; [e fulfill]; }];
    }];
    XCTAssertEqualObjects(pPath, @"/api/v1/users/me/verify-code");
    XCTAssertEqual(sent.resendAfter, 60);
    XCTAssertEqualObjects(sent.phoneMasked, @"+86 136****0001");
    pResp = @{ @"code": @100002, @"message": @"slow", @"data": @{ @"retry_after_sec": @37 } };
    __block NSError *err = nil;
    [self wait:^(XCTestExpectation *e) {
        [IMHTTPService.sharedService sendSMSCodeForScene:@"login" countryCode:@"86" phone:@"13633330001" token:nil
                                              completion:^(IMSMSSendResult *r, NSError *er) { err = er; [e fulfill]; }];
    }];
    XCTAssertEqualObjects(pPath, @"/api/v1/sms/send-code");
    XCTAssertEqualObjects(pBody[@"scene"], @"login");
    XCTAssertEqual(IMSMSRetryAfterFromError(err), 37);
    pResp = @{ @"code": @0, @"data": @{ @"phone_bound": @NO, @"password_set": @YES, @"sms_available": @YES } };
    __block IMSecurityState *st = nil;
    [self wait:^(XCTestExpectation *e) {
        [IMHTTPService.sharedService fetchSecurityStateWithToken:@"t" completion:^(IMSecurityState *s, NSError *er) { st = s; [e fulfill]; }];
    }];
    XCTAssertEqualObjects(pPath, @"/api/v1/users/me/security");
    XCTAssertFalse(st.phoneBound); XCTAssertTrue(st.passwordSet);
}

#pragma mark - 界面接线

- (UIWindow *)windowWith:(UIViewController *)vc {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) { if ([s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; } }
    UIWindow *w = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:CGRectZero];
    w.frame = CGRectMake(0, 0, 390, 844);
    w.rootViewController = vc;
    [w makeKeyAndVisible];
    return w;
}

- (void)test_确认身份弹层_只有一种方式不显示分段_缓存的码预填到短信页签 {
    UIViewController *host = [UIViewController new];
    UIWindow *w = [self windowWith:host];
    IMProofSession *session = [[IMProofSession alloc] initWithHost:kIMPhoneTestHost userID:@"u1"];
    session.security = [self security:NO phone:YES sms:YES];
    pResp = @{ @"code": @0, @"data": @{ @"phone_bound": @YES, @"phone_masked": @"+86 136****0001", @"password_set": @NO, @"sms_available": @YES } };
    XCTAssertTrue([session presentFrom:host submit:^(IMIdentityProof *p, void (^f)(NSError *)) { f(nil); } completion:^(BOOL ok, NSError *e) {}]);
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.8]];
    IMIdentityProofSheet *sheet = (IMIdentityProofSheet *)host.presentedViewController;
    XCTAssertTrue([sheet isKindOfClass:IMIdentityProofSheet.class]);
    XCTAssertEqualObjects(sheet.tabs, @[ @(IMProofTabSMS) ], @"没设密码只有验证码页签");
    XCTAssertTrue(sheet.segmentedControl.superview.hidden, @"只有一种方式时不显示分段控件");
    XCTAssertFalse([session presentFrom:host submit:^(IMIdentityProof *p, void (^f)(NSError *)) {} completion:^(BOOL ok, NSError *e) {}],
                   @"已在屏不重复弹");
    [host dismissViewControllerAnimated:NO completion:nil];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    [session.codeCache notePageErrorAfterProof:[IMIdentityProof smsProof:@"246810"]];
    session.security = [self security:YES phone:YES sms:YES];
    pResp = @{ @"code": @0, @"data": @{ @"phone_bound": @YES, @"password_set": @YES, @"sms_available": @YES } };
    [session presentFrom:host submit:^(IMIdentityProof *p, void (^f)(NSError *)) { f(nil); } completion:^(BOOL ok, NSError *e) {}];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.8]];
    sheet = (IMIdentityProofSheet *)host.presentedViewController;
    XCTAssertEqual(sheet.tabs.count, 2u);
    XCTAssertFalse(sheet.segmentedControl.superview.hidden);
    XCTAssertEqual(sheet.tab, IMProofTabSMS, @"有没用掉的码：直接落在短信页签");
    XCTAssertEqualObjects(sheet.codeField.text, @"246810", @"并预填");
    XCTAssertTrue(sheet.confirmButton.enabled);
    [host dismissViewControllerAnimated:NO completion:nil];
    w.hidden = YES;
}

- (void)test_确认身份弹层_取不到状态且没有旧值_提示而不退化成只有密码 {
    UIViewController *host = [UIViewController new];
    UIWindow *w = [self windowWith:host];
    IMProofSession *session = [[IMProofSession alloc] initWithHost:kIMPhoneTestHost userID:@"u1"];
    pResp = @{ @"code": @100003, @"message": @"boom" };
    [session presentFrom:host submit:^(IMIdentityProof *p, void (^f)(NSError *)) { f(nil); } completion:^(BOOL ok, NSError *e) {}];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    IMIdentityProofSheet *sheet = (IMIdentityProofSheet *)host.presentedViewController;
    XCTAssertEqual(sheet.tabs.count, 0u, @"没有页签（不退化成只有密码）");
    XCTAssertEqualObjects(sheet.errorLabel.text, IMLocalized(@"proof.load_failed"));
    XCTAssertTrue(sheet.passwordField.superview.hidden);
    [host dismissViewControllerAnimated:NO completion:nil];
    w.hidden = YES;
}

/// 走 /login（不走续期）：桩回鉴权类错误码时不能去擦宿主 App 真存着的续期凭据。
- (void)useCredentialLoginForTest {
    NSString *savedRefresh = IMHTTPService.sharedService.refreshToken;
    IMHTTPService.sharedService.refreshToken = nil;
    [self addTeardownBlock:^{ IMHTTPService.sharedService.refreshToken = savedRefresh; }];
}

- (void)test_确认身份弹层_没有可用方式_提示且确认不可点 {
    UIViewController *host = [UIViewController new];
    UIWindow *w = [self windowWith:host];
    IMProofSession *session = [[IMProofSession alloc] initWithHost:kIMPhoneTestHost userID:@"u-proof-none"];
    session.security = [self security:NO phone:YES sms:NO];
    [session presentFrom:host submit:^(IMIdentityProof *p, void (^f)(NSError *)) { f(nil); } completion:^(BOOL ok, NSError *e) {}];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.8]];
    IMIdentityProofSheet *sheet = (IMIdentityProofSheet *)host.presentedViewController;
    XCTAssertEqual(sheet.tabs.count, 0u);
    XCTAssertTrue(sheet.passwordField.superview.hidden, @"不退回只有密码");
    XCTAssertTrue(sheet.codeField.superview.hidden);
    XCTAssertTrue(sheet.segmentedControl.superview.hidden);
    XCTAssertEqualObjects(sheet.noticeLabel.text, IMLocalized(@"proof.sms_unavailable"));
    XCTAssertFalse(sheet.noticeLabel.hidden);
    XCTAssertFalse(sheet.confirmButton.enabled, @"确认不可点（取消照常）");
    [host dismissViewControllerAnimated:NO completion:nil];
    w.hidden = YES;
}

- (void)test_确认身份弹层_取token失败_交还页面且不作废验证码 {
    [self useCredentialLoginForTest];
    UIViewController *host = [UIViewController new];
    UIWindow *w = [self windowWith:host];
    IMProofSession *session = [[IMProofSession alloc] initWithHost:kIMPhoneTestHost userID:@"u-proof-tokenfail"];
    session.security = [self security:NO phone:YES sms:YES];
    pResp = @{ @"code": @200002, @"message": @"wrong password" };
    __block BOOL requested = NO, done = NO;
    __block NSError *pageError = nil;
    [session presentFrom:host request:^(NSString *t, IMIdentityProof *p, void (^f)(NSError *)) { requested = YES; f(nil); }
              completion:^(BOOL ok, NSError *e) { done = YES; pageError = e; }];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.8]];
    IMIdentityProofSheet *sheet = (IMIdentityProofSheet *)host.presentedViewController;
    sheet.codeField.text = @"135790";
    [sheet.codeField sendActionsForControlEvents:UIControlEventEditingChanged];
    [sheet.confirmButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    XCTAssertFalse(requested, @"证明根本没送到服务端");
    XCTAssertTrue(done, @"收起弹层，错误交还页面");
    XCTAssertEqual(pageError.code, IMErrCodeWrongPassword);
    XCTAssertNil(host.presentedViewController);
    XCTAssertEqualObjects(session.codeCache.code, @"135790", @"码没交出去：仍有效，留着下次预填");
    w.hidden = YES;
}

- (void)test_确认身份弹层_取状态失败后重试成功_清掉失败文案 {
    [self useCredentialLoginForTest];
    UIViewController *host = [UIViewController new];
    UIWindow *w = [self windowWith:host];
    IMProofSession *session = [[IMProofSession alloc] initWithHost:kIMPhoneTestHost userID:@"u-proof-reload"];
    pResp = @{ @"code": @100003, @"message": @"boom" };
    [session presentFrom:host submit:^(IMIdentityProof *p, void (^f)(NSError *)) { f(nil); } completion:^(BOOL ok, NSError *e) {}];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    IMIdentityProofSheet *sheet = (IMIdentityProofSheet *)host.presentedViewController;
    XCTAssertEqualObjects(sheet.errorLabel.text, IMLocalized(@"proof.load_failed"));
    // 同一份桩体既当登录成功体（取 token）又当安全状态。
    pResp = @{ @"code": @0, @"data": @{ @"token": @"tk-proof-reload", @"phone_bound": @YES, @"password_set": @YES,
                                        @"sms_available": @YES } };
    [sheet.confirmButton sendActionsForControlEvents:UIControlEventTouchUpInside]; // 「重试」
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    XCTAssertEqual(sheet.tabs.count, 2u);
    XCTAssertEqual(sheet.errorLabel.text.length, 0u, @"重试成功后不再挂着 load_failed");
    XCTAssertTrue(sheet.errorLabel.hidden);
    [host dismissViewControllerAnimated:NO completion:nil];
    [IMHTTPService.sharedService invalidateToken];
    w.hidden = YES;
}

- (void)test_登录页_短信可用两页签_不可用只有密码且无忘记密码 {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    id remembered = [d objectForKey:@"im.login.tab"];
    [d removeObjectForKey:@"im.login.tab"]; // 宿主 App 记着的页签不能影响本用例
    [self addTeardownBlock:^{ if (remembered) { [d setObject:remembered forKey:@"im.login.tab"]; } }];
    IMLoginViewController *vc = [IMLoginViewController new];
    [vc loadViewIfNeeded];
    vc.touched = NO;
    IMLoginConfig *sms = [self configWith:@{ @"register_enabled": @YES, @"sms_available": @YES,
                                             @"sms_regions": @[ @{ @"code": @"86", @"iso": @"CN" } ], @"register_methods": @[ @"phone" ] }];
    [vc applyLoginConfig:sms host:@"h" hostChanged:NO];
    XCTAssertEqual(vc.tab, IMLoginTabSMS, @"没动过：配置到了切到默认的验证码登录");
    XCTAssertFalse([[vc valueForKey:@"tabsRow"] isHidden]);
    IMLoginPhoneFields *fields = [vc valueForKey:@"smsFields"];
    XCTAssertFalse(fields.hidden);
    XCTAssertFalse(fields.countryButton.enabled, @"只有一个地区：+86 不可点");
    XCTAssertTrue([[vc valueForKey:@"userIDField"] isHidden]);
    XCTAssertFalse([[vc valueForKey:@"forgotButton"] isHidden]);
    XCTAssertTrue([[vc valueForKey:@"usernameRegisterButton"] isHidden], @"register_methods 不含 username");
    XCTAssertFalse([[vc valueForKey:@"autoRegisterHintLabel"] isHidden]);
    IMLoginConfig *off = [self configWith:@{ @"register_enabled": @YES, @"sms_available": @NO, @"register_methods": @[ @"username" ] }];
    [vc applyLoginConfig:off host:@"h" hostChanged:NO];
    XCTAssertEqual(vc.tab, IMLoginTabPassword);
    XCTAssertTrue([[vc valueForKey:@"tabsRow"] isHidden], @"只有一个页签不画页签条");
    XCTAssertTrue([[vc valueForKey:@"forgotButton"] isHidden]);
    XCTAssertFalse([[vc valueForKey:@"usernameRegisterButton"] isHidden]);
    XCTAssertFalse([[vc valueForKey:@"userIDField"] isHidden]);
}

- (void)test_登录页_用户已动过_配置晚到不切页签 {
    IMLoginViewController *vc = [IMLoginViewController new];
    [vc loadViewIfNeeded];
    vc.tab = IMLoginTabPassword;
    vc.touched = YES;
    IMLoginConfig *sms = [self configWith:@{ @"sms_available": @YES, @"sms_regions": @[ @{ @"code": @"86", @"iso": @"CN" } ] }];
    [vc applyLoginConfig:sms host:@"h" hostChanged:NO];
    XCTAssertEqual(vc.tab, IMLoginTabPassword);
    XCTAssertFalse([[vc valueForKey:@"tabsRow"] isHidden], @"页签条照样出现，只是不自动切");
}

@end
