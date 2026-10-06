#import <XCTest/XCTest.h>
#import "IMFriendPickerSelectAll.h"

/// 建群选人页全选口径（CREATE_GROUP_SELECT_ALL_DESIGN.md §0）。
@interface IMFriendPickerSelectAllTests : XCTestCase
@end

@implementation IMFriendPickerSelectAllTests

- (void)testNoSearchSelectsAllVisible {
    NSArray *v = @[@"a", @"b", @"c"];
    XCTAssertEqualObjects(IMFriendPickerNextSelection(@[], v, 0), v);
}

- (void)testSearchOnlySelectsVisible {
    // 全集 a..e，搜索后可见 b、d：只补这两个
    XCTAssertEqualObjects(IMFriendPickerNextSelection(@[], @[@"b", @"d"], 0), (@[@"b", @"d"]));
}

- (void)testKeepsExistingSelectionIncludingInvisible {
    NSArray *r = IMFriendPickerNextSelection(@[@"x", @"b"], @[@"a", @"b", @"c"], 0);
    XCTAssertEqualObjects(r, (@[@"x", @"b", @"a", @"c"]));
}

- (void)testLimitTruncatesInVisibleOrder {
    NSArray *r = IMFriendPickerNextSelection(@[@"x"], @[@"a", @"b", @"c", @"d"], 3);
    XCTAssertEqualObjects(r, (@[@"x", @"a", @"b"]));
    // 已选已达上限：不补也不清
    XCTAssertEqualObjects(IMFriendPickerNextSelection(@[@"x", @"y"], @[@"a"], 2), (@[@"x", @"y"]));
}

- (void)testAllVisibleSelectedThenDeselectOnlyVisible {
    NSArray *sel = @[@"x", @"a", @"b"];
    NSArray *vis = @[@"a", @"b"];
    XCTAssertTrue(IMFriendPickerAllVisibleSelected(sel, vis));
    XCTAssertFalse(IMFriendPickerAllVisibleSelected(@[@"a"], vis));
    XCTAssertEqualObjects(IMFriendPickerDeselectVisible(sel, vis), (@[@"x"]));
}

- (void)testNoVisibleRows {
    XCTAssertFalse(IMFriendPickerAllVisibleSelected(@[@"a"], @[]));
    XCTAssertEqualObjects(IMFriendPickerNextSelection(@[@"a"], @[], 5), (@[@"a"]));
    XCTAssertEqualObjects(IMFriendPickerDeselectVisible(@[@"a"], @[]), (@[@"a"]));
}

@end
