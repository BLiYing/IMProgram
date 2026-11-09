//  IMLoginRiskControlTests.m
//  安全风控 S4 端上：登录锁定 200006 的「N 分钟」文案、注册暂停 200007 映射、public-config 解析与旧响应丢弃。

#import <XCTest/XCTest.h>
#import "IMHTTPService.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"
#import "IMPublicConfig.h"

@interface IMLoginRiskControlTests : XCTestCase
@end

@implementation IMLoginRiskControlTests

#pragma mark - 200006 LoginLocked

- (void)testLockMinutesIsCeilWithMinimumOne {
    XCTAssertEqual(IMLoginLockMinutes(0), 1);
    XCTAssertEqual(IMLoginLockMinutes(-30), 1);
    XCTAssertEqual(IMLoginLockMinutes(1), 1);
    XCTAssertEqual(IMLoginLockMinutes(60), 1);
    XCTAssertEqual(IMLoginLockMinutes(61), 2);
    XCTAssertEqual(IMLoginLockMinutes(900), 15);
    XCTAssertEqual(IMLoginLockMinutes(901), 16);
}

- (void)testLockedMessageReadsRetryAfterFromData {
    NSDictionary *body = @{ @"code": @200006, @"message": @"too many", @"data": @{ @"retry_after_sec": @841 } };
    NSString *expected = IMLocalizedFormat(@"err.200006", @"15");
    XCTAssertEqualObjects(IMLoginLockedMessage(body), expected);
    XCTAssertTrue([expected containsString:@"15"], @"格式串参数必须落进文案");
    // 小数秒先向上取整（与 Web Math.ceil(sec/60) 同口径），不截断成少 1 分钟。
    NSDictionary *fractional = @{ @"code": @200006, @"data": @{ @"retry_after_sec": @60.5 } };
    XCTAssertEqualObjects(IMLoginLockedMessage(fractional), IMLocalizedFormat(@"err.200006", @"2"));
}

- (void)testLockedMessageMinutesBoundaries {
    NSDictionary *(^b)(id) = ^NSDictionary *(id sec) { return @{ @"code": @200006, @"data": @{ @"retry_after_sec": sec } }; };
    XCTAssertEqualObjects(IMLoginLockedMessage(b(@0)), IMLocalizedFormat(@"err.200006", @"1"), @"0 秒 → 1 分钟");
    XCTAssertEqualObjects(IMLoginLockedMessage(b(@60.5)), IMLocalizedFormat(@"err.200006", @"2"));
    XCTAssertEqualObjects(IMLoginLockedMessage(b(@119)), IMLocalizedFormat(@"err.200006", @"2"));
    XCTAssertEqualObjects(IMLoginLockedMessage(b(@(1e12))), IMLocalizedFormat(@"err.200006", @"525600"), @"一年上限");
}

- (void)testLockedMessageFallsBackToGenericRateLimitWithoutUsableData {
    NSString *generic = IMLocalized(@"err.100002");
    XCTAssertNotEqualObjects(generic, @"err.100002", @"Localizable.strings 必须含该键");
    XCTAssertEqualObjects(IMLoginLockedMessage(nil), generic);
    XCTAssertEqualObjects(IMLoginLockedMessage(@{ @"code": @200006 }), generic);
    XCTAssertEqualObjects(IMLoginLockedMessage(@{ @"code": @200006, @"data": [NSNull null] }), generic);
    XCTAssertEqualObjects(IMLoginLockedMessage(@{ @"code": @200006, @"data": @{} }), generic);
    XCTAssertEqualObjects(IMLoginLockedMessage(@{ @"code": @200006, @"data": @{ @"retry_after_sec": @"60" } }), generic);
    XCTAssertEqualObjects(IMLoginLockedMessage(@{ @"code": @200006, @"data": @{ @"retry_after_sec": @YES } }), generic);
    XCTAssertEqualObjects(IMLoginLockedMessage(@{ @"code": @200006, @"data": @{ @"retry_after_sec": @(-30) } }), generic);
}

/// 登录失败走 messageFrom: 生成 error.localizedDescription（登录页直接显示它）。
- (void)testMessageFromUsesLockedTextOrGenericRateLimit {
    IMHTTPService *svc = IMHTTPService.sharedService;
    NSDictionary *withData = @{ @"code": @200006, @"message": @"server says", @"data": @{ @"retry_after_sec": @120 } };
    XCTAssertEqualObjects([svc messageFrom:withData fallback:@"fb"], IMLocalizedFormat(@"err.200006", @"2"));
    NSDictionary *noData = @{ @"code": @200006, @"message": @"server says" };
    XCTAssertEqualObjects([svc messageFrom:noData fallback:@"fb"], IMLocalized(@"err.100002"), @"不回退服务端原文");
}

#pragma mark - 200007 RegisterClosed

- (void)testRegisterClosedIsMappedAndLockedIsNotStaticallyMapped {
    XCTAssertEqualObjects(IMFriendlyMessageForCode(IMErrCodeRegisterClosed), IMLocalized(@"err.200007"));
    XCTAssertNotEqualObjects(IMLocalized(@"err.200007"), @"err.200007", @"生成的 Localizable.strings 必须含该键");
    XCTAssertNil(IMFriendlyMessageForCode(IMErrCodeLoginLocked), @"200006 需带分钟数，不能走静态映射");
}

#pragma mark - public-config 解析

- (BOOL)enabledFor:(id)obj {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    return [IMPublicConfig registerEnabledFromResponseData:data];
}

- (void)testRegisterEnabledParsing {
    NSDictionary *off = @{ @"code": @0, @"data": @{ @"register_enabled": @NO } };
    NSDictionary *on = @{ @"code": @0, @"data": @{ @"register_enabled": @YES } };
    XCTAssertFalse([self enabledFor:off]);
    XCTAssertTrue([self enabledFor:on]);
}

- (void)testRegisterEnabledDefaultsToYesOnAnythingUnexpected {
    NSDictionary *noField = @{ @"code": @0, @"data": @{} };
    NSDictionary *noData = @{ @"code": @0 };
    NSDictionary *wrongType = @{ @"code": @0, @"data": @{ @"register_enabled": @"false" } };
    NSDictionary *badCode = @{ @"code": @100001, @"data": @{ @"register_enabled": @NO } };
    NSDictionary *nullCode = @{ @"code": [NSNull null], @"data": @{ @"register_enabled": @NO } };
    XCTAssertTrue([IMPublicConfig registerEnabledFromResponseData:nil]);
    XCTAssertTrue([IMPublicConfig registerEnabledFromResponseData:[@"<html>404</html>" dataUsingEncoding:NSUTF8StringEncoding]]);
    XCTAssertTrue([self enabledFor:noField], @"字段缺失");
    XCTAssertTrue([self enabledFor:noData], @"data 缺失");
    XCTAssertTrue([self enabledFor:wrongType], @"类型不对");
    XCTAssertTrue([self enabledFor:badCode], @"code≠0");
    XCTAssertTrue([self enabledFor:nullCode]);
}

#pragma mark - 旧响应丢弃

/// host 为空时立即（异步）回调 YES，不碰网络——用它验证「只有最近一次请求会回调」。
- (void)testOnlyLatestFetchCompletes {
    IMPublicConfig *config = [IMPublicConfig new];
    __block NSInteger firstCalls = 0, secondCalls = 0;
    XCTestExpectation *done = [self expectationWithDescription:@"latest"];
    [config fetchRegisterEnabledWithScheme:nil host:@"" completion:^(BOOL enabled) { firstCalls++; }];
    [config fetchRegisterEnabledWithScheme:nil host:@"" completion:^(BOOL enabled) {
        secondCalls++;
        XCTAssertTrue(enabled);
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:2];
    XCTAssertEqual(firstCalls, 0, @"被新请求取代的旧回调不得触发");
    XCTAssertEqual(secondCalls, 1);
}

- (void)testCancelSuppressesCompletion {
    IMPublicConfig *config = [IMPublicConfig new];
    __block BOOL called = NO;
    [config fetchRegisterEnabledWithScheme:nil host:@"" completion:^(BOOL enabled) { called = YES; }];
    [config cancel];
    XCTestExpectation *tick = [self expectationWithDescription:@"main queue drained"];
    dispatch_async(dispatch_get_main_queue(), ^{ dispatch_async(dispatch_get_main_queue(), ^{ [tick fulfill]; }); });
    [self waitForExpectations:@[tick] timeout:2];
    XCTAssertFalse(called);
}

@end
