//  IMHTTPAuthTests.m
//  取 token 的生命周期（IMHTTPService+Auth）：TTL 缓存 / 在途合并 / 用哪条路登录 / 缓存键 / 续期被拒的决策。
//
//  错法全是**静默**的：每切一次页面都白发一次 /login（TTL 失效）、冷启动并发自踢（在途不合并）、
//  拿内部 ID 当用户名登录（登录接口不认）、缓存键用错导致永远 miss。所以按「会怎么错」钉。
//
//  用 NSURLProtocol 只拦**本测试专用用户名**的 /api/v1/login 与 /api/v1/token/refresh，宿主 App 的真实请求不碰；
//  桩的登录响应**不回 refresh_token**（回了会写钥匙串）。**不触发「续期被拒」的真实广播**——
//  SceneDelegate 监听 IMSocketDidRevokeSessionNotification 并会真的登出宿主，那一条只测决策函数。
//  测试前后保存/还原单例上所有被碰的登录态。app-hosted 测试。

#import <XCTest/XCTest.h>

#import "IMHTTPService.h"
#import "IMHTTPService+Private.h"

static NSString *const kStubUser = @"im-auth-stub-user";
static NSString *const kStubRefresh = @"im-auth-stub-refresh";

/// 记录请求并按配置回包。静态配置：一次只跑一个用例（XCTest 串行）。
@interface IMAuthStubProtocol : NSURLProtocol
+ (void)reset;
@property (class, nonatomic, strong) NSMutableArray<NSDictionary *> *requests; // {path, body}
@property (class, nonatomic, assign) NSTimeInterval delay;
@property (class, nonatomic, copy) NSDictionary *response;
@end

@implementation IMAuthStubProtocol
static NSMutableArray *sRequests; static NSTimeInterval sDelay; static NSDictionary *sResponse;
+ (NSMutableArray *)requests { return sRequests; }
+ (void)setRequests:(NSMutableArray *)v { sRequests = v; }
+ (NSTimeInterval)delay { return sDelay; }
+ (void)setDelay:(NSTimeInterval)v { sDelay = v; }
+ (NSDictionary *)response { return sResponse; }
+ (void)setResponse:(NSDictionary *)v { sResponse = v; }
+ (void)reset { sRequests = [NSMutableArray array]; sDelay = 0; sResponse = nil; }

static NSDictionary *BodyOf(NSURLRequest *r) {
    NSData *d = r.HTTPBody;
    if (!d && r.HTTPBodyStream) {
        NSInputStream *in = r.HTTPBodyStream; [in open];
        NSMutableData *m = [NSMutableData data]; uint8_t buf[1024]; NSInteger n;
        while ((n = [in read:buf maxLength:sizeof buf]) > 0) { [m appendBytes:buf length:(NSUInteger)n]; }
        [in close]; d = m;
    }
    id o = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    return [o isKindOfClass:NSDictionary.class] ? o : @{};
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *p = request.URL.path;
    if (![p isEqualToString:@"/api/v1/login"] && ![p isEqualToString:@"/api/v1/token/refresh"]) { return NO; }
    NSDictionary *b = BodyOf(request);
    return [b[@"username"] isEqualToString:kStubUser] || [b[@"refresh_token"] isEqualToString:kStubRefresh];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

- (void)startLoading {
    @synchronized (IMAuthStubProtocol.class) {
        [sRequests addObject:@{ @"path": self.request.URL.path, @"body": BodyOf(self.request) }];
    }
    NSDictionary *resp = sResponse ?: @{ @"code": @0, @"message": @"ok", @"data": @{ @"token": @"tok-from-server", @"uid": @"srv-uid-1" } };
    void (^reply)(void) = ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:resp options:0 error:NULL];
        NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                         headerFields:@{ @"Content-Type": @"application/json" }];
        [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:data];
        [self.client URLProtocolDidFinishLoading:self];
    };
    if (sDelay > 0) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sDelay * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), reply); }
    else { reply(); }
}
- (void)stopLoading {}
@end

@interface IMHTTPAuthTests : XCTestCase
@end

@implementation IMHTTPAuthTests {
    IMHTTPService *_svc;
    NSString *_sHost, *_sUsername, *_sPassword, *_sRefresh, *_sToken, *_sTokenUID, *_sLastUID, *_sNick;
    CFAbsoluteTime _sFetched;
}

- (void)setUp {
    [super setUp];
    _svc = IMHTTPService.sharedService;
    _sHost = _svc.host; _sUsername = _svc.username; _sPassword = _svc.password; _sRefresh = _svc.refreshToken;
    _sToken = _svc.currentToken; _sTokenUID = _svc.tokenUserID; _sLastUID = _svc.lastLoginUserID;
    _sNick = _svc.currentNickname; _sFetched = _svc.tokenFetchedAt;
    if (_svc.host.length == 0) { _svc.host = @"127.0.0.1:59391"; }
    _svc.username = kStubUser;
    _svc.password = @"pw";
    _svc.refreshToken = nil;
    _svc.currentToken = nil; _svc.tokenUserID = nil; _svc.tokenFetchedAt = 0;
    _svc.currentNickname = @"nick-cached"; // 非空：登录成功后不再顺手发 /me 预热请求
    [IMAuthStubProtocol reset];
    [NSURLProtocol registerClass:IMAuthStubProtocol.class];
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:IMAuthStubProtocol.class];
    _svc.host = _sHost; _svc.username = _sUsername; _svc.password = _sPassword;
    _svc.refreshToken = _sRefresh; // 只写内存属性；桩不回 refresh_token，所以钥匙串从未被碰
    _svc.currentToken = _sToken; _svc.tokenUserID = _sTokenUID; _svc.lastLoginUserID = _sLastUID;
    _svc.currentNickname = _sNick; _svc.tokenFetchedAt = _sFetched;
    [super tearDown];
}

/// 同步等一次取 token，返回 (token, error)。
- (NSArray *)obtain:(NSString *)uid force:(BOOL)force {
    __block NSString *tok; __block NSError *err;
    XCTestExpectation *e = [self expectationWithDescription:@"obtain"];
    [_svc obtainTokenForUserID:uid forceCredentialLogin:force completion:^(NSString *t, NSError *er) { tok = t; err = er; [e fulfill]; }];
    [self waitForExpectations:@[e] timeout:10];
    return @[tok ?: NSNull.null, err ?: NSNull.null];
}

- (NSArray<NSDictionary *> *)reqs { @synchronized (IMAuthStubProtocol.class) { return [IMAuthStubProtocol.requests copy]; } }

#pragma mark - TTL 缓存

/// TTL（10 分钟）内同账号直接复用：会话列表每次 viewWillAppear 都走这里，不去重就是每切一次页面一次 POST /login。
- (void)test_TTL内同账号复用缓存_不发请求 {
    _svc.currentToken = @"tok-cached"; _svc.tokenUserID = @"u1"; _svc.tokenFetchedAt = CFAbsoluteTimeGetCurrent();
    NSArray *r = [self obtain:@"u1" force:NO];
    XCTAssertEqualObjects(r[0], @"tok-cached");
    XCTAssertEqual([self reqs].count, 0u);
}

/// 过了 TTL（600s）：重新登录，并刷新缓存时刻。
- (void)test_TTL过期就重新登录 {
    _svc.currentToken = @"tok-old"; _svc.tokenUserID = @"u1"; _svc.tokenFetchedAt = CFAbsoluteTimeGetCurrent() - 601;
    NSArray *r = [self obtain:@"u1" force:NO];
    XCTAssertEqualObjects(r[0], @"tok-from-server");
    XCTAssertEqual([self reqs].count, 1u);
    XCTAssertEqualObjects([self reqs][0][@"path"], @"/api/v1/login");
    XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - _svc.tokenFetchedAt, 5, @"缓存时刻应被刷新");
}

/// 缓存属于另一个账号：不能把别人的 token 给当前账号用（串号），必须重新登录。
- (void)test_换账号不复用别人的缓存 {
    _svc.currentToken = @"tok-of-u1"; _svc.tokenUserID = @"u1"; _svc.tokenFetchedAt = CFAbsoluteTimeGetCurrent();
    NSArray *r = [self obtain:@"u2" force:NO];
    XCTAssertEqualObjects(r[0], @"tok-from-server");
    XCTAssertEqual([self reqs].count, 1u);
}

/// 缓存键用**服务端返回的内部 ID**，不是调用方传的 username：首次登录传 username，之后各处用内部 ID 调用，
/// 若拿 username 当键就会全部 miss、每次真发一次 /login。
- (void)test_缓存键用服务端内部ID {
    [self obtain:@"alice" force:NO];
    XCTAssertEqualObjects(_svc.tokenUserID, @"srv-uid-1");
    XCTAssertEqualObjects(_svc.lastLoginUserID, @"srv-uid-1");
    NSArray *r = [self obtain:@"srv-uid-1" force:NO];
    XCTAssertEqualObjects(r[0], @"tok-from-server");
    XCTAssertEqual([self reqs].count, 1u, @"用内部 ID 再取应命中缓存，不再发请求");
}

#pragma mark - 在途合并

/// 冷启动并发自踢：同账号已有一发在途 → 只排队，回来共享同一枚 token。三个并发只能发**一个**请求。
- (void)test_同账号并发只发一个请求_共享token {
    IMAuthStubProtocol.delay = 0.3;
    XCTestExpectation *e = [self expectationWithDescription:@"three"]; e.expectedFulfillmentCount = 3;
    NSMutableArray *tokens = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        [_svc obtainTokenForUserID:@"u1" forceCredentialLogin:NO completion:^(NSString *t, NSError *er) {
            [tokens addObject:t ?: @"nil"]; [e fulfill];
        }];
    }
    [self waitForExpectations:@[e] timeout:10];
    XCTAssertEqual([self reqs].count, 1u);
    XCTAssertEqualObjects(tokens, (@[@"tok-from-server", @"tok-from-server", @"tok-from-server"]));
}

/// 在途状态必须收干净：第一次失败后，下一次要能重新发请求（否则永远排队、再也登不上）。
- (void)test_失败后在途状态清掉_下次能重发 {
    IMAuthStubProtocol.response = @{ @"code": @200002, @"message": @"bad password" };
    NSArray *r1 = [self obtain:@"u1" force:NO];
    XCTAssertEqualObjects(r1[0], NSNull.null);
    XCTAssertEqual(((NSError *)r1[1]).code, 200002, @"业务码透传，调用方据此区分鉴权失败与网络问题");
    IMAuthStubProtocol.response = nil;
    NSArray *r2 = [self obtain:@"u1" force:NO];
    XCTAssertEqualObjects(r2[0], @"tok-from-server");
    XCTAssertEqual([self reqs].count, 2u);
}

#pragma mark - 走哪条路登录

/// 登录接口只认 username：发出去的必须是 `username` 属性，不是内部 ID（内部 ID 只作缓存键）。
- (void)test_登录请求用username不用内部ID {
    [self obtain:@"1000000007" force:NO];
    NSDictionary *body = [self reqs][0][@"body"];
    XCTAssertEqualObjects(body[@"username"], kStubUser);
    XCTAssertEqualObjects(body[@"password"], @"pw");
    XCTAssertGreaterThan([body[@"device_id"] length], 0u, @"登录必带稳定 device_id，服务端按 (uid,device_id) 顶替");
}

/// 有续期凭据且没强制：走 /token/refresh，**不带密码**。
- (void)test_有续期凭据走refresh不带密码 {
    _svc.refreshToken = kStubRefresh;
    [self obtain:@"u1" force:NO];
    XCTAssertEqualObjects([self reqs][0][@"path"], @"/api/v1/token/refresh");
    XCTAssertEqualObjects([self reqs][0][@"body"][@"refresh_token"], kStubRefresh);
    XCTAssertNil([self reqs][0][@"body"][@"password"]);
}

/// 强制密码登录（比如改密后）：即使有续期凭据也走 /login。
- (void)test_强制密码登录不走refresh {
    _svc.refreshToken = kStubRefresh;
    [self obtain:@"u1" force:YES];
    XCTAssertEqualObjects([self reqs][0][@"path"], @"/api/v1/login");
}

/// 服务端回 code=0 但没有 token：算失败，不能把空 token 当成功缓存下来。
- (void)test_成功码但没有token算失败 {
    IMAuthStubProtocol.response = @{ @"code": @0, @"data": @{ @"uid": @"srv-uid-1" } };
    NSArray *r = [self obtain:@"u1" force:NO];
    XCTAssertEqualObjects(r[0], NSNull.null);
    // 现状：此时错误对象的 code 是 0（服务端业务码本就是 0）。调用方只看 error 是否非空就走失败路径，
    // 但任何按 `error.code` 分类的代码会把它归为「非鉴权失败」——这是合理的，不要为此引入新码。
    XCTAssertTrue([r[1] isKindOfClass:NSError.class], @"必须带 error，调用方据此走失败路径");
    XCTAssertEqual(_svc.currentToken.length, 0u, @"空 token 不能被缓存");
}

#pragma mark - 续期被拒：该不该擦凭据

/// 续期被明确拒绝（凭据不存在/会话已注销/账号被封/token 无效过期）：擦凭据。
/// 不擦的话每次进页面都拿同一枚废凭据重试，界面永远停在「未连接」且没出路。
- (void)test_续期被鉴权类错误拒绝才擦凭据 {
    for (NSNumber *c in @[@200001, @200002, @200003, @100101, @100102]) {
        XCTAssertTrue(IMShouldDropRefreshCredential(YES, c.integerValue), @"%@ 应擦", c);
    }
}

/// 暂时性的失败（非鉴权业务码）不擦：因为一次抖动把用户踢下线是不能接受的。
- (void)test_非鉴权错误不擦凭据 {
    for (NSNumber *c in @[@0, @100001, @500, @(-1), @300203]) {
        XCTAssertFalse(IMShouldDropRefreshCredential(YES, c.integerValue), @"%@ 不该擦", c);
    }
}

/// 没在用续期凭据（走的是密码登录）：密码错了不能顺手擦掉一枚与此次失败无关的续期凭据。
- (void)test_密码登录失败不擦续期凭据 {
    XCTAssertFalse(IMShouldDropRefreshCredential(NO, 200002));
    XCTAssertFalse(IMShouldDropRefreshCredential(NO, 100102));
}

@end
