#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMServerEndpoint.h"
#import "../IMProgram/Common/IMMediaUtil.h"

// 服务器地址协议收口（IMServerEndpoint）+ 媒体绝对 URL 的自家主机白名单（IMMediaFullURL）。
// scheme 是进程内单例状态，每条用例跑完必须还原成默认 http，否则串味到别的测试类。
@interface IMServerEndpointTests : XCTestCase
@end

@implementation IMServerEndpointTests

- (void)tearDown {
    IMServerEndpoint.shared.scheme = IMServerSchemeHTTP;
    [super tearDown];
}

#pragma mark - 输入解析

- (void)testParseBareHostDefaultsToHTTP {
    NSString *scheme = nil, *host = nil;
    XCTAssertTrue([IMServerEndpoint parseInput:@"192.168.1.12:8080" scheme:&scheme host:&host]);
    XCTAssertEqualObjects(scheme, IMServerSchemeHTTP); // 无协议前缀保持改造前的默认
    XCTAssertEqualObjects(host, @"192.168.1.12:8080");
}

- (void)testParseExplicitSchemes {
    NSString *scheme = nil, *host = nil;
    XCTAssertTrue([IMServerEndpoint parseInput:@"https://im.example.com" scheme:&scheme host:&host]);
    XCTAssertEqualObjects(scheme, IMServerSchemeHTTPS);
    XCTAssertEqualObjects(host, @"im.example.com");

    XCTAssertTrue([IMServerEndpoint parseInput:@"HTTP://IM.Example.com:8080/" scheme:&scheme host:&host]);
    XCTAssertEqualObjects(scheme, IMServerSchemeHTTP);   // 协议大小写不敏感
    XCTAssertEqualObjects(host, @"im.example.com:8080"); // 尾斜杠去掉、主机名归一化小写
}

- (void)testParseRejectsGarbage {
    NSString *scheme = nil, *host = nil;
    XCTAssertFalse([IMServerEndpoint parseInput:nil scheme:&scheme host:&host]);
    XCTAssertFalse([IMServerEndpoint parseInput:@"   " scheme:&scheme host:&host]);
    XCTAssertFalse([IMServerEndpoint parseInput:@"https://" scheme:&scheme host:&host]);
    XCTAssertFalse([IMServerEndpoint parseInput:@"ws://im.example.com" scheme:&scheme host:&host]);
    XCTAssertFalse([IMServerEndpoint parseInput:@"im.example.com/api" scheme:&scheme host:&host]); // 不支持路径前缀
    // userinfo：`http://real.server@evil.example` 肉眼像连自家、实际连 evil
    XCTAssertFalse([IMServerEndpoint parseInput:@"http://im.example.com@evil.example" scheme:&scheme host:&host]);
    XCTAssertFalse([IMServerEndpoint parseInput:@"im.example .com" scheme:&scheme host:&host]);
}

- (void)testParseDoesNotWriteOutParamsOnFailure {
    NSString *scheme = @"哨兵", *host = @"哨兵";
    XCTAssertFalse([IMServerEndpoint parseInput:@"" scheme:&scheme host:&host]);
    XCTAssertEqualObjects(scheme, @"哨兵");
    XCTAssertEqualObjects(host, @"哨兵");
}

#pragma mark - URL 拼装

- (void)testHTTPAndWebSocketURLsFollowScheme {
    IMServerEndpoint *ep = IMServerEndpoint.shared;
    ep.scheme = IMServerSchemeHTTP;
    XCTAssertEqualObjects([ep httpURLForHost:@"h:8080" path:@"/api/v1/login"].absoluteString,
                          @"http://h:8080/api/v1/login");
    XCTAssertEqualObjects([ep webSocketURLForHost:@"h:8080" path:@"/ws" query:@"token=abc"].absoluteString,
                          @"ws://h:8080/ws?token=abc");

    ep.scheme = IMServerSchemeHTTPS;
    XCTAssertTrue(ep.isSecure);
    XCTAssertEqualObjects([ep httpURLForHost:@"h:8443" path:@"/api/v1/login"].absoluteString,
                          @"https://h:8443/api/v1/login");
    // TLS 必须两条通道一致：https 时长连接不能还留在明文 ws
    XCTAssertEqualObjects([ep webSocketURLForHost:@"h:8443" path:@"/ws" query:@"token=abc"].absoluteString,
                          @"wss://h:8443/ws?token=abc");
    XCTAssertEqualObjects([ep webSocketURLForHost:@"h:8443" path:@"/ws" query:nil].absoluteString,
                          @"wss://h:8443/ws");
}

- (void)testIllegalSchemeIsIgnored {
    IMServerEndpoint *ep = IMServerEndpoint.shared;
    ep.scheme = IMServerSchemeHTTPS;
    ep.scheme = @"ftp";  // 非法值保持原值，不拼出 ftp://
    XCTAssertEqualObjects(ep.scheme, IMServerSchemeHTTPS);
}

- (void)testEmptyHostYieldsNilURL {
    XCTAssertNil([IMServerEndpoint.shared httpURLForHost:@"" path:@"/x"]);
    XCTAssertNil([IMServerEndpoint.shared webSocketURLForHost:nil path:@"/ws" query:nil]);
}

#pragma mark - 自家主机判定

- (void)testIsOwnHost {
    IMServerEndpoint *ep = IMServerEndpoint.shared;
    XCTAssertTrue([ep isOwnHost:@"im.example.com:8080" forAbsoluteURL:@"http://im.example.com:8080/uploads/a.jpg"]);
    XCTAssertTrue([ep isOwnHost:@"im.example.com:8080" forAbsoluteURL:@"https://IM.example.COM:8080/uploads/a.jpg"]);
    XCTAssertTrue([ep isOwnHost:@"im.example.com" forAbsoluteURL:@"http://im.example.com/a.jpg"]);

    XCTAssertFalse([ep isOwnHost:@"im.example.com:8080" forAbsoluteURL:@"http://attacker.example/a.jpg"]);
    XCTAssertFalse([ep isOwnHost:@"im.example.com:8080" forAbsoluteURL:@"http://im.example.com:9090/a.jpg"]);
    XCTAssertFalse([ep isOwnHost:@"im.example.com:8080" forAbsoluteURL:@"http://im.example.com/a.jpg"]); // 端口从严
    // 子域不算自家：`im.example.com.attacker.example` 前缀相同但不是同一台机器
    XCTAssertFalse([ep isOwnHost:@"im.example.com" forAbsoluteURL:@"http://im.example.com.attacker.example/a.jpg"]);
    XCTAssertFalse([ep isOwnHost:@"im.example.com" forAbsoluteURL:@"file:///etc/passwd"]);
    XCTAssertFalse([ep isOwnHost:@"" forAbsoluteURL:@"http://im.example.com/a.jpg"]);
    XCTAssertFalse([ep isOwnHost:@"im.example.com" forAbsoluteURL:nil]);
}

#pragma mark - 媒体 URL 白名单（漏洞：发送方可控 URL 被零点击自动拉取）

- (void)testRelativeMediaURLFollowsScheme {
    IMServerEndpoint.shared.scheme = IMServerSchemeHTTP;
    XCTAssertEqualObjects(IMMediaFullURL(@"/uploads/a.jpg", @"h:8080"), @"http://h:8080/uploads/a.jpg");
    IMServerEndpoint.shared.scheme = IMServerSchemeHTTPS;
    XCTAssertEqualObjects(IMMediaFullURL(@"/uploads/a.jpg", @"h:8443"), @"https://h:8443/uploads/a.jpg");
}

- (void)testForeignAbsoluteMediaURLIsRejected {
    // 对方把 content/avatar_url 设成自己的服务器 → 渲染那一行就零点击发 GET，泄露 IP 与"已查看"时刻。
    XCTAssertEqualObjects(IMMediaFullURL(@"http://attacker.example/beacon.png", @"h:8080"), @"");
    XCTAssertEqualObjects(IMMediaFullURL(@"https://attacker.example/beacon.png", @"h:8080"), @"");
    XCTAssertEqualObjects(IMMediaFullURL(@"http://h:9090/beacon.png", @"h:8080"), @"");
}

- (void)testOwnAbsoluteMediaURLIsNormalizedToCurrentScheme {
    IMServerEndpoint.shared.scheme = IMServerSchemeHTTPS;
    // 存量数据里的 http:// 绝对地址：是自家的就放行，但按当前协议重拼，免得 https 页面里混进明文请求
    XCTAssertEqualObjects(IMMediaFullURL(@"http://h:8443/uploads/a.jpg?v=2", @"h:8443"),
                          @"https://h:8443/uploads/a.jpg?v=2");
}

- (void)testDataURLAndEmptyPassThrough {
    XCTAssertEqualObjects(IMMediaFullURL(@"data:image/jpeg;base64,ZZ", @"h:8080"), @"data:image/jpeg;base64,ZZ");
    XCTAssertEqualObjects(IMMediaFullURL(@"", @"h:8080"), @"");
    XCTAssertEqualObjects(IMMediaFullURL(nil, @"h:8080"), @"");
}

- (void)testLinkPreviewImageKeepsExternalHosts {
    // 链接预览 OG 图是唯一合法的外站场景，显式豁免（其余一律走 IMMediaFullURL 拒收）
    XCTAssertEqualObjects(IMLinkPreviewImageURL(@"https://cdn.news.example/og.png", @"h:8080"),
                          @"https://cdn.news.example/og.png");
    IMServerEndpoint.shared.scheme = IMServerSchemeHTTP;
    XCTAssertEqualObjects(IMLinkPreviewImageURL(@"/avatars/a.jpg", @"h:8080"), @"http://h:8080/avatars/a.jpg");
    XCTAssertEqualObjects(IMLinkPreviewImageURL(@"", @"h:8080"), @"");
}

@end
