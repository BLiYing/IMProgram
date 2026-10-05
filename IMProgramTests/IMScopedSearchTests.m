//  IMScopedSearchTests.m
//  底部搜索 tab 分域匹配规则（「我」设置项 / 通讯录联系人+群聊共用的子串匹配）。

#import <XCTest/XCTest.h>
#import "IMScopedSearch.h"

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

@end
