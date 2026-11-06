//  IMRtcConfigTests.m
//  im-rtc 接入配置的纯逻辑校验：缺项判定、格式校验。字段从四项（wsUrl/appId/keyId/debugSecret）
//  精简为只剩 wsUrl 时（换票改由 IMServer 代理）之前没有测试覆盖，这次补上。

#import <XCTest/XCTest.h>
#import "IMRtcConfig.h"

@interface IMRtcConfigTests : XCTestCase
@end

@implementation IMRtcConfigTests

#pragma mark - 本机信令地址（登录页长按 Logo 保存）

- (void)testNormalizedWSURLAcceptsWebSocketAddresses {
    XCTAssertEqualObjects([IMRtcConfig normalizedWSURL:@"ws://47.250.219.159:8787/v1/ws"], @"ws://47.250.219.159:8787/v1/ws");
    XCTAssertEqualObjects([IMRtcConfig normalizedWSURL:@"  wss://rtc.example.com/v1/ws\n"], @"wss://rtc.example.com/v1/ws");
}

- (void)testNormalizedWSURLRejectsInvalidAddresses {
    for (NSString *input in @[@"", @"   ", @"http://h:8787/v1/ws", @"h:8787/v1/ws", @"ws://", @"ws://a b/v1/ws", @"ws://h:port/v1/ws"]) {
        XCTAssertNil([IMRtcConfig normalizedWSURL:input], @"%@", input);
    }
    XCTAssertNil([IMRtcConfig normalizedWSURL:nil]);
}

- (void)testSavedOverrideWinsAndClearingRestoresDefault {
    NSString *defaultURL = IMRtcConfig.load.wsURL;
    [self addTeardownBlock:^{ [IMRtcConfig saveWSURLOverride:nil]; }];
    [IMRtcConfig saveWSURLOverride:@"ws://override.example.com:8787/v1/ws"];
    XCTAssertEqualObjects(IMRtcConfig.load.wsURL, @"ws://override.example.com:8787/v1/ws");
    [IMRtcConfig saveWSURLOverride:nil];
    XCTAssertEqualObjects(IMRtcConfig.load.wsURL, defaultURL);
}

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
