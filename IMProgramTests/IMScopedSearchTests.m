//  IMScopedSearchTests.m
//  搜索分域匹配规则（通讯录联系人+群聊共用的 trim + 大小写不敏感子串匹配）。设置项另见 IMSettingsSearchRegistryTests。

#import <XCTest/XCTest.h>
#import "IMScopedSearch.h"
#import "IMGroupInfo.h"

@interface IMScopedSearchTests : XCTestCase
@end

@implementation IMScopedSearchTests

- (void)testNormalizeTrimsWhitespaceAndNil {
    XCTAssertEqualObjects(IMScopedSearchNormalize(@"  ab \n"), @"ab");
    XCTAssertEqualObjects(IMScopedSearchNormalize(nil), @"");
}

- (void)testCaseInsensitiveAndTrimmed {
    XCTAssertTrue(IMScopedSearchMatches(@"  LANGUAGE ", @[@"Language 语言"]));
    XCTAssertFalse(IMScopedSearchMatches(@"zzz", @[@"Language 语言"]));
    XCTAssertFalse(IMScopedSearchMatches(@"   ", @[@"Language 语言"]));
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
