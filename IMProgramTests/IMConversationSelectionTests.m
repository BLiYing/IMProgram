//  IMConversationSelectionTests.m
//  会话列表编辑模式选择集（读三端共用向量 IMServer/docs/conformance/conv_selection.json）+ 有界并发批量执行器。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMConversationSelection.h"
#import "../IMProgram/Common/IMBatchRunner.h"
#import "../IMProgram/Models/IMConversation.h"

@interface IMConversationSelectionTests : XCTestCase
@end

@implementation IMConversationSelectionTests

- (NSDictionary *)vectors {
    NSString *repo = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString *path = [[repo stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"IMServer/docs/conformance/conv_selection.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"找不到共用向量 %@", path);
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : @{};
}

- (IMConversation *)conv:(NSDictionary *)d {
    IMConversation *c = [IMConversation new];
    c.convID = d[@"id"];
    c.unread = [d[@"unread"] integerValue];
    c.markedUnread = [d[@"marked"] boolValue];
    return c;
}

- (void)testHasUnreadVectors {
    NSArray *cases = [self vectors][@"has_unread"];
    XCTAssertGreaterThanOrEqual(cases.count, 4u);
    for (NSDictionary *c in cases) {
        IMConversation *conv = [self conv:@{ @"id": @"x", @"unread": c[@"unread"], @"marked": c[@"marked"] }];
        XCTAssertEqual([IMConversationSelection conversationHasUnread:conv], [c[@"expect"] boolValue], @"%@", c[@"name"]);
    }
}

- (void)testScenarioVectors {
    NSArray *scenarios = [self vectors][@"scenarios"];
    XCTAssertGreaterThanOrEqual(scenarios.count, 9u);
    for (NSDictionary *s in scenarios) {
        NSMutableArray<IMConversation *> *list = [NSMutableArray array];
        for (NSDictionary *d in s[@"convs"]) { [list addObject:[self conv:d]]; }
        IMConversationSelection *sel = [IMConversationSelection new];
        for (NSArray *op in s[@"ops"]) {
            NSString *name = op[0];
            if ([name isEqualToString:@"toggle"]) { [sel toggle:op[1]]; }
            else if ([name isEqualToString:@"select_all"]) { [sel selectAllIn:list]; }
            else if ([name isEqualToString:@"clear"]) { [sel clear]; }
            else if ([name isEqualToString:@"prune"]) {
                NSArray *keep = op[1];
                NSMutableArray *next = [NSMutableArray array];
                for (IMConversation *c in list) { if ([keep containsObject:c.convID]) { [next addObject:c]; } }
                list = next;
                [sel pruneToExistingIn:list];
            } else { XCTFail(@"未知 op %@", name); }
        }
        NSDictionary *expect = s[@"expect"];
        NSArray *ids = [sel.selectedIDs.allObjects sortedArrayUsingSelector:@selector(compare:)];
        XCTAssertEqualObjects(ids, expect[@"ids"], @"%@", s[@"name"]);
        XCTAssertEqual([sel isAllSelectedIn:list], [expect[@"all_selected"] boolValue], @"%@ all_selected", s[@"name"]);
        XCTAssertEqual([sel hasUnreadIn:list], [expect[@"has_unread"] boolValue], @"%@ has_unread", s[@"name"]);
    }
}

- (void)testSelectedConversationsKeepListOrder {
    IMConversation *a = [self conv:@{ @"id": @"a", @"unread": @0, @"marked": @NO }];
    IMConversation *b = [self conv:@{ @"id": @"b", @"unread": @0, @"marked": @NO }];
    IMConversation *c = [self conv:@{ @"id": @"c", @"unread": @0, @"marked": @NO }];
    IMConversationSelection *sel = [IMConversationSelection new];
    [sel select:@"c"]; [sel select:@"a"];
    XCTAssertEqualObjects([sel selectedConversationsIn:(@[a, b, c])], (@[a, c]));
}

#pragma mark - IMBatchRunner

- (void)testBatchRunnerBoundsConcurrencyAndSplitsResults {
    NSMutableArray *items = [NSMutableArray array];
    for (int i = 0; i < 10; i++) { [items addObject:@(i)]; }
    __block NSUInteger inflight = 0, peak = 0;
    XCTestExpectation *ex = [self expectationWithDescription:@"batch done"];
    [IMBatchRunner forEach:items concurrency:3
        work:^(NSNumber *item, void (^done)(NSError *)) {
            inflight++; peak = MAX(peak, inflight);
            dispatch_async(dispatch_get_main_queue(), ^{
                inflight--;
                done(item.intValue % 4 == 0 ? [NSError errorWithDomain:@"t" code:1 userInfo:nil] : nil);
            });
        }
        completion:^(NSArray *ok, NSArray *bad) {
            XCTAssertEqual(ok.count + bad.count, 10u);
            XCTAssertEqualObjects(bad, (@[@0, @4, @8]));
            XCTAssertLessThanOrEqual(peak, 3u);
            XCTAssertGreaterThan(peak, 1u);
            [ex fulfill];
        }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testBatchRunnerSynchronousDoneAndEmpty {
    __block BOOL called = NO;
    [IMBatchRunner forEach:@[] concurrency:4 work:^(id i, void (^d)(NSError *e)) { d(nil); }
        completion:^(NSArray *ok, NSArray *bad) { called = YES; XCTAssertEqual(ok.count + bad.count, 0u); }];
    XCTAssertTrue(called);
    called = NO;
    [IMBatchRunner forEach:@[@1, @2, @3, @4, @5] concurrency:2
        work:^(id i, void (^d)(NSError *e)) { d(nil); d(nil); } // 同步完成 + 重复调用 done 只算一次
        completion:^(NSArray *ok, NSArray *bad) { called = YES; XCTAssertEqual(ok.count, 5u); XCTAssertEqual(bad.count, 0u); }];
    XCTAssertTrue(called);
}

@end
