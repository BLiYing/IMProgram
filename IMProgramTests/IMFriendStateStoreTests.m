#import <XCTest/XCTest.h>

#import "IMFriendStateStore.h"
#import "IMUserCard.h"

/// 「谁是我的好友」进程内快照。盯的是它存在的理由——**三态**（是 / 不是 / 不知道）：
/// 把"不知道"塌成"不是"，冷启动第一次进资料页会把好友显示成陌生人；
/// 把"不是"塌成"不知道"，删好友后资料页照旧显示好友界面。两个方向都错过，故用例主要压这两处。
///
/// 用**独立实例**而非 sharedStore：本类唯一的状态就是"喂过没喂过"，共享单例会让用例互相污染
/// （前一个用例喂过全集，后一个就再也测不到「不知道」）。
@interface IMFriendStateStoreTests : XCTestCase
@end

@implementation IMFriendStateStoreTests

- (IMUserCard *)cardWithID:(NSString *)uid status:(IMFriendStatus)status {
    IMUserCard *c = [IMUserCard new];
    c.userID = uid;
    c.status = status;
    return c;
}

#pragma mark - 三态

- (void)testUnknownUntilFedAFullList {
    IMFriendStateStore *store = [IMFriendStateStore new];
    XCTAssertNil([store friendStateForUser:@"bob"], @"没喂过全集时必须是「不知道」，不能是「不是好友」");

    // 子集（如 status=blocked）不足以把表变成「已知」：它只说了被提到的那几个人。
    [store ingestFriends:@[[self cardWithID:@"bob" status:IMFriendStatusAccepted]] authoritative:NO];
    XCTAssertEqualObjects([store friendStateForUser:@"bob"], @YES);
    XCTAssertNil([store friendStateForUser:@"dave"], @"子集没提到的人仍是「不知道」");
}

- (void)testAuthoritativeListResolvesBothDirections {
    IMFriendStateStore *store = [IMFriendStateStore new];
    [store ingestFriends:@[[self cardWithID:@"bob" status:IMFriendStatusAccepted],
                           [self cardWithID:@"carol" status:IMFriendStatusRequested]]
           authoritative:YES];
    XCTAssertEqualObjects([store friendStateForUser:@"bob"], @YES);
    XCTAssertEqualObjects([store friendStateForUser:@"carol"], @NO, @"待对方同意 ≠ 好友");
    XCTAssertEqualObjects([store friendStateForUser:@"dave"], @NO, @"喂过全集后，不在表里就是不是好友");
}

- (void)testAuthoritativeListReplacesInsteadOfMerging {
    // 删好友后那个 uid 只会"不出现在下一次全集里"。合并语义会让他永远留在表里，
    // 资料页照旧显示「消息/呼叫/视频」——正是要防的那条。
    IMFriendStateStore *store = [IMFriendStateStore new];
    [store ingestFriends:@[[self cardWithID:@"bob" status:IMFriendStatusAccepted]] authoritative:YES];
    XCTAssertEqualObjects([store friendStateForUser:@"bob"], @YES);

    [store ingestFriends:@[] authoritative:YES];
    XCTAssertEqualObjects([store friendStateForUser:@"bob"], @NO);
}

- (void)testSubsetDoesNotSweepUnmentionedFriends {
    IMFriendStateStore *store = [IMFriendStateStore new];
    [store ingestFriends:@[[self cardWithID:@"bob" status:IMFriendStatusAccepted],
                           [self cardWithID:@"carol" status:IMFriendStatusAccepted]]
           authoritative:YES];
    // status=blocked 这类子集只提到一部分人；若按全集清扫，会把没提到的好友一起误判成非好友。
    [store ingestFriends:@[[self cardWithID:@"bob" status:IMFriendStatusAccepted]] authoritative:NO];
    XCTAssertEqualObjects([store friendStateForUser:@"carol"], @YES, @"子集不得清扫未提及者");
}

#pragma mark - 本地快照播种（冷启动）

- (void)testEmptyLocalSnapshotStaysUnknown {
    IMFriendStateStore *store = [IMFriendStateStore new];
    // 空的本地快照可能只是"从没同步过"。据此判所有人非好友 → 冷启动把好友显示成陌生人。
    [store seedFromLocalSnapshot:@[]];
    XCTAssertNil([store friendStateForUser:@"bob"]);
}

- (void)testLocalSnapshotSeedsUnknownTableOnly {
    IMFriendStateStore *store = [IMFriendStateStore new];
    [store seedFromLocalSnapshot:@[[self cardWithID:@"bob" status:IMFriendStatusAccepted]]];
    XCTAssertEqualObjects([store friendStateForUser:@"bob"], @YES);
    XCTAssertEqualObjects([store friendStateForUser:@"dave"], @NO, @"快照是全集，播种后即为「已知」");

    // 网络全集更新（bob 已被删）后，过期的本地快照不得把他"救"回来。
    [store ingestFriends:@[] authoritative:YES];
    [store seedFromLocalSnapshot:@[[self cardWithID:@"bob" status:IMFriendStatusAccepted]]];
    XCTAssertEqualObjects([store friendStateForUser:@"bob"], @NO);
}

- (void)testBlankUserIDIsUnknown {
    IMFriendStateStore *store = [IMFriendStateStore new];
    [store ingestFriends:@[] authoritative:YES];
    XCTAssertNil([store friendStateForUser:@""]);
    XCTAssertNil([store friendStateForUser:nil]);
}

@end
