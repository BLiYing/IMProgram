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

/// 表头容器：搜索框整体左右偏位的修法（用户 2026-08-30 报的选好友页）。
/// 盯两点——① 容器一定要把宽度对齐**表格**，不是 view 的初始 bounds；② 宽度已一致时必须早退，
/// 否则 viewDidLayoutSubviews 里「改 frame → 触发布局 → 再改」会自激。
- (void)testHeaderSyncsWidthToTableAndIsIdempotent {
    UISearchBar *bar = IMListSearchBarMake(320, @"搜索好友", nil);
    UIView *header = IMListSearchHeaderMake(bar);
    UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 402, 800)];
    table.tableHeaderView = header;

    IMListSearchHeaderSyncWidth(header, table);
    XCTAssertEqual(CGRectGetWidth(header.frame), 402, @"表头宽度必须跟表格走，而不是建时那个 320");
    XCTAssertEqual(CGRectGetWidth(table.tableHeaderView.frame), 402);

    // 幂等：再调一次不该有任何变化（早退），也不该把 header 从表格上摘下来。
    IMListSearchHeaderSyncWidth(header, table);
    XCTAssertEqualObjects(table.tableHeaderView, header);
    XCTAssertEqual(CGRectGetWidth(header.frame), 402);

    // 搜索框由约束贴满容器宽度并垂直居中（居中才是「不偏」的定义）。
    [header layoutIfNeeded];
    XCTAssertEqual(CGRectGetWidth(bar.frame), 402);
    XCTAssertEqualWithAccuracy(CGRectGetMidY(bar.frame), CGRectGetMidY(header.bounds), 0.5);
}

- (void)testHeaderSyncIgnoresEmptyInputs {
    // 空参数/零宽表格（还没布局）不得崩，也不得把 header 尺寸改成 0。
    UISearchBar *bar = IMListSearchBarMake(320, @"搜索好友", nil);
    UIView *header = IMListSearchHeaderMake(bar);
    UITableView *zero = [[UITableView alloc] initWithFrame:CGRectZero];
    IMListSearchHeaderSyncWidth(header, nil);
    IMListSearchHeaderSyncWidth(nil, zero);
    IMListSearchHeaderSyncWidth(header, zero);
    XCTAssertEqual(CGRectGetWidth(header.frame), 320);
}

@end
