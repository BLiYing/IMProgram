//  IMMuteDurationMenuTests.m
//  IMMuteUntilForDurationOption 纯函数单测（Common/IMMuteDurationMenu.h）：
//  时长菜单选项 → mute_until 的映射（NOTIFICATIONS_P1_DESIGN §4.1）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMMuteDurationMenu.h"

@interface IMMuteDurationMenuTests : XCTestCase
@end

@implementation IMMuteDurationMenuTests

- (void)testOneHour {
    int64_t now = 1790647200000;
    XCTAssertEqual(IMMuteUntilForDurationOption(IMMuteDurationOneHour, now), now + 3600000LL);
}

- (void)testEightHours {
    int64_t now = 1790647200000;
    XCTAssertEqual(IMMuteUntilForDurationOption(IMMuteDurationEightHours, now), now + 8LL * 3600000);
}

- (void)testOneDay {
    int64_t now = 1790647200000;
    XCTAssertEqual(IMMuteUntilForDurationOption(IMMuteDurationOneDay, now), now + 24LL * 3600000);
}

- (void)testSevenDays {
    int64_t now = 1790647200000;
    XCTAssertEqual(IMMuteUntilForDurationOption(IMMuteDurationSevenDays, now), now + 7LL * 24 * 3600000);
}

- (void)testForeverIsAlwaysZeroRegardlessOfNow {
    // 永久＝协议 mute_until=0，与 now 无关（不是"现在 + 一个很大的数"）。
    XCTAssertEqual(IMMuteUntilForDurationOption(IMMuteDurationForever, 0), 0);
    XCTAssertEqual(IMMuteUntilForDurationOption(IMMuteDurationForever, 1790647200000), 0);
}

- (void)testUsesGivenNowNotWallClock {
    // 纯函数：结果完全由传入的 now 决定，同一个 now 反复调用必须得到同一个答案
    // （与调用时的真实系统时钟无关——菜单点选后拼 mute_until 得可预测、可测）。
    int64_t now = 42;
    XCTAssertEqual(IMMuteUntilForDurationOption(IMMuteDurationOneHour, now), 42 + 3600000LL);
    XCTAssertEqual(IMMuteUntilForDurationOption(IMMuteDurationOneHour, now), 42 + 3600000LL);
}

@end
