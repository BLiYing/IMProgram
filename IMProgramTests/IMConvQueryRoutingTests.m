#import <XCTest/XCTest.h>

#import "IMConvQuerySource.h"
#import "IMUnreadBadge.h"

/// 两个**三端同源**的纯逻辑：「整会话问题」问谁，以及未读角标怎么写。
///
/// 值得单独钉的理由是一样的：它们的错法都不报错。分流判错 → 大群里搜不到缺口里的消息、
/// 日历那些天全灰，界面一切正常；格式化写岔 → 同一个群在 iOS 与 Web 上显示不同数字，
/// 用户第一反应是"消息丢了"。对照 im-web 的 convQuerySource.test.ts / unreadBadge.test.ts。
@interface IMConvQueryRoutingTests : XCTestCase
@end

@implementation IMConvQueryRoutingTests

#pragma mark - 分流判据

- (void)testCompleteAlwaysLocal {
    // 齐全时联不联网都走本地——没有理由为一个完整的本地库去问服务端。
    XCTAssertEqual(IMPickConvQuerySource(YES, YES), IMConvQuerySourceLocal);
    XCTAssertEqual(IMPickConvQuerySource(YES, NO), IMConvQuerySourceLocal);
}

- (void)testGappedOnlineGoesToServer {
    XCTAssertEqual(IMPickConvQuerySource(NO, YES), IMConvQuerySourceServer);
}

- (void)testGappedOfflineDegradesLoudly {
    // 有缺口又没网：只能给本地那部分，但**必须**是可标注的第三态，不能和"本地齐全"混为一谈——
    // 混了就等于静默给一个残缺答案。
    XCTAssertEqual(IMPickConvQuerySource(NO, NO), IMConvQuerySourceLocalDegraded);
    XCTAssertNotEqual(IMPickConvQuerySource(NO, NO), IMConvQuerySourceLocal);
}

#pragma mark - 未读角标

- (void)testCompactCountThreeTiers {
    XCTAssertEqualObjects(IMCompactCount(0), @"0");
    XCTAssertEqualObjects(IMCompactCount(1), @"1");
    XCTAssertEqualObjects(IMCompactCount(999), @"999");
    XCTAssertEqualObjects(IMCompactCount(1000), @"1K");
    XCTAssertEqualObjects(IMCompactCount(1234), @"1.2K");
    XCTAssertEqualObjects(IMCompactCount(5000), @"5K");
    XCTAssertEqualObjects(IMCompactCount(12345), @"12.3K");
    XCTAssertEqualObjects(IMCompactCount(1000000), @"1M");
    XCTAssertEqualObjects(IMCompactCount(1200000), @"1.2M");
}

- (void)testBadgeTextEmptyWhenNothingUnread {
    XCTAssertEqualObjects(IMUnreadBadgeText(0, NO), @"");
    XCTAssertEqualObjects(IMUnreadBadgeText(-3, NO), @"");
}

- (void)testBadgeTextCappedGetsPlus {
    // `+` 说的是"至少这么多"。这与旧的 99+ 不是一回事：旧的是把 342 谎报成 99+。
    XCTAssertEqualObjects(IMUnreadBadgeText(342, NO), @"342");
    XCTAssertEqualObjects(IMUnreadBadgeText(10000, YES), @"10K+");
}

@end
