//  IMRtcHistoryReloginTests.m
//  最近通话：哪些拉取失败值得「重新换票登录再拉一次」。

#import <XCTest/XCTest.h>
#import "IMRtcCall.h"
@import IMCallEngine;

@interface IMRtcHistoryReloginTests : XCTestCase
@end

@implementation IMRtcHistoryReloginTests

- (NSError *)errorDomain:(NSString *)d code:(NSInteger)c { return [NSError errorWithDomain:d code:c userInfo:nil]; }

- (void)testSessionLossErrorsNeedRestart {
    XCTAssertTrue(IMRtcHistoryErrorNeedsRelogin([self errorDomain:IMRTCErrorInfo.domain code:2007])); // 尚未登录
    XCTAssertTrue(IMRtcHistoryErrorNeedsRelogin([self errorDomain:IMRTCErrorInfo.domain code:1101])); // 票无效 / 过期（REST 401）
    XCTAssertTrue(IMRtcHistoryErrorNeedsRelogin([self errorDomain:IMRTCErrorInfo.domain code:2003])); // 信令 / REST 不可达
}

- (void)testEngineTornDownNeedsRestart {
    XCTAssertTrue(IMRtcHistoryErrorNeedsRelogin([self errorDomain:@"IMRtcCall" code:-1])); // 引擎被拆（被踢后 stop）
}

- (void)testUnrelatedErrorsDoNot {
    XCTAssertFalse(IMRtcHistoryErrorNeedsRelogin([self errorDomain:IMRTCErrorInfo.domain code:2005])); // 已登录
    XCTAssertFalse(IMRtcHistoryErrorNeedsRelogin([self errorDomain:IMRTCErrorInfo.domain code:1501])); // 服务端内部错
    XCTAssertFalse(IMRtcHistoryErrorNeedsRelogin([self errorDomain:@"IMRtcCall" code:-2]));          // 引擎已换代，本次作废
}

- (void)testForeignDomainAndNilDoNot {
    XCTAssertFalse(IMRtcHistoryErrorNeedsRelogin([self errorDomain:@"IMRtcCall" code:2007]));
    XCTAssertFalse(IMRtcHistoryErrorNeedsRelogin([self errorDomain:@"NSURLErrorDomain" code:-1009]));
    XCTAssertFalse(IMRtcHistoryErrorNeedsRelogin(nil));
}

/// 无论引擎状态如何（共享单例，可能被别的用例起过）：回调必须回来，不挂起、不崩。
- (void)testFetchAlwaysCompletes {
    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [IMRtcCall.shared fetchCallHistoryWithLimit:20 cursor:nil completion:^(NSArray *r, NSNumber *n, NSError *e) {
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:20];
}

/// 登出 / 被踢后 stop 清掉自愈许可：此后点「最近通话」重试只回错误，不能偷偷把引擎重启重登（_recoverable 保持 NO）。
- (void)testNoRecoveryAfterStop {
    IMRtcCall *call = IMRtcCall.shared;
    [call stop];
    [call setValue:@"u_stopped" forKey:@"_uid"]; // 模拟登出/被踢后 _uid 仍留着
    XCTAssertFalse([[call valueForKey:@"_recoverable"] boolValue]);
    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    __block NSError *err = nil;
    [call fetchCallHistoryWithLimit:20 cursor:nil completion:^(NSArray *r, NSNumber *n, NSError *e) { err = e; [done fulfill]; }];
    [self waitForExpectations:@[done] timeout:5];
    XCTAssertEqual(err.code, -1); // 引擎未启动
    XCTAssertFalse([[call valueForKey:@"_recoverable"] boolValue], @"stop 后重试不得重新置位 / 重启");
    XCTAssertFalse(call.isStarted);
    [call setValue:@"" forKey:@"_uid"];
}

@end
