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
    // 2026-10-01 改：中文名取末字，英文名/用户名取首字母并转大写（三端同口径，见 IMAvatarPlaceholder.h）。
    XCTAssertEqualObjects(IMAvatarInitials(@"张三丰"), @"丰", @"中文名取末字");
    XCTAssertEqualObjects(IMAvatarInitials(@"bob"), @"B", @"英文名取首字母并转大写");
    XCTAssertEqualObjects(IMAvatarInitials(@"甲"), @"甲", @"单字中文名原样");
    XCTAssertEqualObjects(IMAvatarInitials(@"用户1001"), @"用", @"中文开头+数字：末字不是汉字，退回取首字母");
    XCTAssertEqualObjects(IMAvatarInitials(@""), @"");
    XCTAssertEqualObjects(IMAvatarInitials(nil), @"", @"nil 安全");
}

@end
