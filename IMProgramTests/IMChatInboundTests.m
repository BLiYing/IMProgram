//  IMChatInboundTests.m
//  聊天页入站处置 + 内存排序（IMChatInbound）。
//
//  这一组的错法全是**静默**的：顺序错 = 用户以为没收到新消息；处置错 = 丢消息或同一条显示两遍。
//  所以按「会怎么错」钉，用例名就是那个错法。
//  与 IMDatabase 的 kIMMessageOrderAsc、im-web 渲染排序、Android MessageOrder.kt 同口径（SYMMETRY 登记）。

#import <XCTest/XCTest.h>

#import "IMChatInbound.h"
#import "IMDatabase.h"
#import "IMMessageModel.h"

@interface IMChatInboundTests : XCTestCase
@end

@implementation IMChatInboundTests

static IMMessageModel *Msg(int64_t ts, int64_t seq) {
    IMMessageModel *m = [[IMMessageModel alloc] init];
    m.timestamp = ts;
    m.convSeq = seq;
    return m;
}

#pragma mark - 排序比较器

/// 时间戳主排：后发出的失败消息（seq=0、时间更大）排在更早收到的消息之后，**不是**一律垫底。
- (void)test_时间戳主排_不看convSeq {
    XCTAssertEqual(IMChatMessageOrder(Msg(100, 9), Msg(200, 1)), NSOrderedAscending);
    XCTAssertEqual(IMChatMessageOrder(Msg(200, 1), Msg(100, 9)), NSOrderedDescending);
}

/// 2026-08-05 事故：被拒收的消息永远 seq=0。旧写法「seq=0 一律甩末尾」让它永久钉底，
/// 之后收到的消息全插到它上面。时间更早的失败消息必须排在**之后**才到的消息前面。
- (void)test_更早的失败消息不钉在更晚收到的消息之后 {
    IMMessageModel *failed = Msg(100, 0);
    IMMessageModel *later = Msg(200, 5);
    XCTAssertEqual(IMChatMessageOrder(failed, later), NSOrderedAscending);
}

/// 同一毫秒：seq=0（待发/失败）垫底，收到的在前。
- (void)test_同毫秒_convSeq为0垫底 {
    XCTAssertEqual(IMChatMessageOrder(Msg(100, 7), Msg(100, 0)), NSOrderedAscending);
    XCTAssertEqual(IMChatMessageOrder(Msg(100, 0), Msg(100, 7)), NSOrderedDescending);
}

/// 同毫秒：都上号则按 seq；都是 0 则视为相等（不能互相「小于」，否则排序不稳定）。
- (void)test_同毫秒_按seq比_两个0相等 {
    XCTAssertEqual(IMChatMessageOrder(Msg(100, 3), Msg(100, 4)), NSOrderedAscending);
    XCTAssertEqual(IMChatMessageOrder(Msg(100, 4), Msg(100, 3)), NSOrderedDescending);
    XCTAssertEqual(IMChatMessageOrder(Msg(100, 0), Msg(100, 0)), NSOrderedSame);
    XCTAssertEqual(IMChatMessageOrder(Msg(100, 3), Msg(100, 3)), NSOrderedSame);
}

#pragma mark - 尾插是否需要重排

/// 空窗口不需要排；按序到达不需要排（省掉每条一次 O(n log n)）。
- (void)test_按序到达不重排 {
    XCTAssertFalse(IMChatInsertNeedsSort(nil, Msg(100, 1)));
    XCTAssertFalse(IMChatInsertNeedsSort(Msg(100, 1), Msg(200, 2)));
    XCTAssertFalse(IMChatInsertNeedsSort(Msg(100, 1), Msg(100, 2)));
}

/// 乱序/补拉插队：落在末条之前必须重排，否则新消息会躺在错误位置。
- (void)test_落在末条之前要重排 {
    XCTAssertTrue(IMChatInsertNeedsSort(Msg(200, 5), Msg(100, 4)));
    XCTAssertTrue(IMChatInsertNeedsSort(Msg(100, 5), Msg(100, 4)));
    // 末条是同毫秒的待发件（seq=0 视为 +∞），新来的上号消息要排到它前面。
    XCTAssertTrue(IMChatInsertNeedsSort(Msg(100, 0), Msg(100, 4)));
}

/// 重排判定与比较器**逐对一致**：判定说「不用排」就不能出现比较器认为 incoming 更小的情况。
- (void)test_重排判定与比较器逐对对拍 {
    int64_t stamps[] = {99, 100, 101};
    int64_t seqs[] = {0, 3, 4};
    for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++)
    for (int k = 0; k < 3; k++) for (int l = 0; l < 3; l++) {
        IMMessageModel *last = Msg(stamps[i], seqs[j]);
        IMMessageModel *incoming = Msg(stamps[k], seqs[l]);
        BOOL expected = IMChatMessageOrder(incoming, last) == NSOrderedAscending;
        XCTAssertEqual(IMChatInsertNeedsSort(last, incoming), expected,
                       @"last=(%lld,%lld) incoming=(%lld,%lld)", stamps[i], seqs[j], stamps[k], seqs[l]);
    }
}

/// **内存比较器与 DB 的 ORDER BY 对拍**（SYMMETRY 登记的事故点：2026-08-05 只改了 DB 没改内存）。
/// 同一批消息——含失败的 seq=0、同毫秒、乱序到达——DB 读出的顺序必须等于内存排序后的顺序。
- (void)test_与DB的ORDER_BY顺序一致 {
    NSString *name = [NSString stringWithFormat:@"im-inbound-test-%@.sqlite", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:url];
    [db useOwnerUserID:@"me"];

    // (ts, seq)：含同毫秒、seq=0 失败件早于/晚于上号消息。
    int64_t rows[][2] = {{300, 0}, {100, 2}, {200, 0}, {200, 5}, {100, 1}, {200, 4}, {400, 7}, {300, 6}};
    NSMutableArray<IMMessageModel *> *mem = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(rows) / sizeof(rows[0]); i++) {
        IMMessageModel *m = [[IMMessageModel alloc] init];
        m.convID = @"c_order";
        m.from = rows[i][1] == 0 ? @"me" : @"peer";
        m.content = [NSString stringWithFormat:@"m%zu", i];
        m.contentType = @"text";
        m.timestamp = rows[i][0];
        m.convSeq = rows[i][1];
        m.status = rows[i][1] == 0 ? IMMessageStatusFailed : IMMessageStatusReceived;
        m.clientMsgID = [NSString stringWithFormat:@"cid-%zu", i];
        m.serverMsgID = rows[i][1] == 0 ? nil : [NSString stringWithFormat:@"sid-%zu", i];
        [db saveMessage:m];
        [mem addObject:m];
    }
    [mem sortUsingComparator:^NSComparisonResult(IMMessageModel *a, IMMessageModel *b) {
        return IMChatMessageOrder(a, b);
    }];
    NSMutableArray<NSString *> *memContents = [NSMutableArray array];
    for (IMMessageModel *m in mem) { [memContents addObject:m.content]; }
    NSMutableArray<NSString *> *dbContents = [NSMutableArray array];
    for (IMMessageModel *m in [db messagesForConv:@"c_order"]) { [dbContents addObject:m.content]; }

    XCTAssertEqual(dbContents.count, mem.count, @"夹具应全部落库");
    XCTAssertEqualObjects(memContents, dbContents);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

#pragma mark - 入站处置

static IMChatInboundDisposition Dispose(BOOL conv, int64_t seq, BOOL seen, BOOL file, BOOL tail, int64_t max) {
    return IMChatInboundDispose(conv, seq, seen, file, tail, max);
}

/// 非本会话：无论其它条件如何都不在此页显示（连「已见过」「窗口在末尾」都不看）。
- (void)test_非本会话一律不上屏 {
    XCTAssertEqual(Dispose(NO, 10, NO, NO, YES, 0), IMChatInboundDropOtherConv);
    XCTAssertEqual(Dispose(NO, 10, YES, YES, NO, 99), IMChatInboundDropOtherConv);
}

/// 同一条既被 new_msg 推送又被 sync_resp 拉到：按 conv_seq 去重，**不能显示两遍**。
- (void)test_已在窗口的消息去重 {
    XCTAssertEqual(Dispose(YES, 10, YES, NO, YES, 5), IMChatInboundDedupDrop);
    // 去重优先于「窗口不在末尾」：窗口在看历史时重复投递照样判重复，不是「只落库」。
    XCTAssertEqual(Dispose(YES, 10, YES, NO, NO, 5), IMChatInboundDedupDrop);
}

/// 去重命中的是带真实字节数的 file：要回填元数据（SQLite 已修成真实 file_size，内存模型不能一直显 0 KB）。
- (void)test_去重命中带字节数的文件要回填 {
    XCTAssertEqual(Dispose(YES, 10, YES, YES, YES, 5), IMChatInboundDedupBackfillFile);
}

/// convSeq<=0（待发/未上号）不参与去重：即便「看起来见过」也不能被当重复吞掉。
- (void)test_未上号消息不参与去重 {
    XCTAssertEqual(Dispose(YES, 0, YES, NO, YES, 5), IMChatInboundAppend);
    XCTAssertEqual(Dispose(YES, -1, YES, NO, YES, 5), IMChatInboundAppend);
}

/// 窗口不在末尾（用户在看历史）：只落库不上屏，否则最新消息会接在几个月前的历史后面。
- (void)test_窗口不在末尾只落库 {
    XCTAssertEqual(Dispose(YES, 100, NO, NO, NO, 5), IMChatInboundDbOnlyHistoryWindow);
    // 待发件同样不能在看历史时硬插到窗口末尾。
    XCTAssertEqual(Dispose(YES, 0, NO, NO, NO, 5), IMChatInboundDbOnlyHistoryWindow);
}

/// 3 万条实测的坑：跳到比同步游标更深的历史后，后台补拉继续送 12001、12002…，
/// 它们 seq 不高于窗口末尾，按时间序会插进窗口**中间**。
- (void)test_低于窗口末尾的补拉消息只落库 {
    XCTAssertEqual(Dispose(YES, 12001, NO, NO, YES, 20000), IMChatInboundDbOnlyBelowTail);
    // 边界：等于窗口末尾也算（<=）。
    XCTAssertEqual(Dispose(YES, 20000, NO, NO, YES, 20000), IMChatInboundDbOnlyBelowTail);
}

/// 高于窗口末尾（正常新消息）才上屏；空窗口（max=0）也上屏。
- (void)test_高于窗口末尾才上屏 {
    XCTAssertEqual(Dispose(YES, 20001, NO, NO, YES, 20000), IMChatInboundAppend);
    XCTAssertEqual(Dispose(YES, 1, NO, NO, YES, 0), IMChatInboundAppend);
}

/// 待发件（seq=0）在窗口贴底时直接上屏：「低于窗口末尾」只管上了号的消息。
- (void)test_待发件在末尾直接上屏 {
    XCTAssertEqual(Dispose(YES, 0, NO, NO, YES, 20000), IMChatInboundAppend);
}

@end
