#import <XCTest/XCTest.h>

#import "IMListSearch.h"

/// 列表页搜索的统一匹配口径。三处列表（转发选择 / 选好友（建群·邀请）/ @提及面板）共用，
/// 口径漂了会同时影响三个页面，故在这里一次性锁住。与 Web `src/listSearch.ts` 同语义。
@interface IMListSearchTests : XCTestCase
@end

@implementation IMListSearchTests

- (void)testNormalizedQueryTrimsWhitespace {
    XCTAssertEqualObjects(IMListSearchNormalizedQuery(@"  abc "), @"abc");
    XCTAssertEqualObjects(IMListSearchNormalizedQuery(@"   "), @"", @"全空白 = 没在搜");
    XCTAssertEqualObjects(IMListSearchNormalizedQuery(nil), @"");
}

- (void)testMatchesAnyFieldCaseInsensitively {
    NSArray *fields = @[@"Alice", @"1001"];
    XCTAssertTrue(IMListSearchMatches(@"li", fields));
    XCTAssertTrue(IMListSearchMatches(@"LI", fields), @"大小写不敏感");
    XCTAssertTrue(IMListSearchMatches(@"1001", fields), @"uid 也参与匹配");
    XCTAssertFalse(IMListSearchMatches(@"zzz", fields));
}

- (void)testEmptyQueryMatchesEverything {
    // 空查询恒命中，调用方据此可以不写分支（各页仍会早退用全量列表，省一次遍历）。
    XCTAssertTrue(IMListSearchMatches(@"", @[@"Alice"]));
    XCTAssertTrue(IMListSearchMatches(@"  ", @[@"Alice"]));
    XCTAssertTrue(IMListSearchMatches(nil, @[@"Alice"]));
}

- (void)testEmptyAndNonStringFieldsAreSkipped {
    // 字段允许空/脏值：不能因为"空串包含任何东西"之类的取巧写法让所有人命中。
    XCTAssertFalse(IMListSearchMatches(@"a", @[@"", @"  "]));
    XCTAssertTrue(IMListSearchMatches(@"a", @[@"", @"Alice"]));
    XCTAssertFalse(IMListSearchMatches(@"a", (NSArray *)@[@42]), @"非字符串字段跳过而非崩溃");
}

- (void)testChineseSubstringMatchesButPinyinDoesNot {
    NSArray *fields = @[@"王小二", @"老王", @"1001"]; // 昵称 / 我给他起的备注 / uid
    XCTAssertTrue(IMListSearchMatches(@"老王", fields), @"备注可作为字段传入参与匹配（纯本地）");
    XCTAssertFalse(IMListSearchMatches(@"lw", fields), @"拼音首字母需额外索引，本期明确不做");
}

- (void)testSearchBarUsesSharedAppearance {
    UISearchBar *bar = IMListSearchBarMake(320, @"搜索好友", nil);
    XCTAssertEqualObjects(bar.placeholder, @"搜索好友");
    XCTAssertEqual(bar.searchBarStyle, UISearchBarStyleMinimal);
    // 搜 uid 时别被输入法首字母大写改坏（"1001" 无所谓，但英文 uid 会）。
    XCTAssertEqual(bar.autocapitalizationType, UITextAutocapitalizationTypeNone);
    XCTAssertEqual(bar.autocorrectionType, UITextAutocorrectionTypeNo);
}

@end
