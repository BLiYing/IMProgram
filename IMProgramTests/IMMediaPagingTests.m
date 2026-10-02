//  IMMediaPagingTests.m
//  会话媒体服务端续拉的判据（IMMediaPaging）。对称 Android `ConvQueryFloorTest` / `MediaTimeline.prependOlder`、
//  Web `fetchConvMedia` 的位点过滤。拼错的表现是翻页时跳到别的图上或同一张出现两次，界面照常不报错。

#import <XCTest/XCTest.h>

#import "IMMediaPaging.h"
#import "IMMessageModel.h"

@interface IMMediaPagingTests : XCTestCase
@end

@implementation IMMediaPagingTests

static IMMessageModel *M(int64_t seq) {
    IMMessageModel *m = [IMMessageModel new];
    m.convSeq = seq; m.content = [NSString stringWithFormat:@"/uploads/%lld.jpg", seq]; m.contentType = @"image";
    return m;
}

static NSArray<NSNumber *> *Seqs(NSArray<IMMessageModel *> *ms) {
    NSMutableArray *o = [NSMutableArray array];
    for (IMMessageModel *m in ms) { [o addObject:@(m.convSeq)]; }
    return o;
}

/// 服务端倒序的更旧一页 → 升序拼到前面；added 用来把正在看的下标后移。
- (void)test_更旧一页拼到前面且升序 {
    NSInteger added = -1;
    NSArray *r = IMMediaPagingPrependOlder(@[M(200), M(300)], @[M(150), M(100)], 0, &added);
    XCTAssertEqualObjects(Seqs(r), (@[@100, @150, @200, @300]));
    XCTAssertEqual(added, 2);
}

/// 重复页 / 游标回退带回的已有项不再塞一遍。
- (void)test_重复页不再塞一遍 {
    NSInteger added = -1;
    NSArray *r = IMMediaPagingPrependOlder(@[M(200), M(300)], @[M(300), M(200), M(180)], 0, &added);
    XCTAssertEqualObjects(Seqs(r), (@[@180, @200, @300]));
    XCTAssertEqual(added, 1);
}

/// 清空位点以内的丢掉——否则媒体库里翻得出刚清掉的图。
- (void)test_清空位点以内的丢掉 {
    NSInteger added = -1;
    NSArray *r = IMMediaPagingPrependOlder(@[M(200)], @[M(150), M(50)], 100, &added);
    XCTAssertEqualObjects(Seqs(r), (@[@150, @200]));
    XCTAssertEqual(added, 1);
}

/// 撤回 / 空内容的不进时间线。
- (void)test_撤回与空内容不进时间线 {
    IMMessageModel *recalled = M(150); recalled.recalledAt = 1;
    IMMessageModel *blank = M(140); blank.content = @"";
    NSInteger added = -1;
    NSArray *r = IMMediaPagingPrependOlder(@[M(200)], @[recalled, blank, M(130)], 0, &added);
    XCTAssertEqualObjects(Seqs(r), (@[@130, @200]));
    XCTAssertEqual(added, 1);
}

/// 时间线为空（服务端模式首屏）：整页都算新增。
- (void)test_空时间线整页新增 {
    NSInteger added = -1;
    NSArray *r = IMMediaPagingPrependOlder(@[], @[M(5), M(3)], 0, &added);
    XCTAssertEqualObjects(Seqs(r), (@[@3, @5]));
    XCTAssertEqual(added, 2);
}

/// 向更新方向：只收比当前最新还新的、去重的，升序拼到后面；撤回 / 位点以内的不收。
- (void)test_更新一页拼到后面且升序只收更新的 {
    NSInteger added = -1;
    NSArray *r = IMMediaPagingAppendNewer(@[M(100), M(200)], @[M(300), M(250), M(200), M(150)], 0, &added);
    XCTAssertEqualObjects(Seqs(r), (@[@100, @200, @250, @300]));
    XCTAssertEqual(added, 2);
}

- (void)test_更新一页重复撤回与位点以内不收 {
    IMMessageModel *recalled = M(260); recalled.recalledAt = 1;
    NSInteger added = -1;
    NSArray *r = IMMediaPagingAppendNewer(@[M(200)], @[M(250), M(250), recalled, M(40)], 300, &added);
    XCTAssertEqualObjects(Seqs(r), (@[@200]));   // 250 在位点 300 以内、260 已撤回、40 更旧
    XCTAssertEqual(added, 0);
    r = IMMediaPagingAppendNewer(@[M(200)], @[M(250), M(250), recalled], 0, &added);
    XCTAssertEqualObjects(Seqs(r), (@[@200, @250]));
    XCTAssertEqual(added, 1);
}

/// 游标落到「位点 + 1」及以下就别再翻（剩下的全在位点以内）。
- (void)test_游标落到位点之内不再翻 {
    XCTAssertFalse(IMMediaPagingHasMore(YES, 101, 100));
    XCTAssertTrue(IMMediaPagingHasMore(YES, 102, 100));
    XCTAssertFalse(IMMediaPagingHasMore(NO, 500, 100));
    XCTAssertFalse(IMMediaPagingHasMore(YES, 0, 0));   // 游标 0 再翻会回到最新页
    XCTAssertTrue(IMMediaPagingHasMore(YES, 50, 0));
}

@end
