#import <XCTest/XCTest.h>

#import "IMTimeUtil.h"
#import "UILabel+IMAvatar.h"

/// Common 层自由函数单测（CODING_STYLE §7③：纯逻辑 → *Util 自由函数 + 配单测）。
@interface IMCommonUtilTests : XCTestCase
@end

@implementation IMCommonUtilTests

- (void)testNowMillisIsMillisecondScaleAndMonotonic {
    int64_t a = IMNowMillis();
    // 毫秒量级（秒级会小三个量级）：2020-01-01 起的毫秒时间戳必大于 1.5e12。
    XCTAssertGreaterThan(a, 1500000000000LL, @"应为毫秒时间戳，而非秒");
    XCTAssertLessThan(a, 100000000000000LL, @"应为毫秒时间戳，而非微秒/纳秒");
    int64_t b = IMNowMillis();
    XCTAssertGreaterThanOrEqual(b, a, @"时间不回退");
}

- (void)testAvatarInitialsRule {
    XCTAssertEqualObjects(IMAvatarInitials(@"张三丰"), @"三丰", @"取末两位");
    XCTAssertEqualObjects(IMAvatarInitials(@"Bob"), @"ob");
    XCTAssertEqualObjects(IMAvatarInitials(@"甲"), @"甲", @"不足两位原样");
    XCTAssertEqualObjects(IMAvatarInitials(@""), @"");
    XCTAssertEqualObjects(IMAvatarInitials(nil), @"", @"nil 安全");
}

@end
