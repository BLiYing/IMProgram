//  IMProofRecentAuthTests.m
//  PHONE_AUTH_DESIGN §15 落地后的调整：
//  - §15.2 最近验证过免确认：安全状态的 recent_auth_sec、空证明的请求体（不带 proof 也不带顶层 password）、
//    分流 IMProofRunWithoutSheet、IMProofSession 弹出前先取状态（≥15 秒不弹层；回 200049 再弹层用用户的证明重试）；
//  - §15.1 资料里的旧号码：legacy_phone 解析、「登录手机号」页提示（绑定预填 / 不再提示 DELETE 成功收起、失败保留）。
//  HTTP 用 NSURLProtocol 桩：拦本测试专用 host，以及**不管 host** 的几条本测试用到的路径——测试宿主就是真 App，
//  已登录时它自己的续期 / 轮询会在用例途中改 IMHTTPService.host 与 token 缓存（实测），按 host 拦会漏到真服务端。
//  所以 token 也不自己种：宿主有登录态就沿用它的 token 与 uid（不污染、不触发 401 作废），没有才种一枚测试 token。

#import <XCTest/XCTest.h>
#import "IMPhoneAuth.h"
#import "IMHTTPService+Phone.h"
#import "IMHTTPService+Account.h"
#import "IMHTTPService+TwoStep.h"
#import "IMHTTPService+Export.h"
#import "IMHTTPService+Email.h"
#import "IMIdentityProofSheet.h"
#import "IMLiquidSegmentedControl.h"
#import "IMPhoneBindViewController.h"
#import "IMSettingsViewController.h"
#import "IMProfileEditViewController.h"
#import "IMLocalization.h"
#import "IMSessionStore.h"

static NSString * const kRAHost = @"127.0.0.1:59396";
static NSString * const kRAUser = @"u-recent-auth";

#pragma mark - HTTP 桩

@interface IMRAStub : NSURLProtocol
@end
@implementation IMRAStub
static NSMutableArray<NSDictionary *> *sRAReqs;          ///< {method, path, body}
static NSDictionary<NSString *, NSDictionary *> *sRAReplies; ///< path → 响应体；缺省 {code:0,data:{}}
+ (NSMutableArray *)reqs { if (!sRAReqs) { sRAReqs = [NSMutableArray array]; } return sRAReqs; }
+ (void)reset:(NSDictionary *)replies { @synchronized (self) { [self.reqs removeAllObjects]; sRAReplies = replies; } }
+ (NSArray<NSDictionary *> *)requestsForPath:(NSString *)path {
    @synchronized (self) { return [self.reqs filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"path == %@", path]]; }
}
+ (BOOL)canInitWithRequest:(NSURLRequest *)r {
    static NSSet<NSString *> *paths;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        paths = [NSSet setWithArray:@[ @"/api/v1/users/me/security", @"/api/v1/users/me/legacy-phone", @"/api/v1/users/me/phone",
                                       @"/api/v1/users/me", @"/api/v1/public-config" ]];
    });
    return ([r.URL.host isEqualToString:@"127.0.0.1"] && r.URL.port.integerValue == 59396) || [paths containsObject:r.URL.path ?: @""];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    NSData *d = self.request.HTTPBody;
    if (!d && self.request.HTTPBodyStream) {
        NSInputStream *in = self.request.HTTPBodyStream; [in open];
        NSMutableData *m = [NSMutableData data]; uint8_t buf[512]; NSInteger n;
        while ((n = [in read:buf maxLength:sizeof buf]) > 0) { [m appendBytes:buf length:(NSUInteger)n]; }
        [in close]; d = m;
    }
    id o = d.length ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    NSString *path = self.request.URL.path ?: @"";
    NSDictionary *reply;
    @synchronized (IMRAStub.class) {
        [IMRAStub.reqs addObject:@{ @"method": self.request.HTTPMethod ?: @"", @"path": path, @"host": self.request.URL.host ?: @"",
                                    @"body": [o isKindOfClass:NSDictionary.class] ? o : @{} }];
        reply = sRAReplies[path];
    }
    NSData *resp = [NSJSONSerialization dataWithJSONObject:reply ?: @{ @"code": @0, @"data": @{} } options:0 error:NULL];
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                     headerFields:@{ @"Content-Type": @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:resp];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface IMPhoneBindViewController (RecentAuthTestAccess)
@property (nonatomic, readonly, nullable) IMLegacyPhone *legacyPhone;
@property (nonatomic, copy) NSString *countryCode;
@property (nonatomic, assign) BOOL legacyDismissing;
- (void)legacyBindTapped;
- (void)legacyDismissTapped;
@end

@interface IMProfileEditViewController (RecentAuthTestAccess)
@property (nonatomic, strong) UILabel *roPhoneValue;
@property (nonatomic, strong) UIView *roPhoneRow;
@property (nonatomic, assign) BOOL profileLoaded;
@end

@interface IMProofRecentAuthTests : XCTestCase
@end

@implementation IMProofRecentAuthTests {
    NSString *_savedHost, *_savedToken, *_savedTokenUser;
    NSNumber *_savedFetchedAt;
    NSString *_uid; ///< 本用例的 userID：宿主已登录就是它的 uid（命中 token 缓存），否则 kRAUser + 种的 token
}

- (void)setUp {
    [super setUp];
    [IMLocalization.shared setPreference:IMLanguagePrefZhHans];
    IMHTTPService *svc = IMHTTPService.sharedService;
    _savedHost = svc.host;
    _savedToken = [svc valueForKey:@"currentToken"];
    _savedTokenUser = [svc valueForKey:@"tokenUserID"];
    _savedFetchedAt = [svc valueForKey:@"tokenFetchedAt"];
    [self seedToken];
    [IMRAStub reset:nil];
    [NSURLProtocol registerClass:IMRAStub.class];
}

/// 让 withToken 命中 TTL 缓存、不发 /login：宿主已有登录态就沿用（续期只会换成同一 uid 的新 token）；
/// 没有才种一枚测试 token。发起动作前再调一次（宿主可能刚好退出 / 续期失败）。
- (void)seedToken {
    IMHTTPService *svc = IMHTTPService.sharedService;
    NSString *token = [svc valueForKey:@"currentToken"], *owner = [svc valueForKey:@"tokenUserID"];
    if (token.length > 0 && owner.length > 0) { _uid = owner; [svc setValue:@(CFAbsoluteTimeGetCurrent()) forKey:@"tokenFetchedAt"]; return; }
    _uid = kRAUser;
    [svc setValue:@"tk-recent-auth" forKey:@"currentToken"];
    [svc setValue:kRAUser forKey:@"tokenUserID"];
    [svc setValue:@(CFAbsoluteTimeGetCurrent()) forKey:@"tokenFetchedAt"];
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:IMRAStub.class];
    IMHTTPService *svc = IMHTTPService.sharedService;
    svc.host = _savedHost;
    [svc setValue:_savedToken forKey:@"currentToken"];
    [svc setValue:_savedTokenUser forKey:@"tokenUserID"];
    [svc setValue:_savedFetchedAt forKey:@"tokenFetchedAt"];
    [super tearDown];
}

- (void)spinUntil:(BOOL (^)(void))cond {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!cond() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

- (UIWindow *)windowWith:(UIViewController *)vc {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) { if ([s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; } }
    UIWindow *w = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:CGRectZero];
    w.frame = CGRectMake(0, 0, 390, 844);
    w.rootViewController = vc;
    [w makeKeyAndVisible];
    return w;
}

- (NSDictionary *)securityReply:(NSInteger)recentSec {
    return @{ @"code": @0, @"data": @{ @"phone_bound": @YES, @"phone_masked": @"+86 136****0001", @"password_set": @YES,
                                       @"sms_available": @YES, @"recent_auth_sec": @(recentSec) } };
}

#pragma mark - 安全状态解析

- (void)test_安全状态_解析recent_auth_sec与legacy_phone {
    IMSecurityState *s = [IMSecurityState stateFromJSON:@{ @"phone_bound": @NO, @"recent_auth_sec": @598,
        @"legacy_phone": @{ @"country_code": @"86", @"phone": @"13712340002", @"masked": @"+86 137****0002" } }];
    XCTAssertEqual(s.recentAuthSec, 598);
    XCTAssertEqualObjects(s.legacyPhone.countryCode, @"86");
    XCTAssertEqualObjects(s.legacyPhone.phone, @"13712340002");
    XCTAssertEqualObjects(s.legacyPhone.masked, @"+86 137****0002");
    XCTAssertFalse([s.legacyPhone.description containsString:@"13712340002"], @"description 不带明文号码");
    IMSecurityState *old = [IMSecurityState stateFromJSON:@{ @"phone_bound": @NO }];
    XCTAssertEqual(old.recentAuthSec, 0, @"老服务端没有字段 = 要确认");
    XCTAssertNil(old.legacyPhone);
    XCTAssertEqual([IMSecurityState stateFromJSON:@{ @"recent_auth_sec": @-3 }].recentAuthSec, 0, @"负数按 0");
    XCTAssertEqual([IMSecurityState stateFromJSON:@{ @"recent_auth_sec": @"600" }].recentAuthSec, 0, @"不是数字按 0");
}

- (void)test_legacy_phone_缺字段为nil_masked兜底 {
    XCTAssertNil([IMLegacyPhone legacyPhoneFromJSON:nil]);
    XCTAssertNil([IMLegacyPhone legacyPhoneFromJSON:@{ @"country_code": @"86" }]);
    XCTAssertNil(([IMLegacyPhone legacyPhoneFromJSON:@{ @"country_code": @"", @"phone": @"13712340002" }]));
    XCTAssertNil(([IMLegacyPhone legacyPhoneFromJSON:@{ @"country_code": @86, @"phone": @"13712340002" }]));
    IMLegacyPhone *p = [IMLegacyPhone legacyPhoneFromJSON:@{ @"country_code": @"86", @"phone": @"13712340002" }];
    XCTAssertEqualObjects(p.masked, IMPhoneMasked(@"86", @"13712340002"), @"缺 masked 端上补打码");
}

- (void)test_旧号码提示_只在未绑定且有legacy时出现 {
    IMSecurityState *s = [IMSecurityState stateFromJSON:@{ @"phone_bound": @NO,
        @"legacy_phone": @{ @"country_code": @"86", @"phone": @"13712340002", @"masked": @"+86 137****0002" } }];
    XCTAssertNotNil(IMSecurityLegacyPhonePrompt(s));
    s.phoneBound = YES;
    XCTAssertNil(IMSecurityLegacyPhonePrompt(s), @"绑定后（服务端也会清）不再提示");
    XCTAssertNil(IMSecurityLegacyPhonePrompt(nil));
    XCTAssertNil(IMSecurityLegacyPhonePrompt([IMSecurityState stateFromJSON:@{ @"phone_bound": @NO }]));
}

#pragma mark - 空证明的请求体

- (void)test_空证明_请求体既不带proof也不带password {
    IMIdentityProof *empty = [IMIdentityProof emptyProof];
    XCTAssertTrue(empty.isEmpty);
    XCTAssertFalse(empty.isSMS);
    XCTAssertEqualObjects(IMBodyWithProof(@{ @"code": @"1" }, empty), @{ @"code": @"1" });
    XCTAssertEqualObjects(IMBodyWithProof(@{ @"code": @"1" }, [IMIdentityProof passwordProof:@"pw"]),
                          (@{ @"code": @"1", @"proof": @{ @"password": @"pw" } }));
    XCTAssertEqualObjects(IMBodyWithProof(@{}, [IMIdentityProof smsProof:@"123456"]), (@{ @"proof": @{ @"sms_code": @"123456" } }));

    IMHTTPService *svc = IMHTTPService.sharedService;
    svc.host = kRAHost;
    __block NSInteger done = 0;
    [svc deleteAccountWithToken:@"t" proof:empty completion:^(NSError *e) { done++; }];
    [svc setupTwoStepWithToken:@"t" proof:empty completion:^(IMTwoStepSetup *s, NSError *e) { done++; }];
    [svc disableTwoStepWithToken:@"t" proof:empty code:@"111111" completion:^(NSError *e) { done++; }];
    [svc regenerateRecoveryCodesWithToken:@"t" proof:empty code:@"111111" completion:^(NSArray *c, NSError *e) { done++; }];
    [svc unbindEmailWithToken:@"t" proof:empty completion:^(NSError *e) { done++; }];
    [svc sendEmailCodeWithToken:@"t" email:@"a@b.co" proof:empty completion:^(IMEmailSendResult *r, NSError *e) { done++; }];
    [svc startExportWithToken:@"t" proof:empty includeMedia:NO formats:@[ @"html" ] completion:^(IMExportJob *j, NSError *e) { done++; }];
    [svc bindPhoneWithToken:@"t" proof:empty countryCode:@"86" phone:@"13612340001" code:@"000000"
                 completion:^(NSString *m, NSError *e) { done++; }];
    [self spinUntil:^BOOL{ return done == 8; }];
    XCTAssertEqual(done, 8);
    NSArray *reqs;
    @synchronized (IMRAStub.class) { // 只数发到测试 host 的：宿主 App 自己的请求、上一条用例在途的 public-config 不算
        reqs = [IMRAStub.reqs filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"host == %@ AND path != %@",
                                                           @"127.0.0.1", @"/api/v1/public-config"]];
    }
    XCTAssertEqual(reqs.count, 8u);
    for (NSDictionary *r in reqs) {
        XCTAssertNil(r[@"body"][@"proof"], @"%@ 不带 proof", r[@"path"]);
        XCTAssertNil(r[@"body"][@"password"], @"%@ 不带旧的顶层 password", r[@"path"]);
    }
    NSDictionary *bind = [IMRAStub requestsForPath:@"/api/v1/users/me/phone"].firstObject;
    XCTAssertEqualObjects(bind[@"body"][@"code"], @"000000", @"其它字段照常");
}

#pragma mark - 分流（纯规则）

- (void)test_分流_状态未知或剩余不足15秒_照常弹层 {
    for (NSNumber *sec in @[ @0, @14 ]) {
        IMSecurityState *s = [IMSecurityState new];
        s.recentAuthSec = sec.integerValue;
        __block BOOL asked = NO, submitted = NO, completed = NO;
        IMProofRunWithoutSheet(s, ^(IMIdentityProof *p, void (^f)(NSError *)) { submitted = YES; },
                               ^{ asked = YES; }, ^(BOOL ok, NSError *e) { completed = YES; });
        XCTAssertTrue(asked, @"recent=%@", sec);
        XCTAssertFalse(submitted);
        XCTAssertFalse(completed);
    }
    __block BOOL asked = NO;
    IMProofRunWithoutSheet(nil, ^(IMIdentityProof *p, void (^f)(NSError *)) { XCTFail(@"取不到状态不能直接发"); },
                           ^{ asked = YES; }, ^(BOOL ok, NSError *e) { XCTFail(); });
    XCTAssertTrue(asked);
}

- (void)test_分流_剩余15秒以上_空证明直接发_成功即完成 {
    IMSecurityState *s = [IMSecurityState new];
    s.recentAuthSec = 15;
    XCTAssertTrue(IMProofSkipsSheet(s));
    __block IMIdentityProof *sent = nil;
    __block void (^finish)(NSError *) = nil;
    __block NSInteger completions = 0;
    __block BOOL okResult = NO;
    IMProofRunWithoutSheet(s, ^(IMIdentityProof *p, void (^f)(NSError *)) { sent = p; finish = f; },
                           ^{ XCTFail(@"不弹层"); }, ^(BOOL ok, NSError *e) { completions++; okResult = ok; XCTAssertNil(e); });
    XCTAssertTrue(sent.isEmpty, @"空证明");
    finish(nil);
    finish(nil); // 只认第一次
    XCTAssertEqual(completions, 1);
    XCTAssertTrue(okResult);
}

- (void)test_分流_空证明回200049_改为弹层_其它错交给页面 {
    IMSecurityState *s = [IMSecurityState new];
    s.recentAuthSec = 600;
    __block BOOL asked = NO, completed = NO;
    IMProofRunWithoutSheet(s, ^(IMIdentityProof *p, void (^f)(NSError *)) {
        f([NSError errorWithDomain:@"t" code:IMErrCodeProofRequired userInfo:nil]);
    }, ^{ asked = YES; }, ^(BOOL ok, NSError *e) { completed = YES; });
    XCTAssertEqual(IMErrCodeProofRequired, 200049);
    XCTAssertTrue(asked, @"边界上刚好过期：照常弹层");
    XCTAssertFalse(completed, @"不当失败交给页面");

    __block NSError *pageError = nil;
    asked = NO;
    IMProofRunWithoutSheet(s, ^(IMIdentityProof *p, void (^f)(NSError *)) {
        f([NSError errorWithDomain:@"t" code:200010 userInfo:nil]);
    }, ^{ asked = YES; }, ^(BOOL ok, NSError *e) { XCTAssertFalse(ok); pageError = e; });
    XCTAssertFalse(asked);
    XCTAssertEqual(pageError.code, 200010, @"导出进行中等页面错误照常交给页面");
}

#pragma mark - IMProofSession 接线

- (void)test_会话_最近验证过_不弹层_空证明直接请求 {
    [IMRAStub reset:@{ @"/api/v1/users/me/security": [self securityReply:600] }];
    UIViewController *host = [UIViewController new];
    UIWindow *w = [self windowWith:host];
    IMProofSession *session = [[IMProofSession alloc] initWithHost:kRAHost userID:_uid];
    __block IMIdentityProof *sent = nil;
    __block BOOL done = NO, okResult = NO;
    [self seedToken];
    XCTAssertTrue([session presentFrom:host request:^(NSString *t, IMIdentityProof *p, void (^f)(NSError *)) { sent = p; f(nil); }
                            completion:^(BOOL ok, NSError *e) { done = YES; okResult = ok; }]);
    XCTAssertTrue(session.isPresenting, @"取状态途中算在途：不重入");
    XCTAssertFalse([session presentFrom:host submit:^(IMIdentityProof *p, void (^f)(NSError *)) {} completion:^(BOOL ok, NSError *e) {}]);
    [self spinUntil:^BOOL{ return done; }];
    XCTAssertTrue(done);
    XCTAssertTrue(okResult);
    XCTAssertTrue(sent.isEmpty);
    XCTAssertNil(host.presentedViewController, @"没有弹层");
    XCTAssertFalse(session.isPresenting);
    XCTAssertEqual(session.security.recentAuthSec, 600, @"取到的状态留给会话");
    w.hidden = YES;
}

- (void)test_会话_空证明回200049_照常弹层并用用户的证明重试 {
    [IMRAStub reset:@{ @"/api/v1/users/me/security": [self securityReply:300] }];
    UIViewController *host = [UIViewController new];
    UIWindow *w = [self windowWith:host];
    IMProofSession *session = [[IMProofSession alloc] initWithHost:kRAHost userID:_uid];
    NSMutableArray<IMIdentityProof *> *proofs = [NSMutableArray array];
    __block BOOL done = NO, okResult = NO;
    [self seedToken];
    [session presentFrom:host request:^(NSString *t, IMIdentityProof *p, void (^f)(NSError *)) {
        [proofs addObject:p];
        f(p.isEmpty ? [NSError errorWithDomain:@"t" code:IMErrCodeProofRequired userInfo:nil] : nil);
    } completion:^(BOOL ok, NSError *e) { done = YES; okResult = ok; }];
    [self spinUntil:^BOOL{ return [host.presentedViewController isKindOfClass:IMIdentityProofSheet.class]; }];
    IMIdentityProofSheet *sheet = (IMIdentityProofSheet *)host.presentedViewController;
    XCTAssertTrue([sheet isKindOfClass:IMIdentityProofSheet.class], @"200049 → 照常弹层");
    XCTAssertFalse(done);
    [self spinUntil:^BOOL{ return sheet.tabs.count > 0; }];
    XCTAssertEqual(sheet.tabs.count, 2u, @"用刚取到的状态定页签");
    XCTAssertEqual([IMRAStub requestsForPath:@"/api/v1/users/me/security"].count, 1u, @"弹层不再重取一遍");
    if (sheet.tab != IMProofTabPassword) {
        sheet.segmentedControl.selectedIndex = (NSInteger)[sheet.tabs indexOfObject:@(IMProofTabPassword)];
        [sheet.segmentedControl sendActionsForControlEvents:UIControlEventValueChanged];
    }
    sheet.passwordField.text = @"secret-pw";
    [sheet.passwordField sendActionsForControlEvents:UIControlEventEditingChanged];
    [sheet.confirmButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self spinUntil:^BOOL{ return done; }];
    XCTAssertTrue(okResult);
    XCTAssertEqual(proofs.count, 2u);
    XCTAssertTrue(proofs[0].isEmpty);
    XCTAssertFalse(proofs[1].isEmpty);
    XCTAssertEqualObjects(proofs[1].secret, @"secret-pw", @"重试带用户的证明");
    w.hidden = YES;
}

- (void)test_会话_剩余不足15秒_照常弹层不直接请求 {
    [IMRAStub reset:@{ @"/api/v1/users/me/security": [self securityReply:14] }];
    UIViewController *host = [UIViewController new];
    UIWindow *w = [self windowWith:host];
    IMProofSession *session = [[IMProofSession alloc] initWithHost:kRAHost userID:_uid];
    __block BOOL requested = NO;
    [self seedToken];
    [session presentFrom:host request:^(NSString *t, IMIdentityProof *p, void (^f)(NSError *)) { requested = YES; f(nil); }
              completion:^(BOOL ok, NSError *e) {}];
    [self spinUntil:^BOOL{ return host.presentedViewController != nil; }];
    XCTAssertTrue([host.presentedViewController isKindOfClass:IMIdentityProofSheet.class]);
    XCTAssertFalse(requested);
    [host dismissViewControllerAnimated:NO completion:nil];
    w.hidden = YES;
}

#pragma mark - 「登录手机号」页：资料里的旧号码

- (IMPhoneBindViewController *)bindPageWithLegacy {
    IMSecurityState *s = [IMSecurityState stateFromJSON:@{ @"phone_bound": @NO, @"password_set": @YES, @"sms_available": @YES,
        @"legacy_phone": @{ @"country_code": @"60", @"phone": @"123456789", @"masked": @"+60 123****6789" } }];
    IMPhoneBindViewController *vc = [[IMPhoneBindViewController alloc] initWithHost:kRAHost userID:_uid security:s];
    [vc loadViewIfNeeded];
    return vc;
}

- (NSInteger)sectionCount:(IMPhoneBindViewController *)vc {
    return [vc.tableView.dataSource numberOfSectionsInTableView:vc.tableView];
}

- (void)test_登录手机号页_旧号码提示_绑定预填国家码与号码 {
    IMPhoneBindViewController *vc = [self bindPageWithLegacy];
    XCTAssertNotNil(vc.legacyPhone);
    XCTAssertEqual([self sectionCount:vc], 2, @"提示在表单上方");
    [vc legacyBindTapped];
    XCTAssertEqualObjects(vc.countryCode, @"60");
    XCTAssertEqualObjects(vc.phoneField.text, @"123456789");
    XCTAssertNil(vc.legacyPhone);
    XCTAssertEqual([self sectionCount:vc], 1, @"预填后提示收起");
    XCTAssertEqual([IMRAStub requestsForPath:@"/api/v1/users/me/legacy-phone"].count, 0u, @"绑定不清旧号码（成功绑定后服务端自己清）");
    IMSecurityState *bound = [IMSecurityState stateFromJSON:@{ @"phone_bound": @YES, @"phone_masked": @"+86 136****0001" }];
    IMPhoneBindViewController *change = [[IMPhoneBindViewController alloc] initWithHost:kRAHost userID:kRAUser security:bound];
    [change loadViewIfNeeded];
    XCTAssertNil(change.legacyPhone, @"已绑定没有提示");
}

- (void)test_登录手机号页_不再提示_成功收起_失败保留 {
    [IMRAStub reset:@{ @"/api/v1/users/me/legacy-phone": @{ @"code": @100001, @"message": @"boom" } }];
    IMPhoneBindViewController *vc = [self bindPageWithLegacy];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    UIWindow *w = [self windowWith:nav];
    [self seedToken];
    [vc legacyDismissTapped];
    [self spinUntil:^BOOL{ return [IMRAStub requestsForPath:@"/api/v1/users/me/legacy-phone"].count == 1 && !vc.legacyDismissing; }];
    NSDictionary *req = [IMRAStub requestsForPath:@"/api/v1/users/me/legacy-phone"].firstObject;
    XCTAssertEqualObjects(req[@"method"], @"DELETE");
    XCTAssertNotNil(vc.legacyPhone, @"失败：提示留着");
    XCTAssertEqual([self sectionCount:vc], 2);
    XCTAssertEqualObjects(vc.phoneField.text, @"", @"不预填");

    [IMRAStub reset:nil];
    [self seedToken];
    [vc legacyDismissTapped];
    [self spinUntil:^BOOL{ return vc.legacyPhone == nil; }];
    XCTAssertNil(vc.legacyPhone, @"成功：收起");
    XCTAssertEqual([self sectionCount:vc], 1);
    XCTAssertEqual([IMRAStub requestsForPath:@"/api/v1/users/me/legacy-phone"].count, 1u);
    w.hidden = YES;
}

#pragma mark - 绑定后本人资料卡跟着刷新（§15.1：资料卡 phone = 登录手机号）

/// 通知是全局的：宿主 App 在屏的「我」页也会重拉并把昵称 / 头像 / 用户名存进本机缓存，
/// 所以回包沿用宿主已缓存的这三项（手机号本来就不落盘），不往真账号的缓存里写测试值。
- (NSDictionary *)meReply:(nullable NSString *)phone {
    NSString *hostUID = IMSessionStore.userID;
    NSDictionary *cached = hostUID.length > 0 ? [IMSessionStore myProfileForUserID:hostUID] : nil;
    NSMutableDictionary *d = [@{ @"user_id": kRAUser, @"username": cached[@"username"] ?: @"ra_user",
                                 @"nickname": cached[@"nickname"] ?: @"RA", @"avatar_url": cached[@"avatar_url"] ?: @"" } mutableCopy];
    if (phone) { d[@"phone"] = phone; }
    return @{ @"code": @0, @"data": d };
}

- (void)test_绑定成功_发本人资料变更通知_失败不发 {
    IMHTTPService.sharedService.host = kRAHost;
    __block NSInteger posted = 0;
    id obs = [NSNotificationCenter.defaultCenter addObserverForName:IMMyProfileDidChangeNotification object:nil queue:nil
                                                         usingBlock:^(NSNotification *n) { posted++; }];
    [self addTeardownBlock:^{ [NSNotificationCenter.defaultCenter removeObserver:obs]; }];
    __block BOOL done = NO;
    [IMRAStub reset:@{ @"/api/v1/users/me/phone": @{ @"code": @200042, @"message": @"taken" } }];
    [IMHTTPService.sharedService bindPhoneWithToken:@"t" proof:[IMIdentityProof passwordProof:@"pw"] countryCode:@"86"
                                              phone:@"13612340001" code:@"000000" completion:^(NSString *m, NSError *e) { done = YES; }];
    [self spinUntil:^BOOL{ return done; }];
    XCTAssertEqual(posted, 0, @"失败不发");
    done = NO;
    [IMRAStub reset:@{ @"/api/v1/users/me/phone": @{ @"code": @0, @"data": @{ @"phone_masked": @"+86 136****0001" } } }];
    [IMHTTPService.sharedService bindPhoneWithToken:@"t" proof:[IMIdentityProof passwordProof:@"pw"] countryCode:@"86"
                                              phone:@"13612340001" code:@"000000" completion:^(NSString *m, NSError *e) { done = YES; }];
    [self spinUntil:^BOOL{ return done; }];
    XCTAssertEqual(posted, 1, @"成功发一次");
}

- (void)test_本人资料变更通知_我页头部与资料页重拉手机号 {
    IMHTTPService.sharedService.host = kRAHost;
    [IMRAStub reset:@{ @"/api/v1/users/me": [self meReply:nil] }];
    [self seedToken];
    IMSettingsViewController *settings = [[IMSettingsViewController alloc] initWithHost:kRAHost userID:kRAUser];
    [settings loadViewIfNeeded];
    IMProfileEditViewController *profile = [[IMProfileEditViewController alloc] initWithHost:kRAHost userID:_uid];
    [profile loadViewIfNeeded];
    [self spinUntil:^BOOL{ return profile.profileLoaded; }];
    XCTAssertEqual(profile.roPhoneValue.text.length, 0u);

    [IMRAStub reset:@{ @"/api/v1/users/me": [self meReply:@"+86 13612340001"] }];
    [self seedToken];
    [NSNotificationCenter.defaultCenter postNotificationName:IMMyProfileDidChangeNotification object:nil];
    [self spinUntil:^BOOL{
        return [[settings valueForKey:@"myPhone"] isEqual:@"+86 13612340001"] && [profile.roPhoneValue.text isEqual:@"+86 13612340001"];
    }];
    XCTAssertEqualObjects([settings valueForKey:@"myPhone"], @"+86 13612340001", @"「我」页头部");
    XCTAssertEqualObjects(profile.roPhoneValue.text, @"+86 13612340001", @"资料页手机号行");
    XCTAssertFalse(profile.roPhoneRow.hidden, @"未绑定时隐藏的行要露出来");
}

@end
