#import <XCTest/XCTest.h>

#import "IMMessageModel.h"

// IMChatViewController+Selection.m 里的文件级纯函数（同 IMChatEntryWindowAnchor 的套路：
// 判据抽出来单测，免构造依赖数据库与 UIKit 的真 VC）。
FOUNDATION_EXPORT NSArray<IMMessageModel *> *IMChatSelectedMessages(NSDictionary<NSNumber *, IMMessageModel *> *selected);

/// 多选态勾选集的契约（2026-09-06，起因是用户实测报出的丢勾选）。
///
/// 原先非相册消息的勾选**只活在 UITableView 的 `indexPathsForSelectedRows` 里**，两个死穴：
///   ① `reloadData` 会把它清空——而向上翻页的 `prependMessages:` 必然 reload；
///   ② 它是**按行下标**记的，prepend 在头部插 N 条后所有下标平移，就算没被清也全指向了别人。
/// 实测表现：勾两条 → 上滚拉一页历史 → 再勾一条，前两条静默消失、标题只剩「已选择 1 条」。
///
/// 现在改按 `conv_seq` 记（与 Web 端 `Set<convSeq>` 同构，那边因此从没这个毛病）。
/// 这组用例钉的就是「导出结果只由勾选集决定」——签名里拿不到窗口/行号，退不回去。
@interface IMChatSelectionTests : XCTestCase
@end

@implementation IMChatSelectionTests

static IMMessageModel *msg(int64_t seq, NSString *from) {
    IMMessageModel *m = [IMMessageModel new];
    m.convSeq = seq;
    m.from = from;
    m.contentType = @"text";
    m.content = [NSString stringWithFormat:@"#%lld", seq];
    return m;
}

/// 导出按 conv_seq 升序 = 会话时序。**不能按插入序**：用户可以先勾靠下的新消息、
/// 再上翻勾更早的，合并转发卡片若按插入序打包，收件人看到的就是倒着的对话。
- (void)testExportsSortedByConvSeq {
    NSMutableDictionary<NSNumber *, IMMessageModel *> *sel = [NSMutableDictionary dictionary];
    sel[@30] = msg(30, @"u2");   // 先勾靠后的
    sel[@10] = msg(10, @"u2");   // 再上翻勾更早的
    sel[@20] = msg(20, @"u2");

    NSArray<IMMessageModel *> *out = IMChatSelectedMessages(sel);
    XCTAssertEqual(out.count, 3u);
    XCTAssertEqual(out[0].convSeq, 10);
    XCTAssertEqual(out[1].convSeq, 20);
    XCTAssertEqual(out[2].convSeq, 30);
}

/// 空集 / nil 都回空数组，别回 nil——调用方一律 `.count` 判空，回 nil 会静默变成"没选"。
- (void)testEmptyAndNil {
    XCTAssertEqual(IMChatSelectedMessages(@{}).count, 0u);
    XCTAssertEqual(IMChatSelectedMessages(nil).count, 0u);
}

/// **本轮 bug 的回归钉**：勾选集里的消息是否还在当前渲染窗口里，与导出结果无关。
/// 上翻翻页会 prepend 一页并从尾部裁掉一窗，早先勾的消息可能被挤出窗口；
/// 存的是模型而不只是 seq，所以它们照样能被转发/收藏/举报，计数也不会缩水。
- (void)testSurvivesWindowMutation {
    NSMutableDictionary<NSNumber *, IMMessageModel *> *sel = [NSMutableDictionary dictionary];
    sel[@900] = msg(900, @"u2");
    sel[@901] = msg(901, @"u2");

    // 模拟一次上翻：窗口整体换成更早的一段（900/901 已被裁出窗口），勾选集不动。
    NSMutableArray<IMMessageModel *> *windowAfterPrepend = [NSMutableArray array];
    for (int64_t s = 1; s <= 200; s++) { [windowAfterPrepend addObject:msg(s, @"u2")]; }
    XCTAssertEqual(windowAfterPrepend.count, 200u); // 窗口确实换了人

    // 再勾一条新翻出来的早消息。
    sel[@5] = windowAfterPrepend[4];

    NSArray<IMMessageModel *> *out = IMChatSelectedMessages(sel);
    XCTAssertEqual(out.count, 3u, @"上翻后应仍是 3 条——旧版这里会掉成 1 条");
    XCTAssertEqual(out[0].convSeq, 5);
    XCTAssertEqual(out[1].convSeq, 900);
    XCTAssertEqual(out[2].convSeq, 901);
}

/// 同一条重复勾选只算一次（相册整组全选与逐格勾选可能对同一 seq 各写一次）。
- (void)testSameSeqDeduped {
    NSMutableDictionary<NSNumber *, IMMessageModel *> *sel = [NSMutableDictionary dictionary];
    sel[@7] = msg(7, @"u2");
    sel[@7] = msg(7, @"u2"); // 覆盖，不新增
    XCTAssertEqual(IMChatSelectedMessages(sel).count, 1u);
}

@end
