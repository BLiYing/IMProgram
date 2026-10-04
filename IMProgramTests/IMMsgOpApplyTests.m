//  IMMsgOpApplyTests.m
//  msg_op（撤回/编辑/置顶/删除）「帧 → 终值 → 内存模型 → 横幅」这一路（IMMsgOpApply）。
//
//  错法全是**静默**的：界面照常渲染，只是取消置顶被当成置顶、编辑后 @ 高亮错位、撤回后横幅仍指向墓碑。
//  所以按「会怎么错」钉，用例名就是那个错法。服务端对应实现：IMServer internal/gateway/hub_msgop*.go。

#import <XCTest/XCTest.h>

#import "IMMsgOpApply.h"
#import "IMMessageModel.h"
#import "IMPinnedMessage.h"
#import "IMProtocol.h"
#import "IMSocketManager.h"

@interface IMMsgOpApplyTests : XCTestCase
@end

@implementation IMMsgOpApplyTests

static const int64_t kNow = 1788000000000;

static NSDictionary *Payload(NSString *op, NSDictionary *extra) {
    NSMutableDictionary *d = [@{ @"op": op, @"conv_id": @"g_1", @"target_conv_seq": @7 } mutableCopy];
    [d addEntriesFromDictionary:extra ?: @{}];
    return d;
}

/// 直接喂原始负载（宏参数里字典字面量的逗号要靠圆括号保护，所以包一层函数）。
static IMMsgOpPatch *Raw(NSDictionary *payload) {
    return [IMMsgOpPatch patchFromPayload:payload nowMillis:kNow];
}

static IMMsgOpPatch *Parse(NSString *op, NSDictionary *extra) {
    return [IMMsgOpPatch patchFromPayload:Payload(op, extra) nowMillis:kNow];
}

#pragma mark - 解析：整条丢弃 vs 忽略

/// convID 缺失/空、target 非正：整条丢弃（nil），不能带着残缺字段往下走。
- (void)test_缺会话或目标位点整条丢弃 {
    XCTAssertNil(Raw(@{ @"op": kIMMsgOpRecall, @"target_conv_seq": @7 }));
    XCTAssertNil(Raw(@{ @"op": kIMMsgOpRecall, @"conv_id": @"", @"target_conv_seq": @7 }));
    XCTAssertNil(Raw(@{ @"op": kIMMsgOpRecall, @"conv_id": @"g_1" }));
    XCTAssertNil(Raw(@{ @"op": kIMMsgOpRecall, @"conv_id": @"g_1", @"target_conv_seq": @0 }));
    XCTAssertNil(Raw(@{ @"op": kIMMsgOpRecall, @"conv_id": @"g_1", @"target_conv_seq": @(-3) }));
    // 类型不对（conv_id 是数字）按缺失处理。
    XCTAssertNil(Raw(@{ @"op": kIMMsgOpRecall, @"conv_id": @5, @"target_conv_seq": @7 }));
}

/// 未知 op：**不是 nil**，而是 Unknown——我方操作的回执 client_msg_id 仍要摘掉，否则在途集合泄漏。
- (void)test_未知op是Unknown而不是nil_回执仍可取 {
    IMMsgOpPatch *p = Parse(@"teleport", @{ @"client_msg_id": @"cm-1" });
    XCTAssertNotNil(p);
    XCTAssertEqual(p.kind, IMMsgOpKindUnknown);
    XCTAssertEqualObjects(p.clientMsgID, @"cm-1");
    XCTAssertEqual(p.recalledAt, 0);
    XCTAssertEqual(p.editedAt, 0);
    XCTAssertEqual(p.pinnedAt, 0);
}

- (void)test_删除不带任何字段终值 {
    IMMsgOpPatch *p = Parse(kIMMsgOpDelete, @{ @"by": @"u9" });
    XCTAssertEqual(p.kind, IMMsgOpKindDelete);
    XCTAssertEqualObjects(p.convID, @"g_1");
    XCTAssertEqual(p.targetConvSeq, 7);
    XCTAssertEqual(p.recalledAt, 0);
}

#pragma mark - 撤回 / 编辑

- (void)test_撤回取本地时钟并带操作者 {
    IMMsgOpPatch *p = Parse(kIMMsgOpRecall, @{ @"by": @"u9" });
    XCTAssertEqual(p.kind, IMMsgOpKindRecall);
    XCTAssertEqual(p.recalledAt, kNow);
    XCTAssertEqualObjects(p.by, @"u9");
}

- (void)test_编辑带新正文与时刻 {
    IMMsgOpPatch *p = Parse(kIMMsgOpEdit, @{ @"content": @"new text" });
    XCTAssertEqual(p.kind, IMMsgOpKindEdit);
    XCTAssertEqual(p.editedAt, kNow);
    XCTAssertEqualObjects(p.editedContent, @"new text");
}

/// 现状（抽取时保持，不是推荐行为）：编辑帧缺 content / 类型不对时 editedContent 退成 @""，
/// 落库会把正文改成空串。服务端恒下发 content，所以实际碰不到；若要改成「缺字段则不改正文」，先改这条用例。
- (void)test_编辑缺正文时现状退成空串 {
    XCTAssertEqualObjects(Parse(kIMMsgOpEdit, nil).editedContent, @"");
    XCTAssertEqualObjects(Parse(kIMMsgOpEdit, @{ @"content": @123 }).editedContent, @"");
}

#pragma mark - 置顶：取消置顶不能被当成置顶

/// G0 接横幅时的事故：取消置顶与置顶是同一个 op，早先一律 pinnedAt=now，把「取消置顶」也记成了置顶。
- (void)test_pinned为false是取消置顶_记为负一 {
    XCTAssertEqual(Parse(kIMMsgOpPin, @{ @"pinned": @NO, @"timestamp": @(kNow + 5) }).pinnedAt, -1);
    XCTAssertEqual(Parse(kIMMsgOpPin, @{ @"pinned": @0 }).pinnedAt, -1);
}

/// 字段缺失按「取消」处理：缺字段=取消比缺字段=置顶安全，取消置顶才不会残留已置顶态。
- (void)test_pinned字段缺失按取消处理 {
    XCTAssertEqual(Parse(kIMMsgOpPin, nil).pinnedAt, -1);
    XCTAssertEqual(Parse(kIMMsgOpPin, @{ @"pinned": NSNull.null }).pinnedAt, -1, @"没有 boolValue 的类型按取消");
}

/// 置顶时刻取服务端 timestamp（多端一致）；缺省/非正才回退本地时钟。
- (void)test_置顶时刻优先用服务端时间 {
    XCTAssertEqual(Parse(kIMMsgOpPin, @{ @"pinned": @YES, @"timestamp": @(kNow + 99) }).pinnedAt, kNow + 99);
    XCTAssertEqual(Parse(kIMMsgOpPin, @{ @"pinned": @YES }).pinnedAt, kNow);
    XCTAssertEqual(Parse(kIMMsgOpPin, @{ @"pinned": @YES, @"timestamp": @0 }).pinnedAt, kNow);
}

#pragma mark - 通知 userInfo 终值

- (void)test_撤回的终值带时刻与操作者 {
    NSDictionary *info = [Parse(kIMMsgOpRecall, @{ @"by": @"u9" }) appliedUserInfo];
    XCTAssertEqualObjects(info[kIMConvIDKey], @"g_1");
    XCTAssertEqualObjects(info[kIMMsgOpTargetSeqKey], @7);
    XCTAssertEqualObjects(info[kIMMsgOpRecalledAtKey], @(kNow));
    XCTAssertEqualObjects(info[kIMMsgOpRecalledByKey], @"u9");
    XCTAssertNil(info[kIMMsgOpEditedAtKey]);
    XCTAssertNil(info[kIMMsgOpPinnedAtKey], @"撤回不能顺带带出置顶字段，收端会据此改 pinnedAt");
}

/// 没有操作者就不带 by 键（收端据键存在与否决定是否覆盖 recalledBy）。
- (void)test_撤回没有操作者不带by键 {
    NSDictionary *info = [Parse(kIMMsgOpRecall, nil) appliedUserInfo];
    XCTAssertNotNil(info[kIMMsgOpRecalledAtKey]);
    XCTAssertNil(info[kIMMsgOpRecalledByKey]);
}

- (void)test_编辑的终值带新正文 {
    NSDictionary *info = [Parse(kIMMsgOpEdit, @{ @"content": @"v2" }) appliedUserInfo];
    XCTAssertEqualObjects(info[kIMMsgOpEditedAtKey], @(kNow));
    XCTAssertEqualObjects(info[kIMMsgOpContentKey], @"v2");
    XCTAssertNil(info[kIMMsgOpRecalledAtKey]);
}

/// 取消置顶的终值是「键存在且值为 0」，**不是缺键**：缺键 = 本 op 不涉及置顶，收端不会清零。
- (void)test_取消置顶的终值是键在值为0 {
    NSDictionary *cancel = [Parse(kIMMsgOpPin, @{ @"pinned": @NO }) appliedUserInfo];
    XCTAssertNotNil(cancel[kIMMsgOpPinnedAtKey]);
    XCTAssertEqualObjects(cancel[kIMMsgOpPinnedAtKey], @0);
    NSDictionary *pin = [Parse(kIMMsgOpPin, @{ @"pinned": @YES, @"timestamp": @(kNow + 1) }) appliedUserInfo];
    XCTAssertEqualObjects(pin[kIMMsgOpPinnedAtKey], @(kNow + 1));
}

#pragma mark - 应用到内存模型

static IMMessageModel *Model(void) {
    IMMessageModel *m = [[IMMessageModel alloc] init];
    m.convSeq = 7;
    m.content = @"hello @bob";
    IMMentionSpan *span = [[IMMentionSpan alloc] init];
    m.mentionSpans = @[span];
    m.pinnedAt = 500;
    return m;
}

/// 编辑后**必须清掉 mentionSpans**：偏移相对原文，正文一改全错位——不清就高亮错位到别的字上。
- (void)test_编辑清掉mentionSpans {
    IMMessageModel *m = Model();
    IMChatApplyMsgOpToMessage(m, [Parse(kIMMsgOpEdit, @{ @"content": @"bye" }) appliedUserInfo]);
    XCTAssertEqualObjects(m.content, @"bye");
    XCTAssertEqual(m.editedAt, kNow);
    XCTAssertNil(m.mentionSpans);
}

/// 撤回只改撤回态，不碰正文（原文保留，供「重新编辑」）、不碰 mentionSpans、不碰置顶。
- (void)test_撤回只改撤回态 {
    IMMessageModel *m = Model();
    IMChatApplyMsgOpToMessage(m, [Parse(kIMMsgOpRecall, @{ @"by": @"u9" }) appliedUserInfo]);
    XCTAssertEqual(m.recalledAt, kNow);
    XCTAssertEqualObjects(m.recalledBy, @"u9");
    XCTAssertEqualObjects(m.content, @"hello @bob");
    XCTAssertEqual(m.mentionSpans.count, 1u);
    XCTAssertEqual(m.pinnedAt, 500);
}

/// 取消置顶把 pinnedAt 清到 0；置顶写入服务端时刻；二者都不动正文与 spans。
- (void)test_置顶与取消置顶只改pinnedAt {
    IMMessageModel *m = Model();
    IMChatApplyMsgOpToMessage(m, [Parse(kIMMsgOpPin, @{ @"pinned": @NO }) appliedUserInfo]);
    XCTAssertEqual(m.pinnedAt, 0);
    IMChatApplyMsgOpToMessage(m, [Parse(kIMMsgOpPin, @{ @"pinned": @YES, @"timestamp": @(kNow + 3) }) appliedUserInfo]);
    XCTAssertEqual(m.pinnedAt, kNow + 3);
    XCTAssertEqualObjects(m.content, @"hello @bob");
    XCTAssertEqual(m.mentionSpans.count, 1u);
}

#pragma mark - 横幅

static IMPinnedMessage *Pinned(int64_t seq) {
    IMPinnedMessage *p = [[IMPinnedMessage alloc] init];
    p.convSeq = seq;
    return p;
}

/// 撤回命中横幅里的置顶项：先本地剔除、再重拉（重拉 best-effort，弱网下只靠它横幅会继续挂着墓碑预览）。
- (void)test_撤回命中横幅_本地剔除并重拉 {
    NSArray *items = @[Pinned(3), Pinned(7)];
    IMChatMsgOpBannerAction a = IMChatMsgOpBannerPlan([Parse(kIMMsgOpRecall, nil) appliedUserInfo], items);
    XCTAssertTrue(a.dropTargetLocally);
    XCTAssertTrue(a.reload);
}

/// 编辑命中横幅：横幅文案要更新（重拉），但消息还在，**不能**本地剔除。
- (void)test_编辑命中横幅_只重拉不剔除 {
    IMChatMsgOpBannerAction a = IMChatMsgOpBannerPlan([Parse(kIMMsgOpEdit, @{ @"content": @"x" }) appliedUserInfo], @[Pinned(7)]);
    XCTAssertFalse(a.dropTargetLocally);
    XCTAssertTrue(a.reload);
}

/// 撤回/编辑的不是横幅里的消息：什么都不用做（别白发一次拉取）。
- (void)test_撤回编辑没命中横幅什么都不做 {
    IMChatMsgOpBannerAction r = IMChatMsgOpBannerPlan([Parse(kIMMsgOpRecall, nil) appliedUserInfo], @[Pinned(3)]);
    XCTAssertFalse(r.dropTargetLocally);
    XCTAssertFalse(r.reload);
    IMChatMsgOpBannerAction e = IMChatMsgOpBannerPlan([Parse(kIMMsgOpEdit, @{ @"content": @"x" }) appliedUserInfo], @[]);
    XCTAssertFalse(e.dropTargetLocally);
    XCTAssertFalse(e.reload);
}

/// 置顶/取消置顶必拉：不看目标是否已在横幅里（置顶列表可能还没加载完，会漏判、横幅晚一拍）。
- (void)test_置顶与取消置顶必重拉 {
    XCTAssertTrue(IMChatMsgOpBannerPlan([Parse(kIMMsgOpPin, @{ @"pinned": @YES }) appliedUserInfo], @[]).reload);
    IMChatMsgOpBannerAction c = IMChatMsgOpBannerPlan([Parse(kIMMsgOpPin, @{ @"pinned": @NO }) appliedUserInfo], @[]);
    XCTAssertTrue(c.reload, @"取消置顶的终值是键在值为0，必须被识别为 pin 变化");
    XCTAssertFalse(c.dropTargetLocally);
}

- (void)test_剔除只去掉目标位点_保持原序 {
    NSArray *items = @[Pinned(9), Pinned(7), Pinned(3), Pinned(7)];
    NSArray<IMPinnedMessage *> *kept = IMChatPinnedItemsDroppingSeq(items, 7);
    XCTAssertEqual(kept.count, 2u);
    XCTAssertEqual(kept[0].convSeq, 9);
    XCTAssertEqual(kept[1].convSeq, 3);
    XCTAssertEqual(IMChatPinnedItemsDroppingSeq(@[], 7).count, 0u);
}

@end
