#import <XCTest/XCTest.h>

#import "IMBacklogTracker.h"
#import "IMDatabase.h"
#import "IMDatabase+Ranges.h"
#import "IMMessageModel.h"

/// 离线积压的两块地基（设计见 IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md）：
///   ① `IMBacklogTracker`——连接级簿记（超级群 / head / 缺口 / 回执合批）；
///   ② `IMDatabase (Ranges)`——「本地有哪几段」的区间清单。
///
/// 为什么这两处值得单独钉：它们的错法**全是静默的**。区间合并少并一次 → "本地齐全"永远判 false →
/// 搜索一律改走服务端、离线集体降级；缺口标记该消没消 → 反过来，明明缺着却当齐全，
/// 于是拿一段残缺数据去回答"整个会话"的问题。两种都不会崩、不会报错，只是答案悄悄不对。
@interface IMBacklogRangesTests : XCTestCase
@end

@implementation IMBacklogRangesTests {
    IMDatabase *_db;
    NSURL *_url;
}

static NSString * const kConv = @"g_backlog";
static NSString * const kMe = @"me";

- (void)setUp {
    [super setUp];
    NSString *name = [NSString stringWithFormat:@"im-backlog-test-%@.sqlite", NSUUID.UUID.UUIDString];
    _url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    _db = [[IMDatabase alloc] initWithFileURL:_url];
    [_db useOwnerUserID:kMe];
}

- (void)tearDown {
    [NSFileManager.defaultManager removeItemAtURL:_url error:NULL];
    [super tearDown];
}

#pragma mark - 区间清单

/// 造一条已落库的对端消息。
- (void)seedMessageSeq:(int64_t)seq {
    IMMessageModel *m = [IMMessageModel receivedMessageWithNewMsgData:@{
        @"server_msg_id": [NSString stringWithFormat:@"s%lld", seq],
        @"conv_id": kConv, @"from": @"peer", @"content": [NSString stringWithFormat:@"#%lld", seq],
        @"content_type": @"text", @"conv_seq": @(seq), @"timestamp": @(1788000000000 + seq),
    }];
    [_db saveMessage:m];
}

/// 建出 im_conversation_local 那一行。
///
/// `updateHeadConvSeq:` 是 UPDATE 不是 UPSERT——行不存在就静默丢弃（刻意：会话列表
/// 是 `SELECT *` 直出，凭空插占位行会变成界面上一条无名空会话）。测试不建行的话，
/// 所有 head 断言都在空转：head 恒 0，`isConvComplete:` 因"上界未知"一律回 YES，
/// 于是几条本该测出问题的用例**全都假绿**（2026-09-03 首次真跑单测才暴露）。
- (void)seedConversationRow {
    [self seedMessageSeq:1];
}


/// 把区间清单压成 "lo-hi,lo-hi" 便于断言。
- (NSString *)rangesText {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSArray<NSNumber *> *r in [_db rangesForConv:kConv]) {
        [parts addObject:[NSString stringWithFormat:@"%lld-%lld",
                          r.firstObject.longLongValue, r.lastObject.longLongValue]];
    }
    return [parts componentsJoinedByString:@","];
}

- (void)testRegisterAndMergeAdjacent {
    [_db registerRangeInConv:kConv from:1 to:100];
    XCTAssertEqualObjects([self rangesText], @"1-100");

    // **相邻必须合并**：conv_seq 是连续整数，[1,100] 与 [101,200] 之间没有空隙。
    // 不合并的话「本地齐全」判定会永远为假——拉全了也当作有缺口。
    [_db registerRangeInConv:kConv from:101 to:200];
    XCTAssertEqualObjects([self rangesText], @"1-200");

    // 隔开的一段自成一格（中间 201..999 是真缺口）。
    [_db registerRangeInConv:kConv from:1000 to:1100];
    XCTAssertEqualObjects([self rangesText], @"1-200,1000-1100");

    // 补上中段 → 三段并成一段，缺口消失。缺口只会收窄，不会扩大。
    [_db registerRangeInConv:kConv from:201 to:999];
    XCTAssertEqualObjects([self rangesText], @"1-1100");
}

- (void)testRegisterIsIdempotent {
    // 幂等：重拉同一页（服务端超时重发、客户端退避重试）不该把清单撑大。
    for (int i = 0; i < 5; i++) { [_db registerRangeInConv:kConv from:1 to:100]; }
    XCTAssertEqualObjects([self rangesText], @"1-100");
    // 被完全包含的子区间同样不改变结果。
    [_db registerRangeInConv:kConv from:20 to:30];
    XCTAssertEqualObjects([self rangesText], @"1-100");
}

- (void)testRegisterRejectsInvalidRange {
    [_db registerRangeInConv:kConv from:1 to:100];
    [_db registerRangeInConv:kConv from:50 to:10];  // hi<lo
    [_db registerRangeInConv:kConv from:0 to:0];
    XCTAssertEqualObjects([self rangesText], @"1-100", @"非法区间应被忽略而不是污染清单");
}

- (void)testCompletenessNeedsHead {
    [self seedConversationRow];
    // head 未知（从没收到过服务端最新位点）→ 按齐全处理：没有上界就无从判断缺什么，
    // 保持改造前的行为，不能让一个未知量把所有会话打成"有缺口"。
    XCTAssertTrue([_db isConvComplete:kConv]);

    [_db updateHeadConvSeq:1000 forConv:kConv];
    XCTAssertFalse([_db isConvComplete:kConv], @"head=1000 但本地一段都没有");

    [_db registerRangeInConv:kConv from:1 to:999];
    XCTAssertFalse([_db isConvComplete:kConv], @"尾巴差一条也不算齐全");

    [_db registerRangeInConv:kConv from:1000 to:1000];
    XCTAssertTrue([_db isConvComplete:kConv]);
}

/// ↓N 问的不是"整个会话齐不齐"，而是"**已滚入位点到 head 之间**还缺不缺"——
/// 会话开头缺十万条与"下面还有多少"无关。这条判据必须与 isConvComplete: 分开。
///
/// 现场（2026-09-05，libeyond 在「20000人大群」）：滚到底再往上滑，↓ 恒显 1。
/// 会话最后一个 conv_seq 是 op=pin 的 **msg_op 事件行**（110031），最后一条真消息是 110030 ——
/// 旧判据拿 `head > 本地最大消息 seq` 猜"下面还有没下载的"，把那个事件行数成了一条不存在的未读。
/// 区间清单登记时**含**这类不渲染的行，所以它盖得住 (frontier, head]。
- (void)testCoversFromToAnswersOnlyAboutTheAskedSpan {
    [self seedConversationRow];
    // 大群典型形态：开头缺一大片，只有尾段在本地——但尾段确实盖住了 (110030, 110031]。
    [_db registerRangeInConv:kConv from:109832 to:110031];
    [_db updateHeadConvSeq:110031 forConv:kConv];
    XCTAssertFalse([_db isConvComplete:kConv], @"整会话当然不齐全（前十万条没下载）");
    XCTAssertTrue([_db conv:kConv coversFrom:110031 to:110031],
                  @"但「已读到 110030，下面还缺不缺」的答案是：不缺");

    // 真有没下载的：head 超出本地那一段。
    [_db updateHeadConvSeq:110032 forConv:kConv];
    XCTAssertFalse([_db conv:kConv coversFrom:110031 to:110032]);

    // **跨两段不算覆盖**：中间那条缺口正是"没下载"，合起来算就等于宣称拿到了没拿到的东西。
    [_db registerRangeInConv:kConv from:110033 to:110040];
    [_db updateHeadConvSeq:110040 forConv:kConv];
    XCTAssertFalse([_db conv:kConv coversFrom:110031 to:110040], @"110032 缺着，两段不能合起来算");

    // 补上缺口 → 相邻段合并 → 覆盖成立。
    [_db registerRangeInConv:kConv from:110032 to:110032];
    XCTAssertTrue([_db conv:kConv coversFrom:110031 to:110040]);

    // 退化入参：hi<lo 不算覆盖（调用方 frontier==head 时压根不该问）。
    XCTAssertFalse([_db conv:kConv coversFrom:110041 to:110040]);
}

- (void)testGappedLocalIsNotComplete {
    [self seedConversationRow];
    [_db updateHeadConvSeq:100000 forConv:kConv];
    // 典型的大群积压形态：旧的一段 + 最新一段，中间十万条没下载。
    [_db registerRangeInConv:kConv from:1 to:1200];
    [_db registerRangeInConv:kConv from:99800 to:100000];
    XCTAssertFalse([_db isConvComplete:kConv]);
}

- (void)testHeadIsMonotonic {
    [self seedConversationRow];
    [_db updateHeadConvSeq:500 forConv:kConv];
    [_db updateHeadConvSeq:100 forConv:kConv]; // 乱序到达的旧快照
    XCTAssertEqual([_db headConvSeqForConv:kConv], 500,
                   @"head 只能前进——被拉回去会让「齐不齐」的判定来回抖");
}

- (void)testLegacyCursorBecomesFirstRange {
    [self seedConversationRow];
    // 老库兼容：升级前只有连续游标、没有区间行。反推出 [1, synced] 那一段，
    // 否则所有老用户升级后会被判成"整个会话都有缺口"，本地搜索一夜之间全改走服务端。
    [_db advanceSyncedConvSeqForConv:kConv toConvSeq:0]; // 先确保会话行存在（下面的 UPDATE 才有目标）
    [_db registerRangeInConv:kConv from:1 to:10];
    [_db updateHeadConvSeq:10 forConv:kConv];
    XCTAssertTrue([_db isConvComplete:kConv]);
}

#pragma mark - 尾窗按连续段切

- (NSString *)tailSeqsWithLimit:(NSInteger)limit {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (IMMessageModel *m in [_db latestContiguousMessagesForConv:kConv limit:limit]) {
        [parts addObject:[NSString stringWithFormat:@"%lld", m.convSeq]];
    }
    return [parts componentsJoinedByString:@","];
}

/// 大群积压的典型形态：本地只剩「一条旧岛」+「最新一段」，中间几万条没下载。
/// 直接取最后 N 行会把旧岛一并取出 → 首窗横跨缺口，且窗口里最早一条变成 seq 1，
/// `hasMoreAbove` 的 `earliest != 1` 判据据此认定"到会话开头了"，中间那几万条**永久**翻不回来。
- (void)testTailWindowExcludesIslandAcrossGap {
    [_db updateHeadConvSeq:1000 forConv:kConv];
    [self seedMessageSeq:1];
    for (int64_t q = 996; q <= 1000; q++) { [self seedMessageSeq:q]; }
    [_db registerRangeInConv:kConv from:1 to:1];
    [_db registerRangeInConv:kConv from:996 to:1000];

    XCTAssertEqualObjects([self tailSeqsWithLimit:200], @"996,997,998,999,1000",
                          @"尾窗只能给包含本地最新一条的那一段，缺口另一侧的旧岛不能混进来");
}

/// 中间被「为所有人删除」的那条不在本地库里，但它**下载过**（区间清单覆盖着它）——
/// 那不是缺口，不该把段切断。Web 侧同一个坑的表现是首屏只剩一条系统消息（2026-09-03 实测）。
- (void)testDeletedRowInsideRangeDoesNotSplitTail {
    [_db updateHeadConvSeq:18 forConv:kConv];
    for (int64_t q = 10; q <= 18; q++) { if (q != 14) { [self seedMessageSeq:q]; } }
    [_db registerRangeInConv:kConv from:1 to:18];   // 1..18 都下载过，14 只是不成为消息

    XCTAssertEqualObjects([self tailSeqsWithLimit:200], @"10,11,12,13,15,16,17,18",
                          @"区间清单覆盖到的空号不是缺口，不能据此切断尾段");
}

/// 上翻一页只能给**同一段**里的更早消息。
///
/// 光判"这一段里还有更早的"不够：段内剩余不足一页时，无下界的查询会径直翻过缺口，
/// 把旧岛接到窗口顶部——两段不相邻的历史被静默拼在一起，界面照常、时间戳看着也递增
/// （2026-09-03 用户实测「上翻不连贯」的另一半成因）。
- (void)testOlderPageStopsAtSegmentStart {
    [_db updateHeadConvSeq:1000 forConv:kConv];
    for (int64_t q = 1; q <= 5; q++) { [self seedMessageSeq:q]; }        // 旧岛
    for (int64_t q = 996; q <= 1000; q++) { [self seedMessageSeq:q]; }   // 尾段
    [_db registerRangeInConv:kConv from:1 to:5];
    [_db registerRangeInConv:kConv from:996 to:1000];

    // 段内只有 996..999 这 4 条比 1000 早，limit 给到 200 也不能把旧岛捞上来。
    NSArray<IMMessageModel *> *page = [_db contiguousMessagesForConv:kConv beforeConvSeq:1000 limit:200];
    NSMutableArray<NSString *> *seqs = [NSMutableArray array];
    for (IMMessageModel *m in page) { [seqs addObject:[NSString stringWithFormat:@"%lld", m.convSeq]]; }
    XCTAssertEqualObjects([seqs componentsJoinedByString:@","], @"996,997,998,999");
}

/// 向下翻页同理：本段剩余不足一页时不能翻过缺口把下一段接上来。
/// 现场形状取自用户实测的「20000人大群」：进会话按读位点开窗拿到 [99970,100219]，
/// 本地另有一段很早的旧岛，服务端 head 还在 110019——往下滑到 100219 就该问服务端，
/// 而不是把旧岛/下一段接到窗口尾部。
- (void)testNewerPageStopsAtSegmentEnd {
    [_db updateHeadConvSeq:110019 forConv:kConv];
    for (int64_t q = 1; q <= 5; q++) { [self seedMessageSeq:q]; }              // 旧岛
    for (int64_t q = 99970; q <= 100219; q++) { [self seedMessageSeq:q]; }     // 进会话那一窗
    for (int64_t q = 110015; q <= 110019; q++) { [self seedMessageSeq:q]; }    // 实时到达的更新一段
    [_db registerRangeInConv:kConv from:1 to:5];
    [_db registerRangeInConv:kConv from:99970 to:100219];
    [_db registerRangeInConv:kConv from:110015 to:110019];

    // 段内 100216..100219 还剩 3 条；limit 给 200 也不能把 110015 那一段捞进来。
    NSArray<IMMessageModel *> *page = [_db contiguousMessagesForConv:kConv afterConvSeq:100216 limit:200];
    NSMutableArray<NSString *> *seqs = [NSMutableArray array];
    for (IMMessageModel *m in page) { [seqs addObject:[NSString stringWithFormat:@"%lld", m.convSeq]]; }
    XCTAssertEqualObjects([seqs componentsJoinedByString:@","], @"100217,100218,100219");
}

- (void)testNewerPageEmptyAtSegmentTail {
    [_db updateHeadConvSeq:110019 forConv:kConv];
    for (int64_t q = 99970; q <= 100219; q++) { [self seedMessageSeq:q]; }
    [_db registerRangeInConv:kConv from:99970 to:100219];
    // 已在本段最后一条：返回空 → 调用方据此改问服务端（此前这里会一直判"到底了"，翻不动）。
    XCTAssertEqual([_db contiguousMessagesForConv:kConv afterConvSeq:100219 limit:200].count, 0u);
}

- (void)testOlderPageEmptyAtSegmentHead {
    [_db updateHeadConvSeq:1000 forConv:kConv];
    for (int64_t q = 996; q <= 1000; q++) { [self seedMessageSeq:q]; }
    [_db registerRangeInConv:kConv from:996 to:1000];
    // 已在本段最早一条：返回空 → 调用方据此改问服务端，而不是拿旧岛顶上。
    XCTAssertEqual([_db contiguousMessagesForConv:kConv beforeConvSeq:996 limit:200].count, 0u);
}

/// 老库（从没登记过区间）必须维持改造前的行为，否则升级即空窗。
- (void)testTailWindowFallsBackWithoutRanges {
    for (int64_t q = 1; q <= 5; q++) { [self seedMessageSeq:q]; }
    XCTAssertEqualObjects([self tailSeqsWithLimit:200], @"1,2,3,4,5");
}

#pragma mark - 连接级簿记

- (void)testMaxGapBySuperFlag {
    IMBacklogTracker *t = [IMBacklogTracker new];
    XCTAssertEqual([t maxGapForConv:@"c1"], IMSyncMaxGap, @"普通会话按分水岭补齐");

    [t setSuper:YES forConv:@"c1"];
    XCTAssertEqual([t maxGapForConv:@"c1"], 0, @"超级群永不自动补拉（正文打开会话时才取）");

    // 两个方向都要生效：只置不清会让一次错误标记永久粘住。
    [t setSuper:NO forConv:@"c1"];
    XCTAssertEqual([t maxGapForConv:@"c1"], IMSyncMaxGap);
}

- (void)testGapMarkAndClear {
    IMBacklogTracker *t = [IMBacklogTracker new];
    XCTAssertFalse([t hasGapForConv:@"c1"]);
    [t markGapForConv:@"c1"];
    XCTAssertTrue([t hasGapForConv:@"c1"]);
    [t clearGapForConv:@"c1"];
    XCTAssertFalse([t hasGapForConv:@"c1"]);
}

- (void)testReceiptsCoalesceToMaxPerConv {
    IMBacklogTracker *t = [IMBacklogTracker new];
    // 第一条要求安排一次 flush；同窗口内后续的都不再安排——否则每条消息各排一个定时器，
    // 补拉 10 万条就是 10 万个定时器，合批也就白做了。
    XCTAssertTrue([t queueReceiptForConv:@"c1" upTo:1]);
    XCTAssertFalse([t queueReceiptForConv:@"c1" upTo:2]);
    XCTAssertFalse([t queueReceiptForConv:@"c2" upTo:7]);

    NSMutableDictionary<NSString *, NSNumber *> *sent = [NSMutableDictionary dictionary];
    [t drainReceipts:^(NSString *convID, int64_t upTo) { sent[convID] = @(upTo); }];
    XCTAssertEqualObjects(sent, (@{ @"c1": @2, @"c2": @7 }), @"每会话只发最大位点（回执是单调位点）");

    // drain 后应清空，且可以重新安排下一轮。
    NSMutableArray *second = [NSMutableArray array];
    [t drainReceipts:^(NSString *convID, int64_t upTo) { [second addObject:convID]; }];
    XCTAssertEqual(second.count, 0);
    XCTAssertTrue([t queueReceiptForConv:@"c1" upTo:3]);
}

- (void)testReceiptsIgnoreInvalidInput {
    IMBacklogTracker *t = [IMBacklogTracker new];
    XCTAssertFalse([t queueReceiptForConv:@"" upTo:5]);
    XCTAssertFalse([t queueReceiptForConv:@"c1" upTo:0]);
}

- (void)testResetClearsEverything {
    IMBacklogTracker *t = [IMBacklogTracker new];
    [t setSuper:YES forConv:@"c1"];
    [t noteHead:99 forConv:@"c1"];
    [t markGapForConv:@"c1"];
    [t queueReceiptForConv:@"c1" upTo:5];

    [t reset];
    // 切账号必须清干净：同一个 conv_id 在两个账号下可见范围不同，串了就是错的。
    XCTAssertEqual([t maxGapForConv:@"c1"], IMSyncMaxGap);
    XCTAssertEqual([t headForConv:@"c1"], 0);
    XCTAssertFalse([t hasGapForConv:@"c1"]);
    XCTAssertTrue([t queueReceiptForConv:@"c1" upTo:1], @"reset 后应能重新安排 flush");
}

@end
