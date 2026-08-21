//  IMHTTPLogFormatterTests.m

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMHTTPLogFormatter.h"

@interface IMHTTPLogFormatterTests : XCTestCase
@end

@implementation IMHTTPLogFormatterTests

- (void)testAlwaysRedactsCredentialsAndPhoneRecursively {
    NSDictionary *input = @{
        @"username": @"a1002",
        @"password": @"secret",
        @"data": @{
            @"access_token": @"jwt-value",
            @"client-secret": @"client-secret-value",
            @"phone": @"13812345678",
            @"content": @"hello",
        },
    };
    NSDictionary *safe = IMHTTPSanitizedJSONObject(input, YES);
    XCTAssertEqualObjects(safe[@"username"], @"a1002");
    XCTAssertEqualObjects(safe[@"password"], @"***");
    XCTAssertEqualObjects(safe[@"data"][@"access_token"], @"***");
    XCTAssertEqualObjects(safe[@"data"][@"client-secret"], @"***");
    XCTAssertEqualObjects(safe[@"data"][@"phone"], @"***");
    XCTAssertEqualObjects(safe[@"data"][@"content"], @"hello");
}

- (void)testReleaseModeRedactsBusinessContent {
    NSDictionary *input = @{
        @"content": @"private message",
        @"reason": @"private report",
        @"data": @[ @{ @"text": @"nested text", @"code": @0 } ],
    };
    NSDictionary *safe = IMHTTPSanitizedJSONObject(input, NO);
    XCTAssertEqualObjects(safe[@"content"], @"***");
    XCTAssertEqualObjects(safe[@"reason"], @"***");
    XCTAssertEqualObjects(safe[@"data"][0][@"text"], @"***");
    XCTAssertEqualObjects(safe[@"data"][0][@"code"], @0);
}

- (void)testMultipartBodyLogsMetadataOnly {
    NSData *data = [@"binary-secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *logged = IMHTTPLogBody(data, @"multipart/form-data; boundary=test", YES);
    XCTAssertEqualObjects(logged, @"<multipart 13 bytes>");
    XCTAssertFalse([logged containsString:@"binary-secret"]);
}

- (void)testJSONEmbeddedDataURIOnlyLogsMetadata {
    NSString *dataURI = @"data:image/jpeg;base64,/9j/secret-binary";
    NSDictionary *safe = IMHTTPSanitizedJSONObject(@{ @"avatar_url": dataURI }, YES);
    XCTAssertEqualObjects(safe[@"avatar_url"], @"<data-uri type=image/jpeg chars=40>");
    XCTAssertFalse([safe[@"avatar_url"] containsString:@"secret-binary"]);
}

- (void)testJSONBodyIsRedactedAndTruncated {
    NSString *large = [@"" stringByPaddingToLength:20000 withString:@"x" startingAtIndex:0];
    NSDictionary *body = @{ @"password": @"secret", @"content": large };
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    NSString *logged = IMHTTPLogBody(data, @"application/json", YES);
    XCTAssertFalse([logged containsString:@"secret"]);
    XCTAssertTrue([logged containsString:@"\"password\":\"***\""]);
    XCTAssertTrue([logged containsString:@"<truncated"]);
}

// 回归：超大字段值必须被**逐值**截断，不能把同层其它字段（尤其是密码脱敏证据）挤出日志。
// 旧实现只做整体 16 KB 截断，一旦 NSJSONSerialization 把超大 content 排在 password 之前，
// `"password":"***"` 会被整体截断吃掉——测试随 key 顺序时绿时红（iOS 26 上稳定失败）。
// 逐值截断后，无论 key 怎么排，每个字段都保留，只有过长的那个值被截短。
- (void)testOversizedValueIsTruncatedPerValueAndSiblingsSurvive {
    NSString *huge = [@"" stringByPaddingToLength:60000 withString:@"x" startingAtIndex:0];
    // 三个字段：脱敏的 password、超大的 content、末尾一个普通标记字段。
    NSDictionary *body = @{ @"password": @"secret", @"content": huge, @"marker": @"tail-field" };
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    NSString *logged = IMHTTPLogBody(data, @"application/json", YES);

    XCTAssertFalse([logged containsString:@"secret"], @"明文密码不得出现");
    XCTAssertTrue([logged containsString:@"\"password\":\"***\""], @"密码脱敏证据必须保留，不因超大兄弟字段被挤掉");
    XCTAssertTrue([logged containsString:@"tail-field"], @"排在超大字段之后的普通字段也必须保留");
    XCTAssertTrue([logged containsString:@"<truncated"], @"超大值本身被截断");
    // 整体长度受逐值上限约束：三字段各 ≤4 KB + 结构开销，远小于旧的 16 KB 整体上限。
    XCTAssertLessThan(logged.length, (NSUInteger)(8 * 1024), @"逐值截断后整体应显著短于 16 KB 整体上限");
}

- (void)testRequestIDsAreNonEmptyAndUnique {
    NSString *first = IMHTTPNewRequestID();
    NSString *second = IMHTTPNewRequestID();
    XCTAssertGreaterThan(first.length, 0U);
    XCTAssertNotEqualObjects(first, second);
}

- (void)testReleaseModeDoesNotLogPlainTextBody {
    NSData *data = [@"private upstream error" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *logged = IMHTTPLogBody(data, @"text/plain", NO);
    XCTAssertEqualObjects(logged, @"<non-json redacted 22 bytes>");
    XCTAssertFalse([logged containsString:@"private"]);
}

// 高频轮询摘要：只留 data 下数组条数与字节数，不含具体条目内容（dev 日志减量）。
- (void)testPollSummaryReportsCountNotBody {
    NSDictionary *body = @{ @"code": @0, @"data": @{ @"conversations": @[
        @{ @"conv_id": @"u_a_b", @"name": @"张三" }, @{ @"conv_id": @"g_x", @"name": @"群一" } ] } };
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    NSString *logged = IMHTTPPollResponseSummary(data);
    XCTAssertTrue([logged hasPrefix:@"<poll conversations=2 bytes="], @"应报会话条数=2，实际：%@", logged);
    XCTAssertFalse([logged containsString:@"张三"], @"摘要不得包含具体条目内容");
    XCTAssertFalse([logged containsString:@"conv_id"], @"摘要不得展开 body");
}

// messages/hidden 的键是 items；空数组也应给出 items=0 摘要。
- (void)testPollSummaryHandlesItemsKeyAndEmpty {
    NSDictionary *body = @{ @"code": @0, @"data": @{ @"items": @[] } };
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    XCTAssertTrue([IMHTTPPollResponseSummary(data) hasPrefix:@"<poll items=0 bytes="]);
    XCTAssertEqualObjects(IMHTTPPollResponseSummary([NSData data]), @"<empty>");
}

@end
