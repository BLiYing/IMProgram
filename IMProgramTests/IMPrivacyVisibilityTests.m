//  IMPrivacyVisibilityTests.m
//  隐私「谁能看到」（PRIVACY_VISIBILITY_DESIGN §2/§4）：档位解析、PUT 只带被改项、失败回滚、
//  以及「服务端给空串 / 缺席就清掉旧头像 / 旧在线态」的端上缓存路径。
//  HTTP 用 NSURLProtocol 只拦 /users/me/privacy 与本测试专用对端的 /users/{id}。

#import <XCTest/XCTest.h>

#import "IMChatDetailViewController.h"
#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMHTTPService.h"
#import "IMHTTPService+AutoDelete.h"
#import "IMPrivacyVisibility.h"
#import "IMPrivacyVisibilityViewController.h"
#import "IMUserCard.h"
#import "IMUserProfileCache.h"
#import "IMPresence.h"

/// 详情页私有属性 / 方法（+Private.h 引了 Swift 桥接头，测试 target 取不到，这里只声明用到的）。
@interface IMChatDetailViewController (IMPVTesting)
@property (nonatomic, copy, nullable) NSString *peerAvatarURL;
@property (nonatomic, strong, nullable) IMPresence *peerPresence;
@property (nonatomic, assign) BOOL peerProfileLoaded;
- (void)loadPeerProfile;
@end

static NSString *const kPVPeer = @"pv-test-peer-9917";

@interface IMPVStub : NSURLProtocol
@end
@implementation IMPVStub
static NSMutableArray<NSDictionary *> *sPVReqs; ///< {method, body}
static NSDictionary *sPVPrivacyReply, *sPVProfileReply;
+ (NSMutableArray *)reqs { if (!sPVReqs) { sPVReqs = [NSMutableArray array]; } return sPVReqs; }
+ (void)reset:(NSDictionary *)privacy profile:(NSDictionary *)profile {
    @synchronized (self) { [self.reqs removeAllObjects]; sPVPrivacyReply = privacy; sPVProfileReply = profile; }
}
+ (BOOL)canInitWithRequest:(NSURLRequest *)r {
    NSString *p = r.URL.path;
    return [p isEqualToString:@"/api/v1/users/me/privacy"] || [p hasSuffix:[@"/api/v1/users/" stringByAppendingString:kPVPeer]];
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
    id o = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    NSDictionary *reply;
    @synchronized (IMPVStub.class) {
        [IMPVStub.reqs addObject:@{ @"method": self.request.HTTPMethod ?: @"", @"body": [o isKindOfClass:NSDictionary.class] ? o : @{} }];
        reply = [self.request.URL.path hasSuffix:kPVPeer] ? sPVProfileReply : sPVPrivacyReply;
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

@interface IMPrivacyVisibilityTests : XCTestCase
@end

@implementation IMPrivacyVisibilityTests {
    NSString *_oldHost;
    NSString *_oldToken;
}

- (void)setUp {
    [super setUp];
    IMHTTPService *svc = IMHTTPService.sharedService;
    _oldHost = svc.host; _oldToken = svc.currentToken;
    if (svc.host.length == 0) { svc.host = @"127.0.0.1:59391"; }
    [svc setValue:@"pv-token" forKey:@"currentToken"];
    [IMPVStub reset:nil profile:nil];
    [NSURLProtocol registerClass:IMPVStub.class];
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:IMPVStub.class];
    IMHTTPService.sharedService.host = _oldHost;
    [IMHTTPService.sharedService setValue:_oldToken forKey:@"currentToken"];
    [super tearDown];
}

- (NSArray<NSDictionary *> *)requests { @synchronized (IMPVStub.class) { return [IMPVStub.reqs copy]; } }

- (void)spinUntil:(BOOL (^)(void))cond {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!cond() && end.timeIntervalSinceNow > 0) { [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]]; }
}

#pragma mark - 档位解析

- (void)test_解析_三值原样_其余落默认 {
    XCTAssertEqualObjects(IMPrivacyVisibilityParse(IMPrivacyVisibilityKindLastSeen, @"nobody"), @"nobody");
    XCTAssertEqualObjects(IMPrivacyVisibilityParse(IMPrivacyVisibilityKindAvatar, @"contacts"), @"contacts");
    // 默认：上次上线=contacts，头像=everyone
    XCTAssertEqualObjects(IMPrivacyVisibilityParse(IMPrivacyVisibilityKindLastSeen, nil), @"contacts");
    XCTAssertEqualObjects(IMPrivacyVisibilityParse(IMPrivacyVisibilityKindLastSeen, @""), @"contacts");
    XCTAssertEqualObjects(IMPrivacyVisibilityParse(IMPrivacyVisibilityKindAvatar, @"friends"), @"everyone");
    XCTAssertEqualObjects(IMPrivacyVisibilityParse(IMPrivacyVisibilityKindAvatar, @7), @"everyone");
}

- (void)test_设置对象_缺字段走默认_自动删除档位照读 {
    IMPrivacySettings *s = [IMPrivacySettings settingsFromJSON:@{ @"auto_delete_default_sec": @86400, @"avatar_visibility": @"nobody" }];
    XCTAssertEqual(s.autoDeleteDefaultSec, 86400);
    XCTAssertEqualObjects(s.lastSeenVisibility, @"contacts");
    XCTAssertEqualObjects(s.avatarVisibility, @"nobody");
    XCTAssertEqualObjects([IMPrivacySettings settingsFromJSON:nil].avatarVisibility, @"everyone");
}

#pragma mark - PUT 只带被改项

- (void)test_PUT_只带被改的那一项 {
    XCTAssertEqualObjects(IMPrivacyVisibilityPutBody(IMPrivacyVisibilityKindLastSeen, @"nobody"), @{ @"last_seen_visibility": @"nobody" });
    XCTAssertEqualObjects(IMPrivacyVisibilityPutBody(IMPrivacyVisibilityKindAvatar, @"contacts"), @{ @"avatar_visibility": @"contacts" });

    XCTestExpectation *e = [self expectationWithDescription:@"put"];
    [IMHTTPService.sharedService saveVisibility:@"nobody" forKind:IMPrivacyVisibilityKindLastSeen token:@"t"
                                     completion:^(NSError *err) { XCTAssertNil(err); [e fulfill]; }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
    NSDictionary *req = self.requests.lastObject;
    XCTAssertEqualObjects(req[@"method"], @"PUT");
    XCTAssertEqualObjects(req[@"body"], @{ @"last_seen_visibility": @"nobody" }); // 不含 auto_delete_default_sec / avatar_visibility
}

- (void)test_GET_解出完整对象 {
    [IMPVStub reset:@{ @"code": @0, @"data": @{ @"auto_delete_default_sec": @0, @"last_seen_visibility": @"everyone", @"avatar_visibility": @"contacts" } } profile:nil];
    XCTestExpectation *e = [self expectationWithDescription:@"get"];
    [IMHTTPService.sharedService fetchPrivacySettingsWithToken:@"t" completion:^(IMPrivacySettings *s, NSError *err) {
        XCTAssertNil(err);
        XCTAssertEqualObjects(s.lastSeenVisibility, @"everyone");
        XCTAssertEqualObjects(s.avatarVisibility, @"contacts");
        [e fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

#pragma mark - 选择页：成功回调 / 失败回滚

- (void)test_选择页_成功_回调新档位且只发一次PUT {
    __block NSString *saved = nil;
    IMPrivacyVisibilityViewController *vc = [[IMPrivacyVisibilityViewController alloc]
        initWithKind:IMPrivacyVisibilityKindAvatar currentLevel:@"everyone" onSaved:^(NSString *l) { saved = l; }];
    [vc loadViewIfNeeded];
    [vc chooseLevel:@"contacts"];
    XCTAssertEqualObjects(vc.currentLevel, @"contacts"); // 乐观 ✓
    [self spinUntil:^BOOL{ return saved != nil; }];
    XCTAssertEqualObjects(saved, @"contacts");
    XCTAssertEqual(self.requests.count, 1u);
    XCTAssertEqualObjects(self.requests.firstObject[@"body"], @{ @"avatar_visibility": @"contacts" });
}

- (void)test_选择页_失败_勾选回滚且不回调 {
    [IMPVStub reset:@{ @"code": @100001, @"message": @"bad" } profile:nil];
    __block BOOL called = NO;
    IMPrivacyVisibilityViewController *vc = [[IMPrivacyVisibilityViewController alloc]
        initWithKind:IMPrivacyVisibilityKindLastSeen currentLevel:@"contacts" onSaved:^(NSString *l) { called = YES; }];
    [vc loadViewIfNeeded];
    [vc chooseLevel:@"nobody"];
    [self spinUntil:^BOOL{ return self.requests.count >= 1 && [vc.currentLevel isEqualToString:@"contacts"]; }];
    XCTAssertEqualObjects(vc.currentLevel, @"contacts");
    XCTAssertFalse(called);
}

- (void)test_选择页_保存在途页面已释放_仍回调上一页 {
    __block NSString *saved = nil;
    @autoreleasepool {
        IMPrivacyVisibilityViewController *vc = [[IMPrivacyVisibilityViewController alloc]
            initWithKind:IMPrivacyVisibilityKindLastSeen currentLevel:@"contacts" onSaved:^(NSString *l) { saved = l; }];
        [vc loadViewIfNeeded];
        [vc chooseLevel:@"nobody"];
    } // 模拟用户点返回：页面被释放，请求仍在途
    [self spinUntil:^BOOL{ return saved != nil; }];
    XCTAssertEqualObjects(saved, @"nobody");
}

- (void)test_选择页_选当前档_不发请求 {
    IMPrivacyVisibilityViewController *vc = [[IMPrivacyVisibilityViewController alloc]
        initWithKind:IMPrivacyVisibilityKindLastSeen currentLevel:@"contacts" onSaved:nil];
    [vc loadViewIfNeeded];
    [vc chooseLevel:@"contacts"];
    XCTAssertEqual(self.requests.count, 0u);
}

#pragma mark - 空头像 / 空在线态清缓存

- (void)test_会话解析_peer_avatar_url空串与peer_presence缺席_覆盖旧值 {
    IMConversation *c = [IMConversation conversationsFromArray:@[@{
        @"conv_id": @"pv_c1", @"is_group": @NO, @"peer": kPVPeer, @"peer_avatar_url": @"" }]].firstObject;
    XCTAssertEqualObjects(c.peerAvatarURL, @"");
    XCTAssertNil(c.peerPresence); // 不可见时服务端省略 peer_presence → nil，列表不画绿点
}

- (void)test_会话缓存_空头像覆盖库里旧头像 {
    IMDatabase *db = IMDatabase.sharedDatabase;
    IMConversation *old = [IMConversation conversationsFromArray:@[@{
        @"conv_id": @"pv_c2", @"is_group": @NO, @"peer": kPVPeer, @"peer_avatar_url": @"/avatars/old" }]].firstObject;
    [db replaceCachedConversations:@[old]];
    IMConversation *fresh = [IMConversation conversationsFromArray:@[@{
        @"conv_id": @"pv_c2", @"is_group": @NO, @"peer": kPVPeer, @"peer_avatar_url": @"" }]].firstObject;
    [db replaceCachedConversations:@[fresh]];
    IMConversation *got = nil;
    for (IMConversation *c in db.cachedConversations) { if ([c.convID isEqualToString:@"pv_c2"]) { got = c; } }
    XCTAssertNotNil(got);
    XCTAssertEqual(got.peerAvatarURL.length, 0u);
    [db replaceCachedConversations:@[]];
}

- (void)test_身份缓存_空头像覆盖旧头像 {
    IMUserCard *a = [IMUserCard new]; a.userID = kPVPeer; a.avatarURL = @"/avatars/old"; a.nickname = @"N";
    [IMUserProfileCache.sharedCache ingestCards:@[a]];
    IMUserCard *b = [IMUserCard new]; b.userID = kPVPeer; b.avatarURL = @""; b.nickname = @"N";
    [IMUserProfileCache.sharedCache ingestCards:@[b]];
    XCTAssertEqual([IMUserProfileCache.sharedCache peekCardForUserID:kPVPeer].avatarURL.length, 0u);
}

- (void)test_单聊详情_权威资料空头像_清掉页内旧头像 {
    [IMPVStub reset:nil profile:@{ @"code": @0, @"data": @{ @"user_id": kPVPeer, @"nickname": @"Peer", @"avatar_url": @"" } }];
    IMChatDetailViewController *vc = [[IMChatDetailViewController alloc] initSingleWithHost:@"127.0.0.1:59391" userID:@"pv-me"
        peerID:kPVPeer peerNickname:@"Peer" peerAvatarURL:@"/avatars/old"];
    [vc loadViewIfNeeded];
    [vc loadPeerProfile];
    [self spinUntil:^BOOL{ return vc.peerProfileLoaded; }];
    XCTAssertTrue(vc.peerProfileLoaded);
    XCTAssertEqual(vc.peerAvatarURL.length, 0u);
}

- (void)test_单聊详情_权威资料在线态缺席_清掉旧副标题 {
    [IMPVStub reset:nil profile:@{ @"code": @0, @"data": @{ @"user_id": kPVPeer, @"nickname": @"Peer" } }]; // 无 presence 键
    IMChatDetailViewController *vc = [[IMChatDetailViewController alloc] initSingleWithHost:@"127.0.0.1:59391" userID:@"pv-me"
        peerID:kPVPeer peerNickname:@"Peer" peerAvatarURL:nil];
    IMPresence *old = [IMPresence presenceFromProfileDictionary:@{ @"presence": @"recently" }];
    vc.peerPresence = old;
    [vc loadViewIfNeeded];
    [vc loadPeerProfile];
    [self spinUntil:^BOOL{ return vc.peerProfileLoaded; }];
    XCTAssertEqualObjects(vc.peerPresence.subtitleText ?: @"", @"");
}

@end
