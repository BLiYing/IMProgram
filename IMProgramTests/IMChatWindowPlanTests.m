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

/// 正常一窗：下界＝**客户端留下来的那批行**里最小的那个 conv_seq（不是整窗最小，见下一条）。
- (void)test_下界取留下来的行的最小位点 {
    XCTAssertEqual(IMChatFloorFromWindow(500, 620), 500);
    XCTAssertEqual(IMChatFloorFromWindow(1, 1), 1);
}

/// **下界必须落在"页面真能渲染出来的号"上**（2026-09-10 /code-review，两端同一个洞）。
/// 会话最早一条 seq=1 被「为所有人删除」、最早的真实消息是 seq=2：`window_resp` 里那条墓碑
/// 照样回给客户端（服务端 LoadBefore 只过滤 conv_seq>0），但客户端当场把它删掉。
/// 若拿**整窗**最小 seq（=1）当下界，而上沿只数真实消息（恒 2），`2<=1` 永假 →
/// 每次滑到顶都再空问一次，**永不收敛**——比改造前还糟（改造前赋 has_before 一次就收敛）。
- (void)test_下界不能落在被丢掉的墓碑上 {
    // 传进来的必须是"留下来的行"的最小 seq，不是整窗最小 seq。
    XCTAssertEqual(IMChatFloorFromWindow(2, 0), 2);
    XCTAssertTrue(IMChatAtHistoryFloor(2, 2), @"上沿=2、下界=2 → 该停");
}

/// 整窗一条真消息都没有（全是 msg_op 事件行 / 墓碑，它们占号但不成为气泡）→ 退回锚点。
/// 那同样断言了"anchor 之下没有"，不能因为窗空就把下界丢了——丢了就等于"未知"，
/// 于是上滑又会去空问一次。锚点正是请求方当时的上沿，比得上、能收敛。
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

/// 粗闸只管"到没到 conv_seq 1"。
- (void)test_上沿是1就到顶了 {
    XCTAssertFalse(IMChatWindowHasMoreAbove(1));
    XCTAssertTrue(IMChatWindowHasMoreAbove(2));
    XCTAssertTrue(IMChatWindowHasMoreAbove(9820));
}

/// 窗口里全是待发消息（conv_seq==0）：没有可作边界的位点，不能拿 0 去问服务端。
- (void)test_窗口里没有已上号消息时不发请求 {
    XCTAssertFalse(IMChatWindowHasMoreAbove(0));
    XCTAssertFalse(IMChatWindowHasMoreAbove(-1));
}

/// **下界不能并进粗闸**（2026-09-10 /code-review）：iOS 的 hasMoreAbove 是本地展开与服务端
/// 请求共用的一道闸，并进去会连本地已经存着的更早历史一起挡掉——成员退群再入群会抬高
/// `join_conv_seq`，而入群前下载过的行仍在本地库里，用户跳进那一段往上滑就展不出来了。
/// 粗闸对下界必须**无感**；下界只在 loadOlderPage 准备问服务端那一步生效。
- (void)test_粗闸不受下界影响 {
    XCTAssertTrue(IMChatWindowHasMoreAbove(300), @"本地存着 300、下界在 500：粗闸仍须放行，交给本地展开");
}

/// 入群前历史不可见的新成员：`oldest > 1` 对他恒真，只有服务端说过的下界能让上滑停下来。
/// 这一条判的是**请求那一步**用的判据（loadOlderPage 里那句），不是粗闸。
- (void)test_新成员滚到自己的可见下界后不再问服务端 {
    XCTAssertFalse(IMChatAtHistoryFloor(0, 500), @"服务端没表过态 → 去问（宁可多问一次）");
    XCTAssertTrue(IMChatAtHistoryFloor(500, 500), @"服务端说过 500 之下没有 → 别再空问");
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

/// **每次连上都要清下界**（2026-09-10 /code-review）：它是会**变小**的——群主关掉
/// 「新成员仅可见入群后历史」后服务端的可见下界当即降到 0，而端上还缓存着旧的 500，
/// 那条会话就在本 App 生命周期内再也翻不上去、且没有任何提示。
/// 只清下界，**不动 head / 缺口**（那两项自纠错，下界是唯一"陈旧即封死"的）。
- (void)test_clearHistoryFloors只清下界 {
    IMBacklogTracker *t = [IMBacklogTracker new];
    [t noteHistoryFloor:500 forConv:@"c1"];
    [t noteHead:20001 forConv:@"c1"];
    [t markGapForConv:@"c1"];

    [t clearHistoryFloors];

    XCTAssertEqual([t historyFloorForConv:@"c1"], 0);
    XCTAssertEqual([t headForConv:@"c1"], 20001, @"head 不该被连累");
    XCTAssertTrue([t hasGapForConv:@"c1"], @"缺口标记不该被连累");
}

/// 切账号 / 断开必须清干净：同一个 conv_id 在两个账号下可见范围不同，串了就是错的
/// （与 head / 缺口标记同一条理由）。
- (void)test_reset清掉下界 {
    IMBacklogTracker *t = [IMBacklogTracker new];
    [t noteHistoryFloor:500 forConv:@"c1"];
    [t reset];
    XCTAssertEqual([t historyFloorForConv:@"c1"], 0);
}

#pragma mark - C4：↓ 跳到底 / conv_bump（与 im-web windowPlan.test.ts 同一组场景）

/// 取最新拿回的正是 `[tip-199, tip]` 这 200 条。下沿多算一条，刚取回最新一页后这一窗永远判不齐，
/// 每次点 ↓ 都白问一次（2026-09-11 im-web 出站帧测试抓到的 off-by-one，两端同口径）。
- (void)test_最新一页下沿是tip减page加1 {
    XCTAssertEqual(IMChatLatestPageLow(1000, 200), 801);
    XCTAssertEqual(IMChatLatestPageLow(50, 200), 1, @"会话不足一页时下沿钳到 1");
}

/// C4 之前 iOS 在 atTail 时一律取最新一窗；用户在尾窗里往上滑着读时会被整窗替换并贴底拽走。
/// 「贴底」由调用方算成 atTail && isNearBottom 传进来，这里钉的是「没贴底就绝不补」。
- (void)test_bump没贴底不补 {
    XCTAssertFalse(IMChatBumpShouldCatchUp(NO, 130, 100));
    XCTAssertFalse(IMChatBumpShouldCatchUp(NO, 5000, 100), @"差距再大，在翻历史也不补——↓N 按 head 计数");
}

- (void)test_bump贴底且落后才补 {
    XCTAssertTrue(IMChatBumpShouldCatchUp(YES, 130, 100));
    XCTAssertTrue(IMChatBumpShouldCatchUp(YES, 50, 0), @"窗口里没有已上号的消息");
}

- (void)test_bump已含最新或不知道最新不补 {
    XCTAssertFalse(IMChatBumpShouldCatchUp(YES, 130, 130), @"信号晚到，窗口已含最新");
    XCTAssertFalse(IMChatBumpShouldCatchUp(YES, 0, 100), @"head 未知");
}

#pragma mark - 取最新一页：内存 head 未知时（2026-09-13 进单聊空白页）

/// 改密码被踢 → 重登 → 内存 head 清空、重连后该会话没再报 head；落库的 head 还在。
/// 只认内存 head 时，进无未读、本地一条都没有的单聊（服务端 13 万条）直接 return → 空白页，
/// 直到对方发来一条新消息把 head 带回来才出历史。
- (void)test_内存head丢了退回落库的head {
    XCTAssertEqual(IMChatTailTip(0, 130064), 130064);
    XCTAssertEqual(IMChatTailTip(130065, 130064), 130065, @"本次连接报上来的优先");
    XCTAssertEqual(IMChatTailTip(0, 0), 0);
    XCTAssertEqual(IMChatTailTip(-1, -1), 0, @"非正值不是位点");
}

/// 连落库的 head 也没有（新装、从没同步过这条会话）：空窗时不问就是永久空白，且没有重试入口。
- (void)test_head未知且空窗必须问服务端 {
    XCTAssertTrue(IMChatShouldRequestTail(0, NO, 0));
}

/// 发消息 / 点 ↓ 都走这一步：窗口里已有内容而 head 未知时每次都问是白跑（与 Web 刻意不同，SYMMETRY 登记）。
- (void)test_head未知但窗口有内容不白跑 {
    XCTAssertFalse(IMChatShouldRequestTail(0, NO, 500));
}

- (void)test_head已知时只看最新一页盖没盖住 {
    XCTAssertTrue(IMChatShouldRequestTail(130064, NO, 0));
    XCTAssertTrue(IMChatShouldRequestTail(130064, NO, 130064), @"尾部孤岛：最大 seq 等于 head 也不算齐（C4）");
    XCTAssertFalse(IMChatShouldRequestTail(130064, YES, 0), @"盖住了就不问，空窗也一样（本地展开由调用方负责）");
}

@end
