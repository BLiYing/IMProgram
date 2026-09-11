//  IMChatSearchPagingTests.m
//  会话内搜索服务端翻页的判据（IMChatSearchPaging）。
//
//  错法全是静默的：拼错位置 / 下标没挪 / 计数虚涨，界面都照常，只是 ▲ 跳到了别处。
//  与 im-web `src/searchPaging.test.ts` 同一组场景（IMServer/docs/SYMMETRY.md 登记）。

#import <XCTest/XCTest.h>

#import "IMChatSearchPaging.h"

@interface IMChatSearchPagingTests : XCTestCase
@end

@implementation IMChatSearchPagingTests

/// 服务端倒序的更旧一页 → 升序拼到前面；下标落到 added-1 正是紧挨着原最旧命中的上一条。
- (void)test_更旧一页拼到前面且下标落在紧挨着的那条 {
    NSInteger added = -1;
    NSArray *hits = IMChatSearchPrependOlderHits(@[@200, @250, @300], @[@150, @100], &added);
    XCTAssertEqualObjects(hits, (@[@100, @150, @200, @250, @300]));
    XCTAssertEqual(added, 2);
    XCTAssertEqualObjects(hits[(NSUInteger)(added - 1)], @150);
}

/// 重复页 / 游标回退带回的已有命中不再塞一遍——否则计数虚涨、下标错位。
- (void)test_重复页不再塞一遍 {
    NSInteger added = -1;
    NSArray *hits = IMChatSearchPrependOlderHits(@[@200, @250], @[@250, @200, @180], &added);
    XCTAssertEqualObjects(hits, (@[@180, @200, @250]));
    XCTAssertEqual(added, 1);
}

- (void)test_页内自己重复只算一条 {
    NSInteger added = -1;
    NSArray *hits = IMChatSearchPrependOlderHits(@[@200], @[@150, @150], &added);
    XCTAssertEqualObjects(hits, (@[@150, @200]));
    XCTAssertEqual(added, 1);
}

- (void)test_空页原样返回 {
    NSInteger added = -1;
    NSArray *hits = IMChatSearchPrependOlderHits(@[@200], @[], &added);
    XCTAssertEqualObjects(hits, (@[@200]));
    XCTAssertEqual(added, 0);
}

- (void)test_当前为空时整页都收 {
    NSInteger added = -1;
    NSArray *hits = IMChatSearchPrependOlderHits(@[], @[@30, @10, @20], &added);
    XCTAssertEqualObjects(hits, (@[@10, @20, @30]));
    XCTAssertEqual(added, 3);
}

/// **在最旧命中上、服务端还有更早的页 → ▲ 必须可点**：否则计数写着「50+」却永远翻不过去。
- (void)test_最旧命中上还有更多页时上一条可点 {
    XCTAssertTrue(IMChatSearchCanGoOlder(0, 50, YES, NO));
    XCTAssertFalse(IMChatSearchCanGoOlder(0, 50, NO, NO), @"真到头了就灰");
}

/// 一次「取更早」在途时灰掉：连点会发出多份同样的请求、把同一页拼两次。
- (void)test_在途时最旧命中上不可点 {
    XCTAssertFalse(IMChatSearchCanGoOlder(0, 50, YES, YES));
    XCTAssertTrue(IMChatSearchCanGoOlder(3, 50, YES, YES), @"不在最旧命中上照常可点，走本地已有的命中");
}

- (void)test_没有命中不可点 {
    XCTAssertFalse(IMChatSearchCanGoOlder(0, 0, YES, NO));
}

@end
