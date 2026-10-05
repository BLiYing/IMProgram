//  IMRtcHistoryReloginTests.m
//  最近通话：哪些拉取失败值得「重新换票登录再拉一次」。

#import <XCTest/XCTest.h>
#import "IMRtcCall.h"
@import IMCallEngine;

@interface IMRtcHistoryReloginTests : XCTestCase
@end

@implementation IMRtcHistoryReloginTests

- (NSError *)errorDomain:(NSString *)d code:(NSInteger)c { return [NSError errorWithDomain:d code:c userInfo:nil]; }

- (void)testNotLoggedInNeedsRelogin {
    XCTAssertTrue(IMRtcHistoryErrorNeedsRelogin([self errorDomain:IMRTCErrorInfo.domain code:2007]));
}

- (void)testOtherSdkErrorsDoNot {
    XCTAssertFalse(IMRtcHistoryErrorNeedsRelogin([self errorDomain:IMRTCErrorInfo.domain code:1101])); // 票无效
    XCTAssertFalse(IMRtcHistoryErrorNeedsRelogin([self errorDomain:IMRTCErrorInfo.domain code:2003])); // 网络不通
    XCTAssertFalse(IMRtcHistoryErrorNeedsRelogin([self errorDomain:IMRTCErrorInfo.domain code:2005])); // 已登录
}

- (void)testForeignDomainAndNilDoNot {
    XCTAssertFalse(IMRtcHistoryErrorNeedsRelogin([self errorDomain:@"IMRtcCall" code:2007]));
    XCTAssertFalse(IMRtcHistoryErrorNeedsRelogin(nil));
}

@end
