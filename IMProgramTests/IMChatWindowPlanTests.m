//  IMChatWindowPlanTests.m
//  上滚取数分流的判据（IMChatWindowPlan）+ 可见下界簿记（IMBacklogTracker）。
//
//  这一组的错法全是**静默**的：判错了界面照常渲染，只是要么上滑永远不动、要么每次上滑都空跑
//  一次注定回空页的请求。所以按"会怎么错"钉，不按"接口长什么样"钉——每条用例的名字就是那个错法。
//  与 im-web `src/windowPlan.test.ts` 同一组场景（IMServer/docs/SYMMETRY.md 登记）。

#import <XCTest/XCTest.h>

#import "IMBacklogTracker.h"
#import "IMChatWindowPlan.h"

@interface IMChatWindowPlanTests : XCTestCase
@end

@implementation IMChatWindowPlanTests

#pragma mark - 可见下界记在哪一条上

/// 正常一窗：下界就是本窗最小的那个 conv_seq。
- (void)test_下界取本窗最小位点 {
    XCTAssertEqual(IMChatFloorFromWindow(500, 620), 500);
    XCTAssertEqual(IMChatFloorFromWindow(1, 1), 1);
}

/// 整窗一条真消息都没有（全是 msg_op 事件行 / 墓碑，它们占号但不成为气泡）→ 退回锚点。
/// 那同样断言了"anchor 之下没有"，不能因为窗空就把下界丢了——丢了就等于"未知"，
/// 于是上滑又会去空问一次。
- (void)test_空窗退回锚点 {
    XCTAssertEqual(IMChatFloorFromWindow(0, 620), 620);
    XCTAssertEqual(IMChatFloorFromWindow(0, 0), 0);      // 两个都没有 → 只能是未知
    XCTAssertEqual(IMChatFloorFromWindow(0, -5), 0);     // 负锚点不是位点
}

#pragma mark - 两次下界怎么合并

/// **只往小里收**。往大里收会把已经证实存在的更早内容挡在外面——那是"少给用户看东西"。
- (void)test_下界只往小里收 {
    XCTAssertEqual(IMChatMergeHistoryFloor(500, 200), 200);
    XCTAssertEqual(IMChatMergeHistoryFloor(200, 500), 200);   // 后来的更大 → 不理它
}

/// 任一侧未知（0）取另一侧；都未知仍是未知。
- (void)test_下界未知时取另一侧 {
    XCTAssertEqual(IMChatMergeHistoryFloor(0, 500), 500);
    XCTAssertEqual(IMChatMergeHistoryFloor(500, 0), 500);
    XCTAssertEqual(IMChatMergeHistoryFloor(0, 0), 0);
}

#pragma mark - 上沿踩没踩到下界

- (void)test_踩到下界就别再问了 {
    XCTAssertTrue(IMChatAtHistoryFloor(500, 500));    // 正好踩上
    XCTAssertTrue(IMChatAtHistoryFloor(500, 480));    // 比下界还早（跳转进旧岛后可能出现）
    XCTAssertFalse(IMChatAtHistoryFloor(500, 501));   // 还在下界之上 → 还能往上要
}

/// **下界未知恒 NO**。不知道就去问，不能靠猜把用户的历史封死——
/// 判成"到底了"是无声的错（上滑永远不动），比多问一次严重得多。
- (void)test_下界未知时不许认定到底 {
    XCTAssertFalse(IMChatAtHistoryFloor(0, 1000));
    XCTAssertFalse(IMChatAtHistoryFloor(-1, 1000));
}

#pragma mark - 上滚总闸

/// 这是本轮 C3 iOS 要修的那条：`earliest != 1` 对**入群前历史不可见的新成员恒真**
/// （他能看到的最早一条是 500 而不是 1），于是每次滚到顶都再问一次服务端、每次都得到
/// "没有了"——永远不收敛的空转。叠上服务端说过的下界之后才会停。
- (void)test_新成员滚到自己的可见下界后要停 {
    // 服务端还没表过态：只能按老判据放行去问（宁可多问一次）。
    XCTAssertTrue(IMChatWindowHasMoreAbove(500, 0));
    // 服务端回过 has_before=false、下界记成 500 之后：同一个上沿就不该再问了。
    XCTAssertFalse(IMChatWindowHasMoreAbove(500, 500));
}

/// conv_seq 从 1 起，1 号之上确定没有——这一条与下界无关，恒 NO。
- (void)test_上沿是1就到顶了 {
    XCTAssertFalse(IMChatWindowHasMoreAbove(1, 0));
    XCTAssertFalse(IMChatWindowHasMoreAbove(1, 500));
}

/// 窗口里全是待发消息（conv_seq==0）：没有可作边界的位点，不能拿 0 去问服务端。
- (void)test_窗口里没有已上号消息时不发请求 {
    XCTAssertFalse(IMChatWindowHasMoreAbove(0, 0));
    XCTAssertFalse(IMChatWindowHasMoreAbove(-1, 0));
}

/// 下界之上照常放行——别把闸修成"记过下界就再也不往上要了"。
- (void)test_下界之上仍放行 {
    XCTAssertTrue(IMChatWindowHasMoreAbove(9820, 500));
}

#pragma mark - 簿记：下界记在会话上，不是记在窗口上

/// 换窗不该把它忘掉。忘掉的表现是每次滚到顶都再问一次服务端、每次都得到"没有了"。
- (void)test_下界按会话记且只往小里收 {
    IMBacklogTracker *t = [IMBacklogTracker new];
    XCTAssertEqual([t historyFloorForConv:@"c1"], 0);   // 未知

    [t noteHistoryFloor:500 forConv:@"c1"];
    XCTAssertEqual([t historyFloorForConv:@"c1"], 500);

    [t noteHistoryFloor:900 forConv:@"c1"];             // 从旧岛顶部报上来的更大值：不理它
    XCTAssertEqual([t historyFloorForConv:@"c1"], 500);

    [t noteHistoryFloor:120 forConv:@"c1"];             // 更早的证据：收窄
    XCTAssertEqual([t historyFloorForConv:@"c1"], 120);

    XCTAssertEqual([t historyFloorForConv:@"c2"], 0);   // 会话之间不串
}

/// 无效输入不许污染簿记（空会话 id / 非正位点）。
- (void)test_下界拒绝无效输入 {
    IMBacklogTracker *t = [IMBacklogTracker new];
    [t noteHistoryFloor:500 forConv:@""];
    XCTAssertEqual([t historyFloorForConv:@""], 0);

    [t noteHistoryFloor:0 forConv:@"c1"];
    [t noteHistoryFloor:-3 forConv:@"c1"];
    XCTAssertEqual([t historyFloorForConv:@"c1"], 0);
}

/// 切账号 / 断开必须清干净：同一个 conv_id 在两个账号下可见范围不同，串了就是错的
/// （与 head / 缺口标记同一条理由）。
- (void)test_reset清掉下界 {
    IMBacklogTracker *t = [IMBacklogTracker new];
    [t noteHistoryFloor:500 forConv:@"c1"];
    [t reset];
    XCTAssertEqual([t historyFloorForConv:@"c1"], 0);
}

@end
