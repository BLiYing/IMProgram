//  IMRtcCallInCallTests.m
//  「正在通话」判据（IMRtcCallPhaseCountsAsInCall）+ 回归：通话服务就绪 ≠ 正在通话。
//
//  起因（2026-09-30）：通知判定的 inCall 误读了 `IMRtcCall.isStarted`（引擎已建好，登录后恒 YES），
//  通话服务一配好，应用内提示音 / 振动 / 横幅全部永久静默。阶段原始值对应 SDK 的 `IMCallKitPhase`：
//  0 idle / 1 incoming / 2 outgoing / 3 connecting / 4 active / 5 ended。

#import <XCTest/XCTest.h>
#import "IMRtcCall.h"

@interface IMRtcCallInCallTests : XCTestCase
@end

@implementation IMRtcCallInCallTests

- (void)testIdleAndEndedAreNotInCall {
    XCTAssertFalse(IMRtcCallPhaseCountsAsInCall(0)); // idle：没有通话
    XCTAssertFalse(IMRtcCallPhaseCountsAsInCall(5)); // ended：只是结束页还没收起
}

- (void)testRingingDialingConnectingActiveAreInCall {
    XCTAssertTrue(IMRtcCallPhaseCountsAsInCall(1)); // 来电响铃
    XCTAssertTrue(IMRtcCallPhaseCountsAsInCall(2)); // 拨出等待
    XCTAssertTrue(IMRtcCallPhaseCountsAsInCall(3)); // 接通中
    XCTAssertTrue(IMRtcCallPhaseCountsAsInCall(4)); // 通话中
}

- (void)testUnknownPhaseDoesNotSwallowAlerts {
    XCTAssertFalse(IMRtcCallPhaseCountsAsInCall(99));
}

/// 没有进行中的通话时 isInCall 必须是 NO——不论通话服务起没起来（起来了 isStarted 是 YES，
/// 但那不是"在通话"）。测试进程里没有登录，引擎未建，走的是 _kit == nil 这一支。
- (void)testNotInCallWhenNoCall {
    XCTAssertFalse(IMRtcCall.shared.isInCall);
}

@end
