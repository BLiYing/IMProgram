#import <XCTest/XCTest.h>

#import "IMBacklogTracker.h"
#import "IMDatabase.h"
#import "IMDatabase+ClearFloor.h"
#import "IMDatabase+Ranges.h"
#import "IMMessageModel.h"
#import "IMProtocol.h"
#import "IMSocketManager.h"
#import "IMSocketManager+Private.h"

/// handleWindowResp: 是主实现里的私有方法（没进任何头）；测试只借它的名字调用，不新增实现。
@interface IMSocketManager (ClearFloorTestHooks)
- (void)handleWindowResp:(NSDictionary *)data;
@end

/// 网络层这一半的「清空位点」（OFFLINE_BACKLOG_DESIGN §6.7）：**落库、UI 投递、回执、提醒共用同一份
/// 实际保留集合**（CONVENTIONS §4.7）。库里的落库闸是第二道防线，挡不住「没落库却照常投递 / 回执」——
/// 那种错法界面看不出来，只是多发回执、多投递一条刚清掉的消息。
///
/// 用 `IMSocketManager.sharedManager` + `IMDatabase.sharedDatabase`（私有 ivar 经 KVC 取），
/// 会话 id 每用例唯一、用例末清理，账号用独立 uid 并在末尾还原。
@interface IMSocketClearFloorTests : XCTestCase <IMSocketManagerDelegate>
@end

@implementation IMSocketClearFloorTests {
    IMSocketManager *_mgr;
    IMDatabase *_db;
    NSString *_prevOwner;
    NSString *_conv;
    NSMutableArray<NSNumber *> *_delivered;   // delegate 收到的 conv_seq（主线程）
}

- (dispatch_queue_t)queue { return [_mgr valueForKey:@"_queue"]; }
- (IMBacklogTracker *)backlog { return [_mgr valueForKey:@"_backlog"]; }

- (void)setUp {
    [super setUp];
    _mgr = IMSocketManager.sharedManager;
    _db = IMDatabase.sharedDatabase;
    _prevOwner = _db.ownerUserID;
    IMDatabaseAccountContext *ctx = [_db useOwnerUserID:@"clrfloor_sock_test"];
    [_mgr setValue:ctx forKey:@"_databaseContext"];
    _conv = [NSString stringWithFormat:@"g_clrsock_%@", NSUUID.UUID.UUIDString];
    _delivered = [NSMutableArray array];
    _mgr.delegate = self;
    // 造一条清空过的会话：1..10 落库后清空 → 位点 10、游标 10。
    for (int64_t i = 1; i <= 10; i++) {
        [_db saveIncomingMessage:[self msgSeq:i] advancingSyncedConvSeq:i];
    }
    [_db clearMessagesForConv:_conv];
    XCTAssertEqual([_db clearedUpToForConv:_conv], 10);
}

- (void)tearDown {
    _mgr.delegate = nil;
    [_db clearMessagesForConv:_conv];
    [_db deleteCachedConversation:_conv];
    [_mgr setValue:nil forKey:@"_databaseContext"];
    [_db useOwnerUserID:_prevOwner];
    [super tearDown];
}

- (void)socketManager:(IMSocketManager *)manager didReceiveMessage:(IMMessageModel *)message {
    [_delivered addObject:@(message.convSeq)];
}

#pragma mark - 夹具

- (NSDictionary *)rawSeq:(int64_t)seq {
    return @{ @"server_msg_id": [NSString stringWithFormat:@"%@-%lld", _conv, seq], @"conv_id": _conv,
              @"from": @"peer", @"content": [NSString stringWithFormat:@"#%lld", seq], @"content_type": @"text",
              @"conv_seq": @(seq), @"timestamp": @(1788000000000 + seq) };
}

- (IMMessageModel *)msgSeq:(int64_t)seq { return [IMMessageModel receivedMessageWithNewMsgData:[self rawSeq:seq]]; }

- (NSArray<NSNumber *> *)localSeqs {
    NSMutableArray *out = [NSMutableArray array];
    for (IMMessageModel *m in [_db messagesForConv:_conv]) { [out addObject:@(m.convSeq)]; }
    return out;
}

/// 让主线程上已排队的 delegate 派发跑完。
- (void)flushMain {
    XCTestExpectation *e = [self expectationWithDescription:@"main flushed"];
    dispatch_async(dispatch_get_main_queue(), ^{ [e fulfill]; });
    [self waitForExpectations:@[e] timeout:5];
}

/// 在 socket 队列上执行并抓**回执暂存区快照**（回执 0.12s 后才合批发出，同队列内立即读就不会被抢先 drain）。
- (NSDictionary<NSString *, NSNumber *> *)runOnQueue:(void (^)(void))block {
    __block NSDictionary *pending = @{};
    dispatch_sync([self queue], ^{
        block();
        pending = [[[self backlog] valueForKey:@"_pendingReceipts"] copy] ?: @{};
    });
    [self flushMain];
    return pending;
}

#pragma mark - sync 页

/// 页里跨位点（9..12，位点 10）：只有 11、12 落库、投递，回执位点 = 12（过滤后集合的最大值）。
- (void)test_sync页跨位点只保留位点之上 {
    NSDictionary *resp = @{ @"conversations": @[ @{ @"conv_id": _conv, @"head_conv_seq": @12, @"covered_conv_seq": @12,
        @"messages": @[ [self rawSeq:9], [self rawSeq:10], [self rawSeq:11], [self rawSeq:12] ] } ] };
    NSDictionary *pending = [self runOnQueue:^{ [self->_mgr handleSyncResp:resp]; }];
    XCTAssertEqualObjects([self localSeqs], (@[@11, @12]));
    XCTAssertEqualObjects(_delivered, (@[@11, @12]), @"被丢弃的 9、10 不得投递给 UI");
    XCTAssertEqualObjects(pending[_conv], @12);
}

/// 整页都在位点之内：不落库、不投递、**一个回执都不发**。
- (void)test_sync页整页在位点之内不投递不回执 {
    NSDictionary *resp = @{ @"conversations": @[ @{ @"conv_id": _conv, @"head_conv_seq": @10, @"covered_conv_seq": @10,
        @"messages": @[ [self rawSeq:8], [self rawSeq:9], [self rawSeq:10] ] } ] };
    NSDictionary *pending = [self runOnQueue:^{ [self->_mgr handleSyncResp:resp]; }];
    XCTAssertEqualObjects([self localSeqs], @[]);
    XCTAssertEqualObjects(_delivered, @[]);
    XCTAssertNil(pending[_conv], @"没有任何保留消息就不该发回执");
}

#pragma mark - 实时

- (void)test_实时消息在位点之内不落库不投递不回执 {
    NSDictionary *pending = [self runOnQueue:^{ [self->_mgr processIncomingMessage:[self msgSeq:10] fromSync:NO syncAdvanceSeq:0]; }];
    XCTAssertEqualObjects([self localSeqs], @[]);
    XCTAssertEqualObjects(_delivered, @[]);
    XCTAssertNil(pending[_conv]);
}

- (void)test_实时消息在位点之上照常 {
    NSDictionary *pending = [self runOnQueue:^{ [self->_mgr processIncomingMessage:[self msgSeq:11] fromSync:NO syncAdvanceSeq:0]; }];
    XCTAssertEqualObjects([self localSeqs], @[@11]);
    XCTAssertEqualObjects(_delivered, @[@11]);
    XCTAssertEqualObjects(pending[_conv], @11);
}

#pragma mark - window 页

/// 跨位点窗口（9..12，位点 10）：≤位点的行不进库；区间仍按整窗 [9,12] 登记（口径不变）；
/// 可见下界只算「留下的行」（11），不得落在被丢的 9 上。
- (void)test_window跨位点 {
    NSDictionary *resp = @{ @"conv_id": _conv, @"anchor": @12, @"anchor_found": @YES, @"has_before": @NO, @"has_after": @NO,
        @"messages": @[ [self rawSeq:9], [self rawSeq:10], [self rawSeq:11], [self rawSeq:12] ] };
    [self runOnQueue:^{ [self->_mgr handleWindowResp:resp]; }];
    XCTAssertEqualObjects([self localSeqs], (@[@11, @12]));
    XCTAssertTrue([_db conv:_conv coversFrom:9 to:12]);
    XCTAssertEqual([_mgr historyFloorForConv:_conv], 11, @"下界 = 留下的行的最小 seq，不是整窗最小");
}

#pragma mark - noteConvClearedUpTo 与缺口标记

- (void)test_清空通知_位点追上head才撤缺口_游标只增不减 {
    IMBacklogTracker *b = [self backlog];
    dispatch_sync([self queue], ^{
        [b markGapForConv:self->_conv];
        [b noteHead:100 forConv:self->_conv];
    });
    [_mgr noteConvClearedUpTo:50 forConv:_conv];
    dispatch_sync([self queue], ^{});
    XCTAssertTrue([_mgr hasGapInConv:_conv], @"位点(50)没追上 head(100)：位点之上仍有缺口，标记不能撤");
    XCTAssertEqual([self syncedInMem], 50);

    [_mgr noteConvClearedUpTo:100 forConv:_conv];
    dispatch_sync([self queue], ^{});
    XCTAssertFalse([_mgr hasGapInConv:_conv], @"位点追上 head：整段都是用户不要的，没有缺口了");
    [_mgr noteConvClearedUpTo:20 forConv:_conv];
    dispatch_sync([self queue], ^{});
    XCTAssertEqual([self syncedInMem], 100, @"内存游标只增不减");
}

/// 超级群（max_gap=0）：正文只在打开会话时按需拉，sync 永远回 too_long、缺口标记常驻。
/// 清空到 head 后标记被撤；之后又来新的 too_long 会重新标记（位点之上确有没下的）。
- (void)test_超级群清空后缺口标记 {
    IMBacklogTracker *b = [self backlog];
    dispatch_sync([self queue], ^{
        [b setSuper:YES forConv:self->_conv];
        [b markGapForConv:self->_conv];
        [b noteHead:5000 forConv:self->_conv];
    });
    [_mgr noteConvClearedUpTo:5000 forConv:_conv];
    dispatch_sync([self queue], ^{});
    XCTAssertFalse([_mgr hasGapInConv:_conv]);
    XCTAssertEqual([b maxGapForConv:_conv], 0, @"超级群 max_gap 恒 0 不受清空影响");
    dispatch_sync([self queue], ^{ [b markGapForConv:self->_conv]; });
    XCTAssertTrue([_mgr hasGapInConv:_conv], @"新来的 too_long 照常重新标记");
}

- (int64_t)syncedInMem {
    __block int64_t v = 0;
    dispatch_sync([self queue], ^{ v = [self->_mgr syncedSeqForConv:self->_conv]; });
    return v;
}

@end
