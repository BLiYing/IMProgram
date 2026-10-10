//  IMFriendRequestSectionsTests.m
//  「新的朋友」分段：待我确认 / 已发出 / 已添加（30 天边界、50 条上限、倒序、其它状态排除）
//  + 本地好友关系变更通知（后台线程调用也必须在主线程送达）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Contacts/IMFriendRequestSections.h"
#import "../IMProgram/Modules/Contacts/IMFriendRequestListViewController.h"
#import "../IMProgram/Models/IMUserCard.h"

static const int64_t kDayMs = 24LL * 60 * 60 * 1000;
static const int64_t kNow = 1800000000000LL;

@interface IMFriendRequestSectionsTests : XCTestCase
@end

@implementation IMFriendRequestSectionsTests

- (IMUserCard *)card:(NSString *)uid status:(IMFriendStatus)st updatedAt:(int64_t)ts {
    IMUserCard *c = [IMUserCard new];
    c.userID = uid;
    c.status = st;
    c.updatedAt = ts;
    return c;
}

/// 恰好 30 天算在内，差 1ms 不算。
- (void)testThirtyDayBoundary {
    NSArray *cards = @[
        [self card:@"in" status:IMFriendStatusAccepted updatedAt:kNow - 30 * kDayMs],
        [self card:@"out" status:IMFriendStatusAccepted updatedAt:kNow - 30 * kDayMs - 1],
    ];
    IMFriendRequestSections *s = [IMFriendRequestSections sectionsWithCards:cards nowMs:kNow];
    XCTAssertEqual(s.added.count, 1u);
    XCTAssertEqualObjects(s.added.firstObject.userID, @"in");
}

/// 其它状态（none / blocked）不进任何段；pending / requested 各归各段，且不因时间被过滤。
- (void)testStatusRouting {
    NSArray *cards = @[
        [self card:@"p" status:IMFriendStatusPending updatedAt:kNow - 90 * kDayMs],
        [self card:@"r" status:IMFriendStatusRequested updatedAt:kNow - 90 * kDayMs],
        [self card:@"n" status:IMFriendStatusNone updatedAt:kNow],
        [self card:@"b" status:IMFriendStatusBlocked updatedAt:kNow],
        [self card:@"a" status:IMFriendStatusAccepted updatedAt:kNow],
    ];
    IMFriendRequestSections *s = [IMFriendRequestSections sectionsWithCards:cards nowMs:kNow];
    XCTAssertEqualObjects([s.incoming valueForKey:@"userID"], @[@"p"]);
    XCTAssertEqualObjects([s.outgoing valueForKey:@"userID"], @[@"r"]);
    XCTAssertEqualObjects([s.added valueForKey:@"userID"], @[@"a"]);
}

/// updatedAt 倒序（最新在前）。
- (void)testAddedSortedDescending {
    NSArray *cards = @[
        [self card:@"old" status:IMFriendStatusAccepted updatedAt:kNow - 5 * kDayMs],
        [self card:@"new" status:IMFriendStatusAccepted updatedAt:kNow - 1 * kDayMs],
        [self card:@"mid" status:IMFriendStatusAccepted updatedAt:kNow - 3 * kDayMs],
    ];
    IMFriendRequestSections *s = [IMFriendRequestSections sectionsWithCards:cards nowMs:kNow];
    XCTAssertEqualObjects([s.added valueForKey:@"userID"], (@[@"new", @"mid", @"old"]));
}

/// 上限 50：保留最新的 50 条。
- (void)testCapKeepsNewestFifty {
    NSMutableArray *cards = [NSMutableArray array];
    for (int i = 0; i < 60; i++) {
        [cards addObject:[self card:[NSString stringWithFormat:@"u%d", i] status:IMFriendStatusAccepted updatedAt:kNow - i * 1000]];
    }
    IMFriendRequestSections *s = [IMFriendRequestSections sectionsWithCards:cards nowMs:kNow];
    XCTAssertEqual(s.added.count, (NSUInteger)kIMRecentAddedMax);
    XCTAssertEqualObjects(s.added.firstObject.userID, @"u0");
    XCTAssertEqualObjects(s.added.lastObject.userID, @"u49");
}

/// 空判定：三段全空才为空；只有「已添加」非空也不算空。nil 输入安全。
- (void)testIsEmpty {
    XCTAssertTrue([IMFriendRequestSections sectionsWithCards:nil nowMs:kNow].isEmpty);
    XCTAssertTrue([IMFriendRequestSections sectionsWithCards:@[[self card:@"x" status:IMFriendStatusAccepted updatedAt:kNow - 40 * kDayMs]] nowMs:kNow].isEmpty);
    XCTAssertFalse([IMFriendRequestSections sectionsWithCards:@[[self card:@"x" status:IMFriendStatusAccepted updatedAt:kNow]] nowMs:kNow].isEmpty);
}

/// 本地通知：从后台线程调用也在主线程送达（通讯录页据此立即 reload）。
- (void)testLocalNotificationDeliveredOnMain {
    XCTestExpectation *exp = [self expectationWithDescription:@"notified"];
    id token = [NSNotificationCenter.defaultCenter addObserverForName:IMFriendRelationDidChangeLocallyNotification
                                                               object:nil queue:nil usingBlock:^(NSNotification *n) {
        XCTAssertTrue(NSThread.isMainThread);
        [exp fulfill];
    }];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ IMPostFriendRelationDidChangeLocally(); });
    [self waitForExpectations:@[exp] timeout:3];
    [NSNotificationCenter.defaultCenter removeObserver:token];
}

@end
