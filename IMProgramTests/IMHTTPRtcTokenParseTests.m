//  IMHTTPRtcTokenParseTests.m
//  POST /api/v1/rtc/token 的请求/响应解析：带上 Bearer、成功拿到 data.token，
//  以及 IMServer 侧 600001（未配置）这类业务错误码原样透传给调用方。
//  用 NSURLProtocol 按本测试专用的 Bearer token 拦截请求，不连真后端（同 IMHTTPFriendsParseTests
//  的 app-hosted 套路：**不改全局 host**，除非它本来为空，避免干扰宿主 App 可能正在发的真实请求）。

#import <XCTest/XCTest.h>

#import "IMHTTPService.h"
#import "IMHTTPService+RTC.h"

static NSString *const kIMRtcTokenStubToken = @"im-rtc-token-parse-stub-token";
static NSString *const kIMRtcTokenUnconfiguredStubToken = @"im-rtc-token-unconfigured-stub-token";

/// 正常换票：回一枚固定的接入票。
@interface IMRtcTokenStubProtocol : NSURLProtocol
@end

@implementation IMRtcTokenStubProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *auth = [request valueForHTTPHeaderField:@"Authorization"];
    return [auth isEqualToString:[@"Bearer " stringByAppendingString:kIMRtcTokenStubToken]]
        && [request.URL.path isEqualToString:@"/api/v1/rtc/token"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

- (void)startLoading {
    NSDictionary *body = @{ @"code": @0, @"message": @"ok",
                             @"data": @{ @"token": @"rtc-jwt", @"expires_at_ms": @1, @"expires_in_sec": @43200 } };
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

/// IMServer 未配置 im-rtc：600001，业务码原样透传，不当成普通网络失败。
@interface IMRtcTokenUnconfiguredStubProtocol : NSURLProtocol
@end

@implementation IMRtcTokenUnconfiguredStubProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *auth = [request valueForHTTPHeaderField:@"Authorization"];
    return [auth isEqualToString:[@"Bearer " stringByAppendingString:kIMRtcTokenUnconfiguredStubToken]]
        && [request.URL.path isEqualToString:@"/api/v1/rtc/token"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

- (void)startLoading {
    NSDictionary *body = @{ @"code": @600001, @"message": @"rtc not configured" };
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:400
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{ @"Content-Type": @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

@interface IMHTTPRtcTokenParseTests : XCTestCase
@property (nonatomic, copy, nullable) NSString *savedHost;
@end

@implementation IMHTTPRtcTokenParseTests

- (void)setUp {
    [super setUp];
    [NSURLProtocol registerClass:IMRtcTokenStubProtocol.class];
    [NSURLProtocol registerClass:IMRtcTokenUnconfiguredStubProtocol.class];
    self.savedHost = IMHTTPService.sharedService.host;
    if (self.savedHost.length == 0) { IMHTTPService.sharedService.host = @"127.0.0.1:59392"; }
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:IMRtcTokenStubProtocol.class];
    [NSURLProtocol unregisterClass:IMRtcTokenUnconfiguredStubProtocol.class];
    if (self.savedHost.length == 0) { IMHTTPService.sharedService.host = self.savedHost; }
    [super tearDown];
}

- (void)testRtcTokenParsesSuccessResponse {
    XCTestExpectation *done = [self expectationWithDescription:@"rtc-token"];
    [IMHTTPService.sharedService rtcTokenWithToken:kIMRtcTokenStubToken completion:^(NSDictionary *data, NSError *error) {
        XCTAssertTrue(NSThread.isMainThread, @"调用方都在回调里直接改状态");
        XCTAssertNil(error);
        XCTAssertEqualObjects(data[@"token"], @"rtc-jwt");
        XCTAssertEqualObjects(data[@"expires_in_sec"], @43200);
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testRtcTokenSurfacesBusinessErrorCode {
    XCTestExpectation *done = [self expectationWithDescription:@"rtc-token-600001"];
    [IMHTTPService.sharedService rtcTokenWithToken:kIMRtcTokenUnconfiguredStubToken completion:^(NSDictionary *data, NSError *error) {
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, 600001);
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

@end
