//  IMAboutLinksTests.m
//  「关于我们」链接后台配置：响应解析、取值解析（绝对 / 相对 / 空 / 非法 scheme）、回退与客服行显隐。

#import <XCTest/XCTest.h>
#import "IMAboutLinks.h"
#import "IMAppInfo.h"
#import "IMAboutViewController.h"

@interface IMAboutLinksTests : XCTestCase
@end

@implementation IMAboutLinksTests

- (NSURL *)resolve:(NSString *)value {
    return [IMAboutLinks URLForConfigValue:value host:@"10.0.0.2:8081" scheme:@"http" language:@"en"];
}

- (void)testAbsoluteURLIsUsedVerbatimWithoutLang {
    NSURL *u = [self resolve:@"https://corp.example.com/privacy?x=1"];
    XCTAssertEqualObjects(u.absoluteString, @"https://corp.example.com/privacy?x=1", @"绝对地址原样，不追加 ?lang=");
    XCTAssertEqualObjects([self resolve:@"http://192.168.1.12:8091/?ck=ck_abc"].absoluteString, @"http://192.168.1.12:8091/?ck=ck_abc");
}

- (void)testServerRelativePathUsesHostAndLang {
    XCTAssertEqualObjects([self resolve:@"/legal/privacy"].absoluteString, @"http://10.0.0.2:8081/legal/privacy?lang=en");
    XCTAssertNil([self resolve:@"/api/v1/login"], @"相对路径仍受法务白名单约束");
}

- (void)testEmptyAndNonHTTPSchemesAreRejected {
    XCTAssertNil([self resolve:@""]);
    XCTAssertNil([self resolve:nil]);
    XCTAssertNil([self resolve:@"javascript:alert(1)"]);
    XCTAssertNil([self resolve:@"file:///etc/passwd"]);
    XCTAssertNil([self resolve:@"ftp://example.com/x"]);
    XCTAssertNil([self resolve:@"https:///nohost"]);
    XCTAssertNil([self resolve:@"example.com/x"]);
}

- (void)testFieldFallbackToBuiltinPathsWhenLinksMissing {
    NSURL *p = [IMAboutLinks URLForField:IMAboutLinkFieldPrivacy links:nil host:@"h:1" scheme:@"http" language:@"zh-Hans"];
    XCTAssertEqualObjects(p.absoluteString, @"http://h:1/legal/privacy?lang=zh-Hans");
    NSURL *t = [IMAboutLinks URLForField:IMAboutLinkFieldTerms links:@{IMAboutLinkFieldTerms: @"javascript:x"} host:@"h:1" scheme:@"http" language:@"en"];
    XCTAssertEqualObjects(t.absoluteString, @"http://h:1/legal/terms?lang=en", @"非法值也退回内置路径");
    NSURL *s = [IMAboutLinks URLForField:IMAboutLinkFieldSupport links:@{} host:@"h:1" scheme:@"https" language:@"en"];
    XCTAssertEqualObjects(s.absoluteString, @"https://h:1/support?lang=en");
    // 配了自定义则用自定义。
    NSURL *c = [IMAboutLinks URLForField:IMAboutLinkFieldPrivacy links:@{IMAboutLinkFieldPrivacy: @"https://a.example/p"} host:@"h:1" scheme:@"http" language:@"en"];
    XCTAssertEqualObjects(c.absoluteString, @"https://a.example/p");
}

- (void)testCustomerServiceHasNoFallback {
    XCTAssertNil([IMAboutLinks URLForField:IMAboutLinkFieldCustomerService links:nil host:@"h:1" scheme:@"http" language:@"en"]);
    XCTAssertNil([IMAboutLinks URLForField:IMAboutLinkFieldCustomerService links:@{IMAboutLinkFieldCustomerService: @""} host:@"h:1" scheme:@"http" language:@"en"], @"空串 = 后台关闭入口");
    NSURL *u = [IMAboutLinks URLForField:IMAboutLinkFieldCustomerService
                                   links:@{IMAboutLinkFieldCustomerService: @"http://192.168.1.12:8091/?ck=ck_abc"}
                                    host:@"h:1" scheme:@"http" language:@"en"];
    XCTAssertEqualObjects(u.absoluteString, @"http://192.168.1.12:8091/?ck=ck_abc");
}

- (void)testResponseParsing {
    NSData *ok = [@"{\"code\":0,\"message\":\"ok\",\"request_id\":\"r\",\"data\":{\"privacy_url\":\"/legal/privacy\",\"terms_url\":\"/legal/terms\",\"support_url\":\"/support\",\"customer_service_url\":\"\",\"extra\":1}}" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *d = [IMAboutLinks linksFromResponseData:ok];
    XCTAssertEqualObjects(d[IMAboutLinkFieldPrivacy], @"/legal/privacy");
    XCTAssertEqualObjects(d[IMAboutLinkFieldCustomerService], @"");
    XCTAssertNil(d[@"extra"]);
    XCTAssertNil([IMAboutLinks linksFromResponseData:[@"{\"code\":100001,\"data\":{}}" dataUsingEncoding:NSUTF8StringEncoding]]);
    XCTAssertNil([IMAboutLinks linksFromResponseData:[@"404 page not found" dataUsingEncoding:NSUTF8StringEncoding]], @"老服务端 404 → 回退");
    XCTAssertNil([IMAboutLinks linksFromResponseData:nil]);
    XCTAssertNil([IMAboutLinks linksFromResponseData:[@"{\"code\":null,\"data\":{}}" dataUsingEncoding:NSUTF8StringEncoding]], @"code=null 不能崩");
    XCTAssertEqualObjects([self resolve:@"  https://a.example/x \n"].absoluteString, @"https://a.example/x", @"首尾空白裁掉");
    NSDictionary *partial = [IMAboutLinks linksFromResponseData:[@"{\"code\":0,\"data\":{\"privacy_url\":5}}" dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertEqual(partial.count, 0u, @"非字符串值丢弃");
}

- (void)testAboutPageHasNoCustomerServiceRowWithoutLinks {
    IMAboutViewController *vc = [[IMAboutViewController alloc] initWithHost:@"nolinks.invalid:1"];
    [vc loadViewIfNeeded];
    UITableView *tv = nil;
    for (UIView *v in vc.view.subviews) { if ([v isKindOfClass:UITableView.class]) { tv = (UITableView *)v; } }
    XCTAssertEqual([tv numberOfRowsInSection:0], 4, @"没拉到链接时客服行隐藏：隐私/条款/支持/版本");
}

- (void)testBeaconUserAgentFormat {
    NSString *base = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15";
    NSString *ua = [IMAboutLinks beaconUserAgentWithBase:base version:@"0.1.0"];
    XCTAssertEqualObjects(ua, @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 BeaconApp/0.1.0 (iOS)");
    XCTAssertEqualObjects([IMAboutLinks beaconUserAgentWithBase:ua version:@"0.1.0"], ua, @"已带标记不重复追加");
}

- (void)testBeaconUserAgentEmptyVersionAndBase {
    XCTAssertEqualObjects([IMAboutLinks beaconUserAgentWithBase:@"UA" version:nil], @"UA BeaconApp/0.0.0 (iOS)");
    XCTAssertEqualObjects([IMAboutLinks beaconUserAgentWithBase:@"UA" version:@"  "], @"UA BeaconApp/0.0.0 (iOS)");
    XCTAssertEqualObjects([IMAboutLinks beaconUserAgentWithBase:nil version:@"1.2"], @"BeaconApp/1.2 (iOS)");
}

- (void)testNavigationDecision {
    IMAboutNavDecision (^d)(NSString *) = ^IMAboutNavDecision(NSString *s) { return [IMAboutLinks navigationDecisionForURL:[NSURL URLWithString:s]]; };
    XCTAssertEqual(d(@"https://a.example/x"), IMAboutNavDecisionAllow);
    XCTAssertEqual(d(@"HTTP://192.168.1.12:8091/?ck=1"), IMAboutNavDecisionAllow);
    XCTAssertEqual(d(@"about:blank"), IMAboutNavDecisionAllow);
    XCTAssertEqual(d(@"tel:10086"), IMAboutNavDecisionExternal);
    XCTAssertEqual(d(@"mailto:a@b.com"), IMAboutNavDecisionExternal);
    XCTAssertEqual(d(@"javascript:alert(1)"), IMAboutNavDecisionBlock);
    XCTAssertEqual(d(@"file:///etc/passwd"), IMAboutNavDecisionBlock);
    XCTAssertEqual(d(@"data:text/html,hi"), IMAboutNavDecisionBlock);
    XCTAssertEqual(d(@"about:srcdoc"), IMAboutNavDecisionBlock);
    XCTAssertEqual(d(@"https:///nohost"), IMAboutNavDecisionBlock);
    XCTAssertEqual([IMAboutLinks navigationDecisionForURL:nil], IMAboutNavDecisionBlock);
}

@end
