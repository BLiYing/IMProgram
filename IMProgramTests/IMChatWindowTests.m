#import <XCTest/XCTest.h>

#import "IMDatabase.h"
#import "IMDatabase+Ranges.h"   // countIncomingInConv: 等区间清单相关查询
#import "IMMessageModel.h"

// IMChatViewController+Window.m 里的文件级纯函数（同 IMPinnedTargetRecalled 的套路：
// 判据抽出来单测，免构造依赖数据库与 UIKit 的真 VC）。
FOUNDATION_EXPORT BOOL IMChatEntryHasUnread(NSInteger entryUnread);
FOUNDATION_EXPORT int64_t IMChatEntryWindowAnchor(int64_t readSeq);

/// 消息窗口的**本地库契约**（设计见 IMServer/docs/design/MESSAGE_WINDOW_DESIGN.md）。
///
/// 这些查询是分页的地基，且它们的错法都是**静默**的：顺序反了、边界差一条、待发消息漏掉，
/// 界面照常渲染，只是内容不对。故按"会怎么错"来钉，而不是按"接口长什么样"来测：
///   ① 三个窗口查询**返回序一致（升序）**——不一致时拼窗口会把顺序弄反且没人报错；
///   ② before 段与 latest 段**接得上**（不重不漏）；
///   ③ latest 恒含待发消息（conv_seq==0），漏掉的表现是"刚发的消息看不见"；
///   ④ around 的锚点是**位点不是行**——进会话要用已读位点开窗，那个值未必对应任何一行；
///   ⑤ 搜索/日历/发件人候选必须**跨窗口**命中，否则会静默退化成"只搜看得见的这一窗"。
@interface IMChatWindowTests : XCTestCase
@end

@implementation IMChatWindowTests {
    IMDatabase *_db;
    NSURL *_url;
}

static NSString * const kConv = @"g_window";
static NSString * const kMe = @"me";

- (void)setUp {
    [super setUp];
    NSString *name = [NSString stringWithFormat:@"im-window-test-%@.sqlite", NSUUID.UUID.UUIDString];
    _url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    _db = [[IMDatabase alloc] initWithFileURL:_url];
    [_db useOwnerUserID:kMe];
}

- (void)tearDown {
    [NSFileManager.defaultManager removeItemAtURL:_url error:NULL];
    [super tearDown];
}

#pragma mark - 造数

/// 灌 n 条消息，conv_seq = 1..n，timestamp 与 conv_seq 同序（服务端就是同一事务里分配的两个值）。
/// 偶数条来自 peer、奇数条来自我——用来验"↓N 只数对端的"。
- (void)seedMessages:(NSInteger)n {
    for (NSInteger i = 1; i <= n; i++) {
        IMMessageModel *m = [IMMessageModel new];
        m.convID = kConv;
        m.from = (i % 2 == 0) ? @"peer" : kMe;
        m.to = kConv;
        m.contentType = @"text";
        m.content = [NSString stringWithFormat:@"msg-%ld", (long)i];
        m.convSeq = i;
        m.timestamp = 1700000000000LL + i * 1000;
        [_db saveMessage:m];
    }
}

/// 一条待发/失败消息（conv_seq==0，语义上恒在会话末尾）。
- (void)seedPendingWithContent:(NSString *)content {
    IMMessageModel *m = [IMMessageModel new];
    m.convID = kConv;
    m.from = kMe;
    m.to = kConv;
    m.contentType = @"text";
    m.content = content;
    m.clientMsgID = content;
    m.convSeq = 0;
    m.timestamp = 1700000000000LL + 999999;
    [_db saveMessage:m];
}

- (NSArray<NSNumber *> *)seqsOf:(NSArray<IMMessageModel *> *)msgs {
    NSMutableArray<NSNumber *> *out = [NSMutableArray array];
    for (IMMessageModel *m in msgs) { [out addObject:@(m.convSeq)]; }
    return out;
}

#pragma mark - ①②③ 三个窗口查询的共同契约

- (void)testLatestReturnsTailAscendingIncludingPending {
    [self seedMessages:500];
    [self seedPendingWithContent:@"还没发出去的"];

    NSArray<IMMessageModel *> *win = [_db latestMessagesForConv:kConv limit:200];
    XCTAssertEqual(win.count, 200u);
    // 升序，且**待发那条占掉一个名额**：200 = 已上号 302..500（199 条）+ 待发 1 条。
    // 写成 msg-301 会红——这正是"待发消息属于最新一窗"的直接证据。
    XCTAssertEqualObjects(win.firstObject.content, @"msg-302");
    // **待发消息必须在末尾**：漏掉它的表现是"刚发的消息看不见"，im-web 踩过同一个坑。
    XCTAssertEqualObjects(win.lastObject.content, @"还没发出去的");
    XCTAssertEqual(win.lastObject.convSeq, 0);
    XCTAssertEqual(win[198].convSeq, 500);
}

- (void)testBeforeStitchesWithLatestWithoutGapOrOverlap {
    [self seedMessages:500];
    NSArray<IMMessageModel *> *tail = [_db latestMessagesForConv:kConv limit:100];  // 401..500
    NSArray<IMMessageModel *> *older = [_db messagesForConv:kConv beforeConvSeq:tail.firstObject.convSeq limit:100];

    XCTAssertEqual(older.count, 100u);
    XCTAssertEqual(older.firstObject.convSeq, 301); // 同为升序
    // 不重不漏：older 的末条 + 1 == tail 的首条。差一条在界面上就是"翻页后少了/多了一条"。
    XCTAssertEqual(older.lastObject.convSeq, 400);
    XCTAssertEqual(older.lastObject.convSeq + 1, tail.firstObject.convSeq);
    // before 段**不含**待发消息（它们不在任何 conv_seq 区间里，只属于末尾那一窗）。
    for (IMMessageModel *m in older) { XCTAssertGreaterThan(m.convSeq, 0); }
}

- (void)testBeforeAtConversationStartReturnsFewerAndStopsAtOne {
    [self seedMessages:50];
    NSArray<IMMessageModel *> *older = [_db messagesForConv:kConv beforeConvSeq:10 limit:100];
    XCTAssertEqual(older.count, 9u);          // 1..9
    XCTAssertEqual(older.firstObject.convSeq, 1);
    XCTAssertEqual(older.lastObject.convSeq, 9);
    // 到 1 之后再翻就是空——客户端据此把"上面还有更早的"关掉。
    XCTAssertEqual([_db messagesForConv:kConv beforeConvSeq:1 limit:100].count, 0u);
}

#pragma mark - ④ around 的锚点是位点不是行

- (void)testAroundCentersOnAnchorAndIncludesIt {
    [self seedMessages:500];
    NSArray<IMMessageModel *> *win = [_db messagesForConv:kConv aroundConvSeq:250 before:100 after:100];
    XCTAssertEqual(win.count, 200u);
    XCTAssertEqual(win.firstObject.convSeq, 151);
    XCTAssertEqual(win.lastObject.convSeq, 350);
    // 锚点自己在 before 段末尾（第 100 条）——跳转要高亮的就是它，丢了就白跳。
    XCTAssertEqual(win[99].convSeq, 250);
}

- (void)testAroundAcceptsAPositionThatIsNotAnyRow {
    // 进会话按「已读位点」开窗，而那个位点可能指向一条已被删除/对我不可见的消息。
    // 删掉 250 后仍要以 250 这个**位点**切分，而不是返回空。
    [self seedMessages:500];
    IMMessageModel *gone = [_db messageInConv:kConv convSeq:250];
    XCTAssertNotNil(gone);
    [_db deleteMessage:gone];

    NSArray<IMMessageModel *> *win = [_db messagesForConv:kConv aroundConvSeq:250 before:3 after:3];
    XCTAssertEqualObjects([self seqsOf:win], (@[@247, @248, @249, @251, @252, @253]));
}

- (void)testAroundZeroGivesConversationHead {
    [self seedMessages:20];
    NSArray<IMMessageModel *> *win = [_db messagesForConv:kConv aroundConvSeq:0 before:5 after:5];
    XCTAssertEqualObjects([self seqsOf:win], (@[@1, @2, @3, @4, @5])); // 位点 0 之前什么也没有
}

#pragma mark - ⑥ 进会话取哪一窗（首次登录 = readSeq 0）

/// 判据只认真实未读数。两个曾被写进来的附加条件都会把「有未读」误判成「无未读」：
/// `readSeq>0` 坑首次登录的新成员，`latest>read` 坑刚灌完消息的发送方。
- (void)testEntryHasUnreadIgnoresReadSeqAndLatest {
    XCTAssertTrue(IMChatEntryHasUnread(10000));   // 首次登录：readSeq=0 照样是有未读
    XCTAssertTrue(IMChatEntryHasUnread(1));
    XCTAssertFalse(IMChatEntryHasUnread(0));      // 发送方：latest 领先一万条也仍是无未读 → 贴底
    XCTAssertFalse(IMChatEntryHasUnread(-1));
}

/// 向服务端开窗的 anchor 不能是 0——协议里那是「取最新一窗」，与"会话开头"正好相反。
- (void)testEntryWindowAnchorNeverZero {
    XCTAssertEqual(IMChatEntryWindowAnchor(0), 1);    // 从没读过 → 会话开头，不是最新
    XCTAssertEqual(IMChatEntryWindowAnchor(-5), 1);
    XCTAssertEqual(IMChatEntryWindowAnchor(1), 1);
    XCTAssertEqual(IMChatEntryWindowAnchor(109820), 109820);
}

/// 首次登录进大群的首屏：按读位点(0)开窗拿到的是**会话开头**那一页，
/// 而不是 `latestContiguousMessagesForConv:` 那一段（判据写错时首屏就是后者，
/// 用户停在倒数第 200 条上、随后被「可见即读」把十万条未读一次清零）。
- (void)testNeverReadEntryOpensHeadNotTail {
    [self seedMessages:1000];
    NSArray<IMMessageModel *> *entry = [_db messagesForConv:kConv aroundConvSeq:0 before:50 after:200];
    NSArray<IMMessageModel *> *tail = [_db latestContiguousMessagesForConv:kConv limit:200];
    XCTAssertEqual(entry.firstObject.convSeq, 1);
    XCTAssertEqual(entry.lastObject.convSeq, 200);
    XCTAssertEqual(tail.firstObject.convSeq, 801);   // 两段不能是同一段，否则这条测试什么也没测
    XCTAssertEqual(tail.lastObject.convSeq, 1000);
}

#pragma mark - ↓N 计数

- (void)testCountIncomingExcludesMyOwnMessages {
    [self seedMessages:100]; // 偶数来自 peer
    XCTAssertEqual([_db countIncomingInConv:kConv afterConvSeq:0], 50);
    XCTAssertEqual([_db countIncomingInConv:kConv afterConvSeq:90], 5); // 92 94 96 98 100
    XCTAssertEqual([_db countIncomingInConv:kConv afterConvSeq:100], 0);
}

#pragma mark - ⑤ 搜索 / 日历 / 发件人候选必须跨窗口

- (void)testSearchFindsHitsOutsideAnySingleWindow {
    [self seedMessages:500];
    IMMessageModel *needle = [_db messageInConv:kConv convSeq:7];
    needle.content = @"很久以前的暗号";
    [_db saveMessage:needle];

    NSArray<NSNumber *> *hits = [_db searchConvSeqsInConv:kConv keyword:@"暗号" fromUID:nil limit:0];
    // 第 7 条离末尾 493 条，任何一窗（200）都够不着——扫内存的实现在这里会返回空。
    XCTAssertEqualObjects(hits, @[@7]);
}

- (void)testSearchBySenderOnlyAndAscendingOrder {
    [self seedMessages:20];
    NSArray<NSNumber *> *hits = [_db searchConvSeqsInConv:kConv keyword:@"" fromUID:@"peer" limit:0];
    XCTAssertEqualObjects(hits, (@[@2, @4, @6, @8, @10, @12, @14, @16, @18, @20])); // 升序，只有对端的
    XCTAssertEqual([_db searchConvSeqsInConv:kConv keyword:@"" fromUID:nil limit:0].count, 0u); // 两者皆空=不搜
}

- (void)testSearchExcludesRecalled {
    [self seedMessages:10];
    IMMessageModel *m = [_db messageInConv:kConv convSeq:4];
    m.content = @"暗号";
    m.recalledAt = 1700000009000;
    [_db saveMessage:m];
    XCTAssertEqual([_db searchConvSeqsInConv:kConv keyword:@"暗号" fromUID:nil limit:0].count, 0u);
}

- (void)testFirstConvSeqAtOrAfterCoversEarliestAndByDay {
    [self seedMessages:30];
    XCTAssertEqual([_db firstConvSeqInConv:kConv atOrAfterTimestamp:0], 1);           // 「跳到最早」
    XCTAssertEqual([_db firstConvSeqInConv:kConv atOrAfterTimestamp:1700000010000LL], 10);
    XCTAssertEqual([_db firstConvSeqInConv:kConv atOrAfterTimestamp:1799999999999LL], 0); // 之后没有了
}

- (void)testDistinctSenderSamplesGiveOneLatestRowPerSender {
    [self seedMessages:20]; // me 与 peer 交替
    NSArray<IMMessageModel *> *samples = [_db distinctSenderSamplesInConv:kConv limit:0];
    XCTAssertEqual(samples.count, 2u);
    NSMutableDictionary<NSString *, NSNumber *> *bySender = [NSMutableDictionary dictionary];
    for (IMMessageModel *m in samples) { bySender[m.from] = @(m.convSeq); }
    XCTAssertEqualObjects(bySender[@"peer"], @20); // 各取最新一条（面板要显示的昵称/头像取自它）
    XCTAssertEqualObjects(bySender[kMe], @19);
}

- (void)testActiveDaysBucketsByLocalDay {
    // 三条消息落在两个本地日（按测试机当前时区偏移分桶，与实现同一口径）。
    int64_t offset = (int64_t)NSTimeZone.systemTimeZone.secondsFromGMT * 1000;
    int64_t dayA = (1700000000000LL + offset) / 86400000LL * 86400000LL - offset; // 那天 0 点
    for (int i = 0; i < 3; i++) {
        IMMessageModel *m = [IMMessageModel new];
        m.convID = kConv; m.from = @"peer"; m.contentType = @"text"; m.content = @"x";
        m.convSeq = 100 + i;
        m.timestamp = (i < 2) ? dayA + 3600000LL * (i + 1) : dayA + 86400000LL + 3600000LL;
        [_db saveMessage:m];
    }
    NSArray<NSNumber *> *days = [_db activeLocalDayStartsInConv:kConv utcOffsetMs:offset];
    XCTAssertEqualObjects(days, (@[@(dayA), @(dayA + 86400000LL)]));
}

- (void)testMediaMessagesSpanWholeConversation {
    [self seedMessages:400];
    for (NSNumber *seq in @[@3, @200, @399]) {
        IMMessageModel *m = [_db messageInConv:kConv convSeq:seq.longLongValue];
        m.contentType = @"image";
        m.content = @"/uploads/a.jpg";
        [_db saveMessage:m];
    }
    IMMessageModel *recalled = [_db messageInConv:kConv convSeq:200];
    recalled.recalledAt = 1700000009000;
    [_db saveMessage:recalled];

    NSArray<IMMessageModel *> *media = [_db mediaMessagesForConv:kConv];
    // 跨整个会话取（第 3 条离末尾 397 条），且撤回的不算——查看器左右翻页据此排片。
    XCTAssertEqualObjects([self seqsOf:media], (@[@3, @399]));
}

#pragma mark - 按 client_msg_id 取发件行（ack 回来时目标已不在窗口）

- (void)testMessageByClientMsgIDFindsPendingOutsideWindow {
    [self seedMessages:500];
    [self seedPendingWithContent:@"发送中"];
    IMMessageModel *row = [_db messageInConv:kConv clientMsgID:@"发送中"];
    XCTAssertNotNil(row);
    XCTAssertEqual(row.convSeq, 0);
    XCTAssertNil([_db messageInConv:kConv clientMsgID:@"不存在的"]);
}

@end
