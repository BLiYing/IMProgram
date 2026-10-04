//  IMDeviceModelsTests.m
//  已登录设备列表的模型（IMDeviceSession）：脏数据解析 / 在线与否的副标题 / 相对活跃时间分档。
//
//  错法：脏字段让设备管理页崩溃或错位；「在线」判成离线（用户以为那台设备没在用而不敢踢）；
//  分档边界错一位（59 秒显示「1 分钟前」之类）。文案一律用 IMLocalized 取值断言，不写死中文，免受当前语言影响。

#import <XCTest/XCTest.h>

#import "IMDeviceModels.h"
#import "IMLocalization.h"

@interface IMDeviceModelsTests : XCTestCase
@end

@implementation IMDeviceModelsTests

static int64_t NowMs(void) { return (int64_t)(NSDate.date.timeIntervalSince1970 * 1000); }

#pragma mark - 解析

/// 缺 session_id（踢下线的目标）整条丢弃：没有它这行点了也踢不了任何设备。
- (void)test_缺session_id丢弃 {
    XCTAssertNil([IMDeviceSession fromDictionary:@{ @"platform": @"ios" }]);
    XCTAssertNil([IMDeviceSession fromDictionary:@{ @"session_id": @"" }]);
    XCTAssertNil([IMDeviceSession fromDictionary:@{ @"session_id": @123 }], @"类型不对按缺失处理");
    XCTAssertNil([IMDeviceSession fromDictionary:nil]);
    XCTAssertNil([IMDeviceSession fromDictionary:(id)@"junk"]);
}

/// 脏字段安全取值：类型不符回退默认值，绝不抛。
- (void)test_脏字段回退默认值 {
    IMDeviceSession *s = [IMDeviceSession fromDictionary:@{
        @"session_id": @"s1", @"platform": @5, @"device_name": NSNull.null, @"created_at": @"1700000000000",
        @"last_active_at": @[], @"online": @"yes", @"current": @1 }];
    XCTAssertEqualObjects(s.sessionID, @"s1");
    XCTAssertEqualObjects(s.platform, @"");
    XCTAssertEqualObjects(s.deviceName, @"");
    XCTAssertEqual(s.createdAt, 1700000000000, @"字符串里的数字也能取（respondsToSelector:longLongValue）");
    XCTAssertEqual(s.lastActiveAt, 0);
    XCTAssertFalse(s.online, @"online 只认 NSNumber：字符串 \"yes\" 不算在线");
    XCTAssertTrue(s.current);
}

/// 数组里夹着脏项：跳过脏项，其余照常；非数组返回空数组（不是 nil）。
- (void)test_数组解析跳过脏项 {
    NSArray *out = [IMDeviceSession fromArray:@[ @{ @"session_id": @"a" }, @"junk", @{ }, NSNull.null, @{ @"session_id": @"b" } ]];
    XCTAssertEqual(out.count, 2u);
    XCTAssertEqualObjects([out[1] sessionID], @"b");
    XCTAssertEqual([IMDeviceSession fromArray:(id)@"nope"].count, 0u);
    XCTAssertEqual([IMDeviceSession fromArray:nil].count, 0u);
}

#pragma mark - 平台

- (void)test_平台图标与展示名 {
    NSDictionary<NSString *, NSArray *> *cases = @{ @"ios": @[@"📱", @"iOS"], @"android": @[@"🤖", @"Android"] };
    for (NSString *p in cases) {
        IMDeviceSession *s = [IMDeviceSession fromDictionary:@{ @"session_id": @"s", @"platform": p }];
        XCTAssertEqualObjects(s.platformEmoji, cases[p][0]);
        XCTAssertEqualObjects(s.platformLabel, cases[p][1]);
    }
    IMDeviceSession *web = [IMDeviceSession fromDictionary:@{ @"session_id": @"s", @"platform": @"web" }];
    XCTAssertEqualObjects(web.platformEmoji, @"💻");
    XCTAssertEqualObjects(web.platformLabel, IMLocalized(@"device.platform.web"));
    IMDeviceSession *desk = [IMDeviceSession fromDictionary:@{ @"session_id": @"s", @"platform": @"desktop" }];
    XCTAssertEqualObjects(desk.platformEmoji, @"🖥");
    // 未知/空平台：中性图标与「未知设备」，不能崩。
    IMDeviceSession *unk = [IMDeviceSession fromDictionary:@{ @"session_id": @"s", @"platform": @"toaster" }];
    XCTAssertEqualObjects(unk.platformEmoji, @"📟");
    XCTAssertEqualObjects(unk.platformLabel, IMLocalized(@"device.platform.unknown"));
}

#pragma mark - 相对活跃时间分档

- (IMDeviceSession *)sessionActiveSecondsAgo:(double)sec {
    return [IMDeviceSession fromDictionary:@{ @"session_id": @"s", @"last_active_at": @(NowMs() - (int64_t)(sec * 1000)) }];
}

/// 分档边界：<60s 刚刚；<1h 按分钟；<1d 按小时；其余按天。未来时间（时钟偏差）归零按「刚刚」。
- (void)test_相对活跃分档与边界 {
    XCTAssertEqualObjects([self sessionActiveSecondsAgo:5].lastActiveText, IMLocalized(@"device.active.just_now"));
    XCTAssertEqualObjects([self sessionActiveSecondsAgo:-300].lastActiveText, IMLocalized(@"device.active.just_now"), @"未来时间不能显示负数");
    XCTAssertEqualObjects([self sessionActiveSecondsAgo:61].lastActiveText, IMLocalizedFormat(@"device.active.minutes_ago", 1L));
    XCTAssertEqualObjects([self sessionActiveSecondsAgo:3599].lastActiveText, IMLocalizedFormat(@"device.active.minutes_ago", 59L));
    XCTAssertEqualObjects([self sessionActiveSecondsAgo:3601].lastActiveText, IMLocalizedFormat(@"device.active.hours_ago", 1L));
    XCTAssertEqualObjects([self sessionActiveSecondsAgo:86399].lastActiveText, IMLocalizedFormat(@"device.active.hours_ago", 23L));
    XCTAssertEqualObjects([self sessionActiveSecondsAgo:86401].lastActiveText, IMLocalizedFormat(@"device.active.days_ago", 1L));
    XCTAssertEqualObjects([self sessionActiveSecondsAgo:86400 * 3 + 5].lastActiveText, IMLocalizedFormat(@"device.active.days_ago", 3L));
}

/// 从未活跃（last_active_at<=0）显示「离线」，不能显示「X 天前」（那是 1970 年）。
- (void)test_从未活跃显示离线 {
    IMDeviceSession *s = [IMDeviceSession fromDictionary:@{ @"session_id": @"s", @"last_active_at": @0 }];
    XCTAssertEqualObjects(s.lastActiveText, IMLocalized(@"common.offline"));
}

#pragma mark - 副标题

/// 在线：「在线 · 平台 · 位置 · IP」，**不显示相对时间**；离线：显示相对活跃。位置/IP 为空就不占位。
- (void)test_副标题_在线与离线 {
    IMDeviceSession *on = [IMDeviceSession fromDictionary:@{ @"session_id": @"s", @"platform": @"ios", @"online": @YES,
        @"login_loc": @"深圳", @"login_ip": @"1.2.3.4", @"last_active_at": @(NowMs() - 999999999) }];
    NSString *expectOn = [@[IMLocalized(@"common.online"), @"iOS", @"深圳", @"1.2.3.4"] componentsJoinedByString:@" · "];
    XCTAssertEqualObjects(on.statusLine, expectOn);

    IMDeviceSession *off = [IMDeviceSession fromDictionary:@{ @"session_id": @"s", @"platform": @"ios", @"online": @NO,
        @"login_loc": @"", @"login_ip": @"9.9.9.9", @"last_active_at": @(NowMs() - 120 * 1000) }];
    NSString *expectOff = [@[IMLocalizedFormat(@"device.active.minutes_ago", 2L), @"9.9.9.9"] componentsJoinedByString:@" · "];
    XCTAssertEqualObjects(off.statusLine, expectOff);
}

#pragma mark - 登录时间

/// 登录时间：<=0 回「—」；否则绝对时间 `yyyy-MM-dd HH:mm`（格式固定，不随语言变）。
- (void)test_登录时间文案 {
    IMDeviceSession *none = [IMDeviceSession fromDictionary:@{ @"session_id": @"s", @"created_at": @0 }];
    XCTAssertEqualObjects(none.loginTimeText, @"—");
    IMDeviceSession *s = [IMDeviceSession fromDictionary:@{ @"session_id": @"s", @"created_at": @1788000000000 }];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}$" options:0 error:NULL];
    XCTAssertEqual([re numberOfMatchesInString:s.loginTimeText options:0 range:NSMakeRange(0, s.loginTimeText.length)], 1u, @"%@", s.loginTimeText);
}

@end
