//  IMRtcConfigTests.m
//  im-rtc 接入配置的纯逻辑校验：缺项判定、格式校验。字段从四项（wsUrl/appId/keyId/debugSecret）
//  精简为只剩 wsUrl 时（换票改由 IMServer 代理）之前没有测试覆盖，这次补上。

#import <XCTest/XCTest.h>
#import "IMRtcConfig.h"

@interface IMRtcConfigTests : XCTestCase
@end

@implementation IMRtcConfigTests

#pragma mark - 缺项判定

- (void)testUsableWhenWsUrlPresent {
    IMRtcConfig *config = [[IMRtcConfig alloc] initWithDictionary:@{ @"wsUrl": @"ws://h:8787/v1/ws" }];
    XCTAssertTrue(config.isUsable);
    XCTAssertEqual(config.missingKeys.count, 0);
    XCTAssertEqualObjects(config.wsURL, @"ws://h:8787/v1/ws");
}

- (void)testMissingWsUrl {
    IMRtcConfig *config = [[IMRtcConfig alloc] initWithDictionary:@{}];
    XCTAssertFalse(config.isUsable);
    XCTAssertEqualObjects(config.missingKeys, @[@"wsUrl"]);
}

- (void)testNilDictionaryTreatedAsEmpty {
    IMRtcConfig *config = [[IMRtcConfig alloc] initWithDictionary:nil];
    XCTAssertFalse(config.isUsable);
}

- (void)testWsUrlTrimmed {
    IMRtcConfig *config = [[IMRtcConfig alloc] initWithDictionary:@{ @"wsUrl": @"  ws://h:8787/v1/ws  " }];
    XCTAssertEqualObjects(config.wsURL, @"ws://h:8787/v1/ws");
}

- (void)testWsUrlNonStringTreatedAsEmpty {
    IMRtcConfig *config = [[IMRtcConfig alloc] initWithDictionary:@{ @"wsUrl": @123 }];
    XCTAssertFalse(config.isUsable);
    XCTAssertEqualObjects(config.wsURL, @"");
}

#pragma mark - problemForID:kind:

- (void)testProblemForIDEmpty {
    XCTAssertEqualObjects([IMRtcConfig problemForID:@"" kind:@"uid"], @"uid 为空");
    XCTAssertEqualObjects([IMRtcConfig problemForID:nil kind:@"uid"], @"uid 为空");
}

- (void)testProblemForIDWhitespace {
    XCTAssertNotNil([IMRtcConfig problemForID:@"a b" kind:@"uid"]);
}

- (void)testProblemForIDTooLong {
    NSString *long65 = [@"" stringByPaddingToLength:65 withString:@"a" startingAtIndex:0];
    XCTAssertNotNil([IMRtcConfig problemForID:long65 kind:@"uid"]);
}

- (void)testProblemForIDValid {
    XCTAssertNil([IMRtcConfig problemForID:@"user-1001" kind:@"uid"]);
}

@end
