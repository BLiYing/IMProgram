//  IMPresenceTests.m
//  在线态租约模型的纯逻辑测试：解析（含脏数据）、租约到期自动降级、副标题文案分级。
//  app-hosted 测试，符号由宿主 App 提供；头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMPresence.h"
#import "../IMProgram/Models/IMUserCard.h"

@interface IMPresenceTests : XCTestCase
@end

@implementation IMPresenceTests

/// 当前毫秒时间戳。
static int64_t nowMs(void) { return (int64_t)(NSDate.date.timeIntervalSince1970 * 1000); }

#pragma mark - 解析

- (void)testParsesProfileKeys {
    IMPresence *p = [IMPresence presenceFromProfileDictionary:@{
        @"presence": @"online", @"online_until": @(nowMs() + 60000), @"last_seen": @12345
    }];
    XCTAssertEqual(p.level, IMPresenceLevelOnline);
    XCTAssertEqual(p.lastSeen, 12345);
    XCTAssertTrue(p.isOnline);
}

- (void)testParsesConversationKeys {
    IMPresence *p = [IMPresence presenceFromConversationDictionary:@{
        @"peer_presence": @"recently", @"peer_last_seen": @999
    }];
    XCTAssertEqual(p.level, IMPresenceLevelRecently);
    XCTAssertEqual(p.lastSeen, 999);
    XCTAssertFalse(p.isOnline);
}

- (void)testDirtyDataIsSafe {
    XCTAssertEqual([IMPresence presenceFromProfileDictionary:nil].level, IMPresenceLevelUnknown);
    XCTAssertEqual([IMPresence presenceFromProfileDictionary:(id)@"not a dict"].level, IMPresenceLevelUnknown);
    IMPresence *weird = [IMPresence presenceFromProfileDictionary:@{
        @"presence": @42, @"online_until": @"字符串", @"last_seen": NSNull.null
    }];
    XCTAssertEqual(weird.level, IMPresenceLevelUnknown);
    XCTAssertEqual(weird.onlineUntil, 0);
    XCTAssertEqual(weird.lastSeen, 0);
    XCTAssertEqualObjects(weird.subtitleText, @"");
}

/// 找人/好友列表不带在线态键 → 解析出空态，副标题为空串（不显示占位）。
- (void)testUserCardWithoutPresenceKeysIsEmptyState {
    IMUserCard *c = [IMUserCard cardsFromArray:@[@{ @"user_id": @"1002", @"nickname": @"小明" }]].firstObject;
    XCTAssertNotNil(c.presence);
    XCTAssertEqual(c.presence.level, IMPresenceLevelUnknown);
    XCTAssertEqualObjects(c.presence.subtitleText, @"");
}

#pragma mark - 租约（核心：服务端不推下线，靠到期本地降级）

- (void)testLeaseExpiryDowngradesWithoutServerFrame {
    IMPresence *p = [IMPresence new];
    p.level = IMPresenceLevelOnline;       // 快照当时判定为在线
    p.onlineUntil = nowMs() - 1;           // 但租约已过期
    p.lastSeen = nowMs() - 30 * 1000;      // 半分钟前
    XCTAssertFalse(p.isOnline, @"租约过期即不在线，无需服务端下线帧");
    XCTAssertEqualObjects(p.subtitleText, @"刚刚在线");
}

- (void)testOnlineWinsOverLastSeen {
    IMPresence *p = [IMPresence new];
    p.onlineUntil = nowMs() + 60 * 1000;
    p.lastSeen = nowMs() - 10 * 24 * 3600 * 1000LL; // 十天前，但当前有效租约压过它
    XCTAssertTrue(p.isOnline);
    XCTAssertEqualObjects(p.subtitleText, @"在线");
}

#pragma mark - 副标题文案分级

- (void)testSubtitleBuckets {
    IMPresence *p = [IMPresence new];

    p.lastSeen = nowMs() - 30 * 1000;
    XCTAssertEqualObjects(p.subtitleText, @"刚刚在线");

    p.lastSeen = nowMs() - 5 * 60 * 1000;
    XCTAssertEqualObjects(p.subtitleText, @"5 分钟前在线");

    p.lastSeen = nowMs() - 59 * 60 * 1000;
    XCTAssertEqualObjects(p.subtitleText, @"59 分钟前在线");
}

/// 无精确时间（未知或将来被隐私设置抹掉）时回退到粗档文案。
- (void)testSubtitleFallsBackToLevelWhenLastSeenHidden {
    IMPresence *p = [IMPresence new];
    p.lastSeen = 0;

    p.level = IMPresenceLevelRecently;
    XCTAssertEqualObjects(p.subtitleText, @"最近在线");
    p.level = IMPresenceLevelLastWeek;
    XCTAssertEqualObjects(p.subtitleText, @"一周内在线");
    p.level = IMPresenceLevelLastMonth;
    XCTAssertEqualObjects(p.subtitleText, @"一个月内在线");
    p.level = IMPresenceLevelLongAgo;
    XCTAssertEqualObjects(p.subtitleText, @"很久未上线");
    p.level = IMPresenceLevelUnknown;
    XCTAssertEqualObjects(p.subtitleText, @"", @"未知态不显示副标题占位");
}

@end
