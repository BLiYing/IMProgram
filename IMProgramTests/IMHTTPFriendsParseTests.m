//  IMHTTPFriendsParseTests.m
//  GET /friends 的名单解析挪出主线程后，对调用方的契约不能变：completion 仍在主线程，
//  且回调那一刻备注名缓存与「谁是我的好友」快照已经灌好（资料页 init 同步读它们）。
//  用 NSURLProtocol 按本测试专用的 Bearer token 拦截请求，不连真后端。**不改全局 host**（除非它本来为空）：
//  app-hosted 进程里宿主 App 可能正在发真实请求，改掉 host 会把它们也导到假地址。app-hosted 测试。

#import <XCTest/XCTest.h>

#import "IMHTTPService.h"
#import "IMRemarkStore.h"
#import "IMFriendStateStore.h"
#import "IMUserCard.h"

static NSString *const kIMFriendsStubToken = @"im-friends-parse-stub-token";

/// 只接带本测试 token 的 /api/v1/friends，回一份固定名单；宿主 App 的真实请求（token 不同）一律不碰。
@interface IMFriendsListStubProtocol : NSURLProtocol
@end

@implementation IMFriendsListStubProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *auth = [request valueForHTTPHeaderField:@"Authorization"];
    return [auth isEqualToString:[@"Bearer " stringByAppendingString:kIMFriendsStubToken]]
        && [request.URL.path isEqualToString:@"/api/v1/friends"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

- (void)startLoading {
    NSDictionary *body = @{ @"code": @0, @"message": @"ok", @"data": @{ @"friends": @[
        @{ @"user_id": @"stub-u1", @"nickname": @"甲", @"remark": @"老甲", @"status": @"accepted" },
        @{ @"user_id": @"stub-u2", @"nickname": @"乙", @"status": @"pending" },
    ] } };
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{ @"Content-Type": @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

@interface IMHTTPFriendsParseTests : XCTestCase
@property (nonatomic, copy, nullable) NSString *savedHost;
@end

@implementation IMHTTPFriendsParseTests

- (void)setUp {
    [super setUp];
    [NSURLProtocol registerClass:IMFriendsListStubProtocol.class];
    // host 为空时建不出 URL（直接回「非法服务器地址」），才临时补一个；此时宿主 App 没登录、没有真实请求可干扰。
    self.savedHost = IMHTTPService.sharedService.host;
    if (self.savedHost.length == 0) { IMHTTPService.sharedService.host = @"127.0.0.1:59391"; }
    // 单例跨用例共享：用「权威空全集」清表，保证从零开始（同 IMRemarkStoreTests）。
    [IMRemarkStore.sharedStore ingestFriends:@[] authoritative:YES];
    [IMFriendStateStore.sharedStore ingestFriends:@[] authoritative:YES];
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:IMFriendsListStubProtocol.class];
    if (self.savedHost.length == 0) { IMHTTPService.sharedService.host = self.savedHost; }
    [IMRemarkStore.sharedStore ingestFriends:@[] authoritative:YES];
    [IMFriendStateStore.sharedStore ingestFriends:@[] authoritative:YES];
    [super tearDown];
}

- (void)testFriendsDeliveredOnMainWithStoresAlreadyFed {
    XCTestExpectation *done = [self expectationWithDescription:@"friends"];
    [IMHTTPService.sharedService friendsWithToken:kIMFriendsStubToken status:nil
                                       completion:^(NSArray<IMUserCard *> *friends, NSError *error) {
        XCTAssertTrue(NSThread.isMainThread, @"调用方都在回调里直接改 UI");
        XCTAssertNil(error);
        XCTAssertEqual(friends.count, 2);
        XCTAssertEqualObjects(friends.firstObject.userID, @"stub-u1");
        XCTAssertEqual(friends.lastObject.status, IMFriendStatusPending);
        XCTAssertEqualObjects([IMRemarkStore.sharedStore remarkForUser:@"stub-u1"], @"老甲",
                              @"回调时备注缓存就该灌好");
        XCTAssertEqualObjects([IMFriendStateStore.sharedStore friendStateForUser:@"stub-u1"], @YES,
                              @"回调时好友关系快照就该灌好");
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

@end
