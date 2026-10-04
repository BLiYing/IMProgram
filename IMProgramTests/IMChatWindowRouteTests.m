//  IMChatWindowRouteTests.m
//  window_resp 到达后的分流（IMChatWindowRoute）。
//
//  window_resp 的形状对所有开窗用途都一样，分不清就拿 A 的应答干 B 的事，且**错得很安静**：
//  界面照常，只是「大群进会话最后几条各显示两遍」「停在首条未读被甩到最底并顺手标已读」「翻页途中被换窗」。
//  所以按「会怎么错」钉，用例名就是那个错法。

#import <XCTest/XCTest.h>

#import "IMChatWindowRoute.h"

@interface IMChatWindowRouteTests : XCTestCase
@end

@implementation IMChatWindowRouteTests

/// 在途标志的快照；默认全空（没有任何在途）。
typedef struct {
    int64_t newer, entry, anchor, hi;
    BOOL tail, isJump, earliest;
} Pending;

static IMChatWindowRespRoute Route(int64_t respAnchor, BOOL found, Pending p) {
    return IMChatRouteWindowResp(YES, respAnchor, found, p.newer, p.entry, p.tail, p.anchor, p.isJump, p.earliest, p.hi);
}

#pragma mark - 非本会话 / 没有在途

/// 别的会话的应答：无论在途标志怎么摆都不碰本页。
- (void)test_非本会话一律忽略 {
    XCTAssertEqual(IMChatRouteWindowResp(NO, 100, YES, 100, 100, YES, 100, YES, NO, 200), IMChatWindowRespIgnore);
}

/// 没有任何在途请求时，来一帧锚点对不上的应答：忽略（不清任何标志）。
- (void)test_没有在途的应答忽略 {
    XCTAssertEqual(Route(500, YES, (Pending){0}), IMChatWindowRespIgnore);
}

/// 锚点回显对不上 = 这帧是回更早那次开窗的（翻页途中又点了置顶横幅）：用了它会把窗口拉到错误的一段。
- (void)test_锚点对不上通用在途就忽略 {
    Pending p = {.anchor = 300};
    XCTAssertEqual(Route(250, YES, p), IMChatWindowRespIgnore);
}

/// **行为修正（本次抽取时一并修）**：「要最新一窗」的 6s 兜底超时清掉 pendingTail 之后，迟到的 anchor=0 应答
/// 以前会因 `0 == pendingAnchor(0)` 落进向上翻页分支，凭空多做一次向上 prepend。现在必须忽略。
- (void)test_迟到的anchor0应答不再误入向上翻页 {
    XCTAssertEqual(Route(0, YES, (Pending){0}), IMChatWindowRespIgnore);
    // 通用在途是向上翻页（anchor=300）时，anchor=0 的帧同样不是它的。
    Pending p = {.anchor = 300};
    XCTAssertEqual(Route(0, YES, p), IMChatWindowRespIgnore);
}

#pragma mark - 向下翻页

/// 正常：应答时窗口末尾 >= 请求锚点 → 接尾。
- (void)test_向下翻页_窗口没被换过就接尾 {
    Pending p = {.newer = 1000, .hi = 1000};
    XCTAssertEqual(Route(1000, YES, p), IMChatWindowRespNewerAppend);
    p.hi = 1200; // 在途期间又上来几条
    XCTAssertEqual(Route(1000, YES, p), IMChatWindowRespNewerAppend);
}

/// 窗口被换到了**更早**的一段（翻页途中点了置顶横幅/搜索跳转）：这帧已过期，不能接尾、不能改 atTail。
- (void)test_向下翻页_窗口被换到更早一段是过期帧 {
    Pending p = {.newer = 1000, .hi = 400};
    XCTAssertEqual(Route(1000, YES, p), IMChatWindowRespNewerStale);
}

/// 窗口空（hi=0）也是过期：没有可以接的尾。
- (void)test_向下翻页_空窗口是过期帧 {
    Pending p = {.newer = 1000, .hi = 0};
    XCTAssertEqual(Route(1000, YES, p), IMChatWindowRespNewerStale);
}

#pragma mark - 优先级：专用路必须先于通用路认领

/// 进会话按读位点开窗：**停在首条未读**，不是通用路（通用路在 anchor 对得上时会当跳转/翻页处理）。
- (void)test_按读位点开窗走专用路 {
    Pending p = {.entry = 700};
    XCTAssertEqual(Route(700, YES, p), IMChatWindowRespEntryRewindow);
    // anchor_found=NO 也一样：读位点那一条可能是占号的事件行。
    XCTAssertEqual(Route(700, NO, p), IMChatWindowRespEntryRewindow);
}

/// 同一个锚点既是向下翻页又是读位点开窗（并发）：向下翻页先认领（顺序即语义）。
- (void)test_锚点同时对上向下翻页与读位点开窗_向下翻页优先 {
    Pending p = {.newer = 800, .entry = 800, .hi = 900};
    XCTAssertEqual(Route(800, YES, p), IMChatWindowRespNewerAppend);
}

/// 专用路优先于通用路：读位点开窗的锚点恰好也等于通用在途锚点时，不能被当成跳转/向上翻页。
- (void)test_读位点开窗优先于通用在途 {
    Pending p = {.entry = 700, .anchor = 700, .isJump = YES};
    XCTAssertEqual(Route(700, YES, p), IMChatWindowRespEntryRewindow);
}

/// 「要最新一窗」：anchor=0 且 pendingTail。贴底；与读位点开窗**必须分开**（否则停在未读处被甩到最底并标已读）。
- (void)test_要最新一窗走尾窗路 {
    Pending p = {.tail = YES};
    XCTAssertEqual(Route(0, YES, p), IMChatWindowRespTailRewindow);
    // 通用在途同时存在（用户一边向上翻页一边点 ↓）：anchor=0 的帧仍归尾窗路。
    p.anchor = 300;
    XCTAssertEqual(Route(0, YES, p), IMChatWindowRespTailRewindow);
}

/// 非 0 锚点不会被 pendingTail 误认。
- (void)test_非0锚点不走尾窗路 {
    Pending p = {.tail = YES, .anchor = 300};
    XCTAssertEqual(Route(300, YES, p), IMChatWindowRespOlder);
}

#pragma mark - 通用路：跳转 / 跳最早 / 向上翻页

- (void)test_向上翻页 {
    Pending p = {.anchor = 300};
    XCTAssertEqual(Route(300, YES, p), IMChatWindowRespOlder);
    // 向上翻页不看 anchor_found（落点由本地取段决定）。
    XCTAssertEqual(Route(300, NO, p), IMChatWindowRespOlder);
}

- (void)test_跳转_找到了开本地窗口 {
    Pending p = {.anchor = 300, .isJump = YES};
    XCTAssertEqual(Route(300, YES, p), IMChatWindowRespJumpOpen);
}

/// 服务端明确说这条不存在/对我不可见：才报「原消息已被删除」（旧做法靠猜，会报假的）。
- (void)test_跳转_服务端说没有才报删除 {
    Pending p = {.anchor = 300, .isJump = YES};
    XCTAssertEqual(Route(300, NO, p), IMChatWindowRespJumpNotFound);
}

/// 「跳到最早」：锚点写死 1，1 号常常不是一条消息 → anchor_found=NO 也**不能**按普通跳转报假的「已删除」。
- (void)test_跳最早_不看anchorFound {
    Pending p = {.anchor = 1, .isJump = YES, .earliest = YES};
    XCTAssertEqual(Route(1, NO, p), IMChatWindowRespJumpEarliest);
    XCTAssertEqual(Route(1, YES, p), IMChatWindowRespJumpEarliest);
}

/// earliest 标志只在跳转时有意义：向上翻页（isJump=NO）带着残留的 earliest 也不能走跳最早。
- (void)test_earliest只对跳转生效 {
    Pending p = {.anchor = 300, .isJump = NO, .earliest = YES};
    XCTAssertEqual(Route(300, YES, p), IMChatWindowRespOlder);
}

@end
