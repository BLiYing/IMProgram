//  IMCallHistoryRecordTests.m
//  设置 ▸ 最近通话：纯函数单测——未接判定 / 群通话人数 / 按日期分组 / 全部-未接过滤。
//  设计：IMServer docs/design/CALL_HISTORY_DESIGN.md §1/§3.5/§6。

#import <XCTest/XCTest.h>
#import "../IMProgram/Common/IMCallHistoryRecord.h"

@interface IMCallHistoryRecordTests : XCTestCase
@end

@implementation IMCallHistoryRecordTests

- (IMCallHistoryRecord *)recordWithCaller:(NSString *)caller duration:(NSInteger)duration startedAtMs:(int64_t)ms {
    IMCallHistoryRecord *r = [IMCallHistoryRecord new];
    r.callID = @"call-1";
    r.caller = caller;
    r.durationSec = duration;
    r.startedAtMs = ms;
    return r;
}

#pragma mark - 未接判定（设计文档 §1「未接判定」/ §6 测试点 2）

- (void)testMissedWhenCalleeAndZeroDuration {
    IMCallHistoryRecord *r = [self recordWithCaller:@"1003" duration:0 startedAtMs:1];
    XCTAssertTrue(IMCallHistoryRecordIsMissed(r, @"1001")); // 我=1001，主叫是对方，时长0 → 未接
}

- (void)testNotMissedWhenCallerAnyOutcome {
    IMCallHistoryRecord *r = [self recordWithCaller:@"1001" duration:0 startedAtMs:1];
    XCTAssertFalse(IMCallHistoryRecordIsMissed(r, @"1001")); // 我是主叫，任何结局都不算未接
    r.durationSec = 120;
    XCTAssertFalse(IMCallHistoryRecordIsMissed(r, @"1001"));
}

- (void)testNotMissedWhenCalleeButConnected {
    IMCallHistoryRecord *r = [self recordWithCaller:@"1003" duration:45 startedAtMs:1];
    XCTAssertFalse(IMCallHistoryRecordIsMissed(r, @"1001")); // 被叫已接通，不算未接
}

- (void)testMissedGuardsAgainstEmptySelfUID {
    IMCallHistoryRecord *r = [self recordWithCaller:@"1003" duration:0 startedAtMs:1];
    XCTAssertFalse(IMCallHistoryRecordIsMissed(r, nil));
    XCTAssertFalse(IMCallHistoryRecordIsMissed(r, @""));
}

#pragma mark - 单聊对方身份（设计文档 §6 测试点 3）

- (void)testPeerUIDWhenSelfIsCallee {
    IMCallHistoryRecord *r = [self recordWithCaller:@"1003" duration:9 startedAtMs:1];
    XCTAssertEqualObjects(IMCallHistoryRecordPeerUID(r, @"1001"), @"1003");
}

- (void)testPeerUIDWhenSelfIsCallerUsesMembers {
    IMCallHistoryRecord *r = [self recordWithCaller:@"1001" duration:9 startedAtMs:1];
    r.memberUIDs = @[@"1001", @"1003"];
    XCTAssertEqualObjects(IMCallHistoryRecordPeerUID(r, @"1001"), @"1003");
}

- (void)testPeerUIDMissingDataReturnsNilNotCrash {
    IMCallHistoryRecord *r = [self recordWithCaller:@"" duration:0 startedAtMs:1];
    r.memberUIDs = @[];
    XCTAssertNil(IMCallHistoryRecordPeerUID(r, @"1001"));
    XCTAssertNil(IMCallHistoryRecordPeerUID(nil, @"1001"));
}

#pragma mark - 群通话人数（设计文档 §1「群通话」/ §6 测试点 4）

- (void)testGroupPeerCountCallerNotInMembers {
    // members 不含发起人：5 个其他成员 + 发起人本人 = 6
    NSArray<NSString *> *members = @[@"1002", @"1003", @"1004", @"1005", @"1006"];
    XCTAssertEqual(IMCallHistoryGroupPeerCount(members, @"1001"), 6);
}

- (void)testGroupPeerCountCallerInMembers {
    // members 含发起人：结果应与「不含」时一致（同一通电话，两种服务端返回口径不该影响人数）
    NSArray<NSString *> *members = @[@"1001", @"1002", @"1003", @"1004", @"1005", @"1006"];
    XCTAssertEqual(IMCallHistoryGroupPeerCount(members, @"1001"), 6);
}

- (void)testGroupPeerCountEmptyMembersFallsBackToCallerOnly {
    XCTAssertEqual(IMCallHistoryGroupPeerCount(@[], @"1001"), 2); // max(0,1)=1 + 1（caller 不在空数组里）
    // callerUID 拿不到（脏数据）：函数不特殊降级，仍按「caller 不在 members 里」计（1 + 1 = 2）——
    // 比起悄悄退化成 1（=只有我自己），2 更不容易让人以为「这通电话没别人」。
    XCTAssertEqual(IMCallHistoryGroupPeerCount(@[], nil), 2);
}

#pragma mark - 按日期分组（设计文档 §2「按日期分组」/ §6 测试点 1）

- (void)testGroupByDateBucketsAndPreservesOrder {
    NSDate *now = NSDate.date;
    int64_t todayMs = (int64_t)(now.timeIntervalSince1970 * 1000);
    int64_t yesterdayMs = (int64_t)([now dateByAddingTimeInterval:-86400].timeIntervalSince1970 * 1000);

    IMCallHistoryRecord *a = [self recordWithCaller:@"1001" duration:1 startedAtMs:todayMs];
    IMCallHistoryRecord *b = [self recordWithCaller:@"1002" duration:1 startedAtMs:todayMs - 1000];
    IMCallHistoryRecord *c = [self recordWithCaller:@"1003" duration:1 startedAtMs:yesterdayMs];

    NSArray<IMCallHistorySection *> *sections = IMCallHistoryGroupByDate(@[a, b, c]);
    XCTAssertEqual(sections.count, 2u);
    XCTAssertEqualObjects(sections[0].records, (@[a, b])); // 同一天两条按输入顺序（已假定调用方倒序传入）保留
    XCTAssertEqual(sections[1].records.count, 1u);
    XCTAssertEqualObjects(sections[1].records.firstObject, c);
    XCTAssertNotEqualObjects(sections[0].title, sections[1].title);
}

- (void)testGroupByDateEmptyInput {
    XCTAssertEqual(IMCallHistoryGroupByDate(@[]).count, 0u);
}

#pragma mark - 全部 / 未接 过滤（设计文档 §3.5 / §6 测试点 7）

- (void)testApplyFilterAllReturnsEverythingUnordered {
    IMCallHistoryRecord *missed = [self recordWithCaller:@"1003" duration:0 startedAtMs:1];
    IMCallHistoryRecord *connected = [self recordWithCaller:@"1001" duration:9 startedAtMs:2];
    NSArray *all = @[missed, connected];
    XCTAssertEqualObjects(IMCallHistoryApplyFilter(all, IMCallHistoryFilterAll, @"1001"), all);
}

- (void)testApplyFilterMissedOnlyKeepsMissedInOrder {
    IMCallHistoryRecord *missed1 = [self recordWithCaller:@"1003" duration:0 startedAtMs:1];
    IMCallHistoryRecord *connected = [self recordWithCaller:@"1001" duration:9 startedAtMs:2];
    IMCallHistoryRecord *missed2 = [self recordWithCaller:@"1004" duration:0 startedAtMs:3];
    NSArray<IMCallHistoryRecord *> *filtered =
        IMCallHistoryApplyFilter(@[missed1, connected, missed2], IMCallHistoryFilterMissed, @"1001");
    XCTAssertEqualObjects(filtered, (@[missed1, missed2]));
}

@end
