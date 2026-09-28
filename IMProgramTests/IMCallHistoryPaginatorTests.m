//  IMCallHistoryPaginatorTests.m
//  设置 ▸ 最近通话：翻页/筛选状态机单测——用假 fetcher（同步或手动延迟回调）驱动，不碰网络/模拟器。
//  设计：IMServer docs/design/CALL_HISTORY_DESIGN.md §3（翻页/generation）/ §3.5（未接自动续页）/ §6 测试点 1、7。

#import <XCTest/XCTest.h>
#import "../IMProgram/Modules/Me/IMCallHistoryPaginator.h"

@interface IMCallHistoryPaginatorTests : XCTestCase
@end

@implementation IMCallHistoryPaginatorTests

- (IMCallHistoryRecord *)recordWithCaller:(NSString *)caller duration:(NSInteger)duration {
    IMCallHistoryRecord *r = [IMCallHistoryRecord new];
    r.callID = [NSString stringWithFormat:@"call-%p", r];
    r.caller = caller;
    r.durationSec = duration;
    r.startedAtMs = 1;
    return r;
}

#pragma mark - 基本翻页（同步假 fetcher）

- (void)testFirstPageReachesEndWhenCursorNil {
    IMCallHistoryRecord *a = [self recordWithCaller:@"1001" duration:9];
    IMCallHistoryFetchBlock fetcher = ^(id cursor, NSInteger limit, IMCallHistoryFetchCompletion completion) {
        XCTAssertNil(cursor);
        completion(@[a], nil, nil);
    };
    IMCallHistoryPaginator *p = [[IMCallHistoryPaginator alloc] initWithSelfUID:@"1001" pageSize:20 fetcher:fetcher];
    XCTestExpectation *exp = [self expectationWithDescription:@"reload"];
    [p reloadWithMinVisible:0 completion:^(NSError *error) {
        XCTAssertNil(error);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
    XCTAssertEqualObjects(p.allRecords, @[a]);
    XCTAssertTrue(p.reachedEnd);
    XCTAssertFalse(p.loading);
}

- (void)testLoadMoreNoOpWhenReachedEnd {
    IMCallHistoryFetchBlock fetcher = ^(id cursor, NSInteger limit, IMCallHistoryFetchCompletion completion) {
        completion(@[], nil, nil);
    };
    IMCallHistoryPaginator *p = [[IMCallHistoryPaginator alloc] initWithSelfUID:@"1001" pageSize:20 fetcher:fetcher];
    XCTestExpectation *exp1 = [self expectationWithDescription:@"reload"];
    [p reloadWithMinVisible:0 completion:^(NSError *error) { [exp1 fulfill]; }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
    XCTAssertTrue(p.reachedEnd);

    __block BOOL fetcherCalledAgain = NO;
    IMCallHistoryPaginator *p2 = [[IMCallHistoryPaginator alloc] initWithSelfUID:@"1001" pageSize:20
        fetcher:^(id cursor, NSInteger limit, IMCallHistoryFetchCompletion completion) {
            fetcherCalledAgain = YES;
            completion(@[], nil, nil);
        }];
    XCTestExpectation *exp2 = [self expectationWithDescription:@"reload2"];
    [p2 reloadWithMinVisible:0 completion:^(NSError *error) { [exp2 fulfill]; }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
    fetcherCalledAgain = NO;
    XCTestExpectation *exp3 = [self expectationWithDescription:@"loadMore noop"];
    [p2 loadMoreWithMinVisible:0 completion:^(NSError *error) {
        XCTAssertNil(error);
        [exp3 fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
    XCTAssertFalse(fetcherCalledAgain); // 已到底：loadMore 不应再发请求
}

#pragma mark - 「未接」自动续页（设计文档 §3.5）

- (void)testMissedFilterAutoContinuesUntilMinVisible {
    // 每页 5 条只有 1 条未接；minVisible=2 应自动翻到第 2 页凑够，第 2 页到底。
    NSMutableArray<NSArray<IMCallHistoryRecord *> *> *pages = [NSMutableArray array];
    NSMutableArray<IMCallHistoryRecord *> *page1 = [NSMutableArray array];
    for (int i = 0; i < 4; i++) { [page1 addObject:[self recordWithCaller:@"1001" duration:9]]; } // 主叫=自己，不算未接
    IMCallHistoryRecord *missed1 = [self recordWithCaller:@"1003" duration:0];
    [page1 addObject:missed1];
    [pages addObject:page1];

    NSMutableArray<IMCallHistoryRecord *> *page2 = [NSMutableArray array];
    for (int i = 0; i < 4; i++) { [page2 addObject:[self recordWithCaller:@"1001" duration:9]]; }
    IMCallHistoryRecord *missed2 = [self recordWithCaller:@"1004" duration:0];
    [page2 addObject:missed2];
    [pages addObject:page2];

    __block NSInteger callIndex = 0;
    IMCallHistoryFetchBlock fetcher = ^(id cursor, NSInteger limit, IMCallHistoryFetchCompletion completion) {
        NSArray<IMCallHistoryRecord *> *records = pages[(NSUInteger)callIndex];
        NSString *next = (callIndex == 0) ? @"cursor-2" : nil; // 第 2 页到底
        callIndex++;
        completion(records, next, nil);
    };
    IMCallHistoryPaginator *p = [[IMCallHistoryPaginator alloc] initWithSelfUID:@"1001" pageSize:5 fetcher:fetcher];
    p.filter = IMCallHistoryFilterMissed;

    XCTestExpectation *exp = [self expectationWithDescription:@"reload missed auto-continue"];
    [p reloadWithMinVisible:2 completion:^(NSError *error) {
        XCTAssertNil(error);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertEqual(callIndex, 2); // 两页都发了（自动续页）
    XCTAssertEqual(p.allRecords.count, 10u); // 未筛选：两页全部记录都保留
    XCTAssertEqualObjects(p.filteredRecords, (@[missed1, missed2]));
    XCTAssertTrue(p.reachedEnd);
}

- (void)testAllFilterDoesNotAutoContinue {
    // 「全部」视图即使一页数据是 0 条也只发一页，不自动续拉（自动续页只属于「未接」视图）。
    __block NSInteger callIndex = 0;
    IMCallHistoryFetchBlock fetcher = ^(id cursor, NSInteger limit, IMCallHistoryFetchCompletion completion) {
        callIndex++;
        completion(@[], @"still-more", nil); // 明明还有下一页
    };
    IMCallHistoryPaginator *p = [[IMCallHistoryPaginator alloc] initWithSelfUID:@"1001" pageSize:5 fetcher:fetcher];
    p.filter = IMCallHistoryFilterAll;
    XCTestExpectation *exp = [self expectationWithDescription:@"reload all no auto-continue"];
    [p reloadWithMinVisible:20 completion:^(NSError *error) { [exp fulfill]; }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
    XCTAssertEqual(callIndex, 1);
    XCTAssertFalse(p.reachedEnd);
}

#pragma mark - generation：旧翻页请求作废，不覆盖新首页数据（设计文档 §3 / §6 测试点 1）

- (void)testStaleReloadCompletionDoesNotOverwriteNewerData {
    NSMutableArray<IMCallHistoryFetchCompletion> *pending = [NSMutableArray array];
    IMCallHistoryFetchBlock fetcher = ^(id cursor, NSInteger limit, IMCallHistoryFetchCompletion completion) {
        [pending addObject:completion]; // 不立即回调，模拟仍在途的网络请求
    };
    IMCallHistoryPaginator *p = [[IMCallHistoryPaginator alloc] initWithSelfUID:@"1001" pageSize:20 fetcher:fetcher];

    __block BOOL staleCompletionFired = NO;
    [p reloadWithMinVisible:0 completion:^(NSError *error) { staleCompletionFired = YES; }];
    XCTAssertEqual(pending.count, 1u);

    __block BOOL freshCompletionFired = NO;
    [p reloadWithMinVisible:0 completion:^(NSError *error) { freshCompletionFired = YES; }]; // callEnd 刷新场景：作废第一次请求
    XCTAssertEqual(pending.count, 2u);

    // 旧请求（generation 1）迟到：不应覆盖状态、也不应触发它自己的 completion。
    IMCallHistoryRecord *staleRecord = [self recordWithCaller:@"9999" duration:0];
    pending[0](@[staleRecord], nil, nil);
    XCTAssertFalse(staleCompletionFired);
    XCTAssertEqual(p.allRecords.count, 0u);

    // 新请求（generation 2）到达：正常生效。
    IMCallHistoryRecord *freshRecord = [self recordWithCaller:@"1002" duration:0];
    pending[1](@[freshRecord], nil, nil);
    XCTAssertTrue(freshCompletionFired);
    XCTAssertEqualObjects(p.allRecords, @[freshRecord]);
    XCTAssertTrue(p.reachedEnd);
}

@end
