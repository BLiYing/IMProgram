//  IMScopedSearchTests.m
//  底部搜索 tab 分域匹配规则（「我」设置项 / 通讯录联系人+群聊共用的子串匹配）。

#import <XCTest/XCTest.h>
#import "IMScopedSearch.h"
#import "IMGroupInfo.h"

@interface IMScopedSearchTests : XCTestCase
@end

@implementation IMScopedSearchTests

- (NSArray<IMSettingsSearchEntry *> *)entries {
    return @[
        [IMSettingsSearchEntry entryWithId:@"recentCalls" title:@"最近通话" systemImage:nil],
        [IMSettingsSearchEntry entryWithId:@"notifications" title:@"通知与声音" systemImage:nil],
        [IMSettingsSearchEntry entryWithId:@"language" title:@"Language 语言" systemImage:nil],
    ];
}

- (void)testEmptyOrBlankKeywordMatchesNothing {
    XCTAssertEqual(IMSettingsSearchFilter(self.entries, @"").count, 0u);
    XCTAssertEqual(IMSettingsSearchFilter(self.entries, @"   ").count, 0u);
    XCTAssertEqual(IMSettingsSearchFilter(self.entries, nil).count, 0u);
}

- (void)testSubstringHitKeepsOrder {
    NSArray *hits = IMSettingsSearchFilter(self.entries, @"通");
    XCTAssertEqual(hits.count, 2u);
    XCTAssertEqualObjects([hits[0] rowId], @"recentCalls");
    XCTAssertEqualObjects([hits[1] rowId], @"notifications");
}

- (void)testCaseInsensitiveAndTrimmed {
    NSArray *hits = IMSettingsSearchFilter(self.entries, @"  LANGUAGE ");
    XCTAssertEqual(hits.count, 1u);
    XCTAssertEqualObjects([hits[0] rowId], @"language");
}

- (void)testNoHit {
    XCTAssertEqual(IMSettingsSearchFilter(self.entries, @"zzz").count, 0u);
}

- (void)testMatchesAnyField {
    XCTAssertTrue(IMScopedSearchMatches(@"ali", @[@"", @"Alice", @"备注"]));
    XCTAssertTrue(IMScopedSearchMatches(@"备", @[@"", @"Alice", @"备注"]));
    XCTAssertFalse(IMScopedSearchMatches(@"bob", @[@"Alice"]));
    XCTAssertFalse(IMScopedSearchMatches(@"", @[@"Alice"]));
}

- (IMGroupInfo *)groupID:(NSString *)gid name:(NSString *)name {
    IMGroupInfo *g = [IMGroupInfo new];
    g.convID = gid; g.name = name;
    return g;
}

/// 范围是完整群列表：没有会话行的群也要命中（传入的只是群列表，与会话无关）。
- (void)testGroupHitsComeFromFullGroupList {
    NSArray *groups = @[[self groupID:@"g_1" name:@"项目群"], [self groupID:@"g_2" name:@"午饭群"], [self groupID:@"g_3" name:@"项目二组"]];
    NSArray<IMGroupInfo *> *hits = IMScopedGroupHits(groups, @" 项目 ", @"群聊");
    XCTAssertEqual(hits.count, 2u);
    XCTAssertEqualObjects(hits[0].convID, @"g_1");
    XCTAssertEqualObjects(hits[1].convID, @"g_3");
}

- (void)testGroupHitsEmptyKeywordOrListMatchNothing {
    NSArray *groups = @[[self groupID:@"g_1" name:@"项目群"]];
    XCTAssertEqual(IMScopedGroupHits(groups, @"  ", @"群聊").count, 0u);
    XCTAssertEqual(IMScopedGroupHits(groups, nil, @"群聊").count, 0u);
    XCTAssertEqual(IMScopedGroupHits(nil, @"项目", @"群聊").count, 0u);
    XCTAssertEqual(IMScopedGroupHits(@[], @"项目", @"群聊").count, 0u);
}

- (void)testGroupHitsCaseInsensitiveAndEmptyNameUsesFallback {
    NSArray *groups = @[[self groupID:@"g_1" name:@"iOS Team"], [self groupID:@"g_2" name:@""]];
    XCTAssertEqual(IMScopedGroupHits(groups, @"ios", @"群聊").count, 1u);
    NSArray<IMGroupInfo *> *hits = IMScopedGroupHits(groups, @"群聊", @"群聊");
    XCTAssertEqual(hits.count, 1u);
    XCTAssertEqualObjects(hits[0].convID, @"g_2");
}

@end
