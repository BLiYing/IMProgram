//  IMSocketFrameTests.m
//  收帧分发（handleFrame）与已读回执（handleReceipt）。
//
//  错法全是**静默**的：已读错端（对端读了却把「我自己的未读」清掉，或反过来）、非法帧把连接读线程带崩、
//  超级群 bump 不标缺口导致 ↓N 永远不对、消息操作被拒却没人回滚提示。所以按「会怎么错」钉，用例名就是那个错法。
//
//  脚手架同 IMSocketClearFloorTests：`IMSocketManager.sharedManager` + `IMDatabase.sharedDatabase`，
//  私有方法只借名字调用；会话 id 每用例唯一、用例末清理，账号用独立 uid 并在末尾还原。

#import <XCTest/XCTest.h>

#import "IMBacklogTracker.h"
#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMDatabase+ClearFloor.h"
#import "IMDatabase+Ranges.h"
#import "IMMessageModel.h"
#import "IMProtocol.h"
#import "IMSocketManager.h"
#import "IMSocketManager+Private.h"

@interface IMSocketManager (FrameTestHooks)
- (void)handleFrame:(NSString *)text;
@end

@interface IMSocketFrameTests : XCTestCase <IMSocketManagerDelegate>
@end

@implementation IMSocketFrameTests {
    IMSocketManager *_mgr;
    IMDatabase *_db;
    NSString *_prevOwner;
    NSString *_prevUserID;
    NSString *_conv;
    NSMutableArray<NSDictionary *> *_reads;   // delegate 收到的 didReadConv：{from, upTo}
}

static NSString * const kMe = @"frame_me";
static NSString * const kPeer = @"frame_peer";

- (dispatch_queue_t)queue { return [_mgr valueForKey:@"_queue"]; }
- (IMBacklogTracker *)backlog { return [_mgr valueForKey:@"_backlog"]; }

- (void)setUp {
    [super setUp];
    _mgr = IMSocketManager.sharedManager;
    _db = IMDatabase.sharedDatabase;
    _prevOwner = _db.ownerUserID;
    _prevUserID = _mgr.userID;
    IMDatabaseAccountContext *ctx = [_db useOwnerUserID:kMe];
    [_mgr setValue:ctx forKey:@"_databaseContext"];
    _mgr.userID = kMe;
    _conv = [NSString stringWithFormat:@"u_frame_%@", NSUUID.UUID.UUIDString];
    _reads = [NSMutableArray array];
    _mgr.delegate = self;
    // 建会话行：收一条对端消息（readSeq/peerReadSeq 都从 0 起）。
    [_db saveIncomingMessage:[self msgSeq:1] advancingSyncedConvSeq:1];
}

- (void)tearDown {
    _mgr.delegate = nil;
    dispatch_sync(self.queue, ^{
        [(NSMutableDictionary *)[self->_mgr valueForKey:@"_syncedSeq"] removeObjectForKey:self->_conv];
        [[self backlog] clearGapForConv:self->_conv];
    });
    [_db clearMessagesForConv:_conv];
    [_db deleteCachedConversation:_conv];
    [_mgr setValue:nil forKey:@"_databaseContext"];
    _mgr.userID = _prevUserID;
    [_db useOwnerUserID:_prevOwner];
    [super tearDown];
}

- (void)socketManager:(IMSocketManager *)manager didReadConv:(NSString *)convID by:(NSString *)from upToConvSeq:(int64_t)convSeq {
    [_reads addObject:@{ @"conv": convID, @"from": from, @"upTo": @(convSeq) }];
}

#pragma mark - 夹具

- (IMMessageModel *)msgSeq:(int64_t)seq {
    return [IMMessageModel receivedMessageWithNewMsgData:@{
        @"server_msg_id": [NSString stringWithFormat:@"%@-%lld", _conv, seq], @"conv_id": _conv, @"from": kPeer,
        @"content": @"x", @"content_type": @"text", @"conv_seq": @(seq), @"timestamp": @(1788000000000 + seq) }];
}

- (void)flushMain {
    XCTestExpectation *e = [self expectationWithDescription:@"main"];
    dispatch_async(dispatch_get_main_queue(), ^{ [e fulfill]; });
    [self waitForExpectations:@[e] timeout:5];
}

/// 把一帧交给 handleFrame（在 socket 队列上），再排空主线程派发。
- (void)feed:(NSDictionary *)envelope {
    NSData *d = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:NULL];
    [self feedRaw:[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]];
}

- (void)feedRaw:(NSString *)text {
    dispatch_sync(self.queue, ^{ [self->_mgr handleFrame:text]; });
    [self flushMain];
}

- (IMConversation *)conv { return [_db cachedConversationWithID:_conv]; }

- (NSDictionary *)receipt:(NSString *)status from:(NSString *)from upTo:(int64_t)upTo {
    return @{ @"type": kIMTypeReceipt, @"data": @{ @"conv_id": _conv, @"status": status, @"from": from, @"up_to_conv_seq": @(upTo) } };
}

#pragma mark - 已读回执：别把读位点写到错的一端

/// 对端读了我发的 → 只推进 peerReadSeq（单聊「我发的」变 ✓✓），**不能**动我自己的 readSeq。
- (void)test_对端已读只推进peerReadSeq不动我的readSeq {
    [self feed:[self receipt:@"read" from:kPeer upTo:5]];
    XCTAssertEqual([self conv].peerReadSeq, 5);
    XCTAssertEqual([self conv].readSeq, 0);
    XCTAssertEqual(_reads.count, 1u);
    XCTAssertEqualObjects(_reads[0][@"from"], kPeer);
}

/// 我的另一个设备读了（from == 我自己）→ 推进**我的** readSeq（多端已读同步、未读清零），**不能**动 peerReadSeq。
- (void)test_本人其它端已读只推进我的readSeq不动peerReadSeq {
    [self feed:[self receipt:@"read" from:kMe upTo:1]];
    XCTAssertEqual([self conv].readSeq, 1);
    XCTAssertEqual([self conv].peerReadSeq, 0);
    XCTAssertEqualObjects(_reads[0][@"from"], kMe);
}

/// delivered（单勾）本端不显示：不能写任何位点、也不通知 UI。
- (void)test_delivered回执被忽略 {
    [self feed:[self receipt:@"delivered" from:kPeer upTo:5]];
    XCTAssertEqual([self conv].peerReadSeq, 0);
    XCTAssertEqual(_reads.count, 0u);
}

/// 缺 conv_id：忽略，不崩。
- (void)test_回执缺会话id被忽略 {
    [self feed:@{ @"type": kIMTypeReceipt, @"data": @{ @"status": @"read", @"from": kPeer, @"up_to_conv_seq": @5 } }];
    XCTAssertEqual(_reads.count, 0u);
    XCTAssertEqual([self conv].peerReadSeq, 0);
}

/// 已读位点只增不减：乱序到达的旧回执不能把位点拉回去（否则 ✓✓ 又变回 ✓）。
- (void)test_已读位点只增不减 {
    [self feed:[self receipt:@"read" from:kPeer upTo:9]];
    [self feed:[self receipt:@"read" from:kPeer upTo:5]];
    XCTAssertEqual([self conv].peerReadSeq, 9);
}

#pragma mark - 分发：坏帧不能带崩

/// 非 JSON / 不是对象：丢弃，不崩、不投递。
- (void)test_非法信封丢弃不崩 {
    [self feedRaw:@"not json at all"];
    [self feedRaw:@"[1,2,3]"];
    [self feedRaw:@"\"just a string\""];
    [self feedRaw:@""];
    XCTAssertEqual(_reads.count, 0u);
}

/// data 不是字典：回退成 {}，对应处理函数读到空字段、安静返回（不能因为 `data[@"x"]` 对 NSString 取下标而崩）。
- (void)test_data不是字典按空处理 {
    [self feed:@{ @"type": kIMTypeReceipt, @"data": @"oops" }];
    [self feed:@{ @"type": kIMTypeAck, @"data": @[@1] }];
    [self feed:@{ @"type": kIMTypeMsgOp, @"data": @42 }];
    XCTAssertEqual(_reads.count, 0u);
}

/// 未知 type：走附加分发，不崩、不投递。
- (void)test_未知type安静忽略 {
    [self feed:@{ @"type": @"from_the_future", @"data": @{ @"a": @1 } }];
    [self feed:@{ @"data": @{} }]; // 连 type 都没有
    XCTAssertEqual(_reads.count, 0u);
}

#pragma mark - conv_bump（超级群轻量信号）

- (NSDictionary *)bump:(NSArray *)items { return @{ @"type": kIMTypeConvBump, @"data": @{ @"items": items } }; }

/// 本地位点落后于服务端最新：标缺口 + 记 head（正文按需再取，不全量补拉）；广播给列表刷预览。
- (void)test_bump领先本地位点标缺口记head {
    XCTestExpectation *posted = [self expectationForNotification:IMSocketDidReceiveConvBumpNotification object:_mgr handler:^BOOL(NSNotification *n) {
        return [n.userInfo[@"items"] count] == 1;
    }];
    [self feed:[self bump:@[ @{ @"conv_id": self->_conv, @"latest_seq": @50, @"preview": @"hi" } ]]];
    [self waitForExpectations:@[posted] timeout:5];
    __block BOOL gap = NO; __block int64_t head = 0;
    dispatch_sync(self.queue, ^{ gap = [[self backlog] hasGapForConv:self->_conv]; head = [[self backlog] headForConv:self->_conv]; });
    XCTAssertTrue(gap, @"位点 1 < latest 50：这个会话现在有缺口");
    XCTAssertEqual(head, 50);
}

/// 本地已追平（latest <= 已同步位点）：不能标缺口，否则 ↓N 永远多算、进会话白跑一次补拉。
- (void)test_bump没领先本地位点不标缺口 {
    // 内存同步位点（_syncedSeq）由 trackConversation / sync 填充；这里直接设成「已追平到 1」。
    dispatch_sync(self.queue, ^{ [(NSMutableDictionary *)[self->_mgr valueForKey:@"_syncedSeq"] setObject:@1 forKey:self->_conv]; });
    [self feed:[self bump:@[ @{ @"conv_id": self->_conv, @"latest_seq": @1 } ]]];
    __block BOOL gap = YES;
    dispatch_sync(self.queue, ^{ gap = [[self backlog] hasGapForConv:self->_conv]; });
    XCTAssertFalse(gap);
}

/// 脏项（非字典 / 缺 conv_id）跳过；latest<=0 的项不记 head 也不标缺口，但仍广播（列表可能只想刷预览）。
- (void)test_bump脏项跳过 {
    XCTestExpectation *posted = [self expectationForNotification:IMSocketDidReceiveConvBumpNotification object:_mgr handler:^BOOL(NSNotification *n) {
        return [n.userInfo[@"items"] count] == 1; // 只有合法的那一项被广播
    }];
    [self feed:[self bump:@[ @"junk", @42, @{ @"latest_seq": @9 }, @{ @"conv_id": @"" }, @{ @"conv_id": self->_conv, @"latest_seq": @0 } ]]];
    [self waitForExpectations:@[posted] timeout:5];
    __block int64_t head = -1; __block BOOL gap = YES;
    dispatch_sync(self.queue, ^{ head = [[self backlog] headForConv:self->_conv]; gap = [[self backlog] hasGapForConv:self->_conv]; });
    XCTAssertEqual(head, 0);
    XCTAssertFalse(gap);
}

#pragma mark - error 帧

/// 消息操作被拒（撤回超时等）：广播回滚提示，并把它从在途操作集合摘掉（否则内存泄漏、下次同 id 误判）。
- (void)test_消息操作被拒广播提示并摘掉在途 {
    dispatch_sync(self.queue, ^{ [[self->_mgr valueForKey:@"_pendingOps"] addObject:@"op-1"]; });
    XCTestExpectation *rejected = [self expectationForNotification:IMSocketDidRejectMsgOpNotification object:_mgr handler:^BOOL(NSNotification *n) {
        return [n.userInfo[@"message"] isEqualToString:@"recall window passed"];
    }];
    [self feed:@{ @"type": kIMTypeError, @"data": @{ @"client_msg_id": @"op-1", @"code": @300008, @"message": @"recall window passed" } }];
    [self waitForExpectations:@[rejected] timeout:5];
    __block BOOL still = YES;
    dispatch_sync(self.queue, ^{ still = [[self->_mgr valueForKey:@"_pendingOps"] containsObject:@"op-1"]; });
    XCTAssertFalse(still);
}

/// 消息操作被拒但没带 message：用通用文案，不能广播空串（用户会看到一个空 toast）。
- (void)test_消息操作被拒缺message用通用文案 {
    dispatch_sync(self.queue, ^{ [[self->_mgr valueForKey:@"_pendingOps"] addObject:@"op-2"]; });
    XCTestExpectation *rejected = [self expectationForNotification:IMSocketDidRejectMsgOpNotification object:_mgr handler:^BOOL(NSNotification *n) {
        return [n.userInfo[@"message"] length] > 0;
    }];
    [self feed:@{ @"type": kIMTypeError, @"data": @{ @"client_msg_id": @"op-2", @"code": @300008 } }];
    [self waitForExpectations:@[rejected] timeout:5];
}

/// 不带 client_msg_id 的 error：只记日志，不广播任何回滚提示。
- (void)test_无cmid的error不广播 {
    XCTestExpectation *none = [self expectationForNotification:IMSocketDidRejectMsgOpNotification object:_mgr handler:nil];
    none.inverted = YES;
    [self feed:@{ @"type": kIMTypeError, @"data": @{ @"code": @500, @"message": @"boom" } }];
    [self waitForExpectations:@[none] timeout:0.3];
}

#pragma mark - msg_hidden

/// 「仅为我删除」多端同步：本人另一端删了 → 本端物理移除那条。
- (void)test_msg_hidden移除本地消息 {
    [_db saveIncomingMessage:[self msgSeq:2] advancingSyncedConvSeq:2];
    XCTAssertEqual([_db messagesForConv:_conv].count, 2u);
    [self feed:@{ @"type": kIMTypeMsgHidden, @"data": @{ @"conv_id": _conv, @"conv_seq": @2 } }];
    NSMutableArray *seqs = [NSMutableArray array];
    for (IMMessageModel *m in [_db messagesForConv:_conv]) { [seqs addObject:@(m.convSeq)]; }
    XCTAssertEqualObjects(seqs, @[@1]);
}

@end
