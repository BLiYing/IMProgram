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

@end
