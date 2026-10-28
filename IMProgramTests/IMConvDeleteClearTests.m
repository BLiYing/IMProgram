#import <XCTest/XCTest.h>

#import "IMBacklogTracker.h"
#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMDatabase+ClearFloor.h"
#import "IMDatabase+Ranges.h"
#import "IMMessageModel.h"
#import "IMSocketManager.h"
#import "IMSocketManager+ConvClear.h"
#import "IMSocketManager+Private.h"

/// 「删除会话」＝ 清空聊天记录 + 隐藏会话（OFFLINE_BACKLOG_DESIGN §6.7.1）：统一「清除到位点」例程的三个触发点。
/// 错法全是静默的：位点没写 / 没取 max / 快照没追平 / 服务端下界缓存没丢 → 界面照常，只是对方再发消息后旧历史冒出来。
/// 脚手架同 IMSocketClearFloorTests（sharedManager + sharedDatabase，会话 id 每用例唯一，账号独立并还原）。
@interface IMConvDeleteClearTests : XCTestCase
@end

@implementation IMConvDeleteClearTests {
    IMSocketManager *_mgr;
    IMDatabase *_db;
    NSString *_prevOwner;
    NSString *_conv;
}

- (dispatch_queue_t)queue { return [_mgr valueForKey:@"_queue"]; }
- (IMBacklogTracker *)backlog { return [_mgr valueForKey:@"_backlog"]; }

- (void)setUp {
    [super setUp];
    _mgr = IMSocketManager.sharedManager;
    _db = IMDatabase.sharedDatabase;
    _prevOwner = _db.ownerUserID;
    IMDatabaseAccountContext *ctx = [_db useOwnerUserID:@"convdel_clear_test"];
    [_mgr setValue:ctx forKey:@"_databaseContext"];
    _conv = [NSString stringWithFormat:@"g_cdel_%@", NSUUID.UUID.UUIDString];
    for (int64_t i = 1; i <= 10; i++) { [_db saveIncomingMessage:[self msgSeq:i] advancingSyncedConvSeq:i]; }
    [_db updateHeadConvSeq:12 forConv:_conv];
}

- (void)tearDown {
    [_db clearMessagesForConv:_conv];
    [_db deleteCachedConversation:_conv];
    [_mgr setValue:nil forKey:@"_databaseContext"];
    [_db useOwnerUserID:_prevOwner];
    [super tearDown];
}

#pragma mark - 夹具

- (IMMessageModel *)msgSeq:(int64_t)seq {
    return [IMMessageModel receivedMessageWithNewMsgData:@{
        @"server_msg_id": [NSString stringWithFormat:@"%@-%lld", _conv, seq], @"conv_id": _conv, @"from": @"peer",
        @"content": [NSString stringWithFormat:@"#%lld", seq], @"content_type": @"text",
        @"conv_seq": @(seq), @"timestamp": @(1788000000000 + seq) }];
}

- (NSArray<NSNumber *> *)localSeqs {
    NSMutableArray *out = [NSMutableArray array];
    for (IMMessageModel *m in [_db messagesForConv:_conv]) { [out addObject:@(m.convSeq)]; }
    return out;
}

/// 等 socket 队列上已排队的异步例程跑完（例程里内存游标 / 下界缓存是 dispatch_async 上去的）。
- (void)drainQueue { dispatch_sync([self queue], ^{}); }

- (NSUInteger)cachedRowCount {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"convID == %@", _conv];
    return [[_db cachedConversations] filteredArrayUsingPredicate:pred].count;
}

- (int64_t)cachedServerFloor {
    __block int64_t f = 0;
    dispatch_sync([self queue], ^{ f = [[self backlog] historyFloorForConv:self->_conv]; });
    return f;
}

- (void)seedServerFloor:(int64_t)floor {
    dispatch_sync([self queue], ^{ [[self backlog] noteHistoryFloor:floor forConv:self->_conv]; });
    XCTAssertEqual([self cachedServerFloor], floor);
}

- (NSArray<IMConversation *> *)snapshotWithClearedAt:(int64_t)clearedAt {
    return [IMConversation conversationsFromArray:@[ @{ @"conv_id": _conv, @"is_group": @YES, @"name": @"g",
                                                         @"latest_conv_seq": @12, @"cleared_at": @(clearedAt) } ]];
}

#pragma mark - ① 本机删除成功

/// 回包没带 cleared_at：位点 = 本机所知最新（head 12，不是本地最大 10）；删会话行之后位点仍在（独立小表）。
- (void)test_本机删除无cleared_at用本机head写位点并清消息 {
    [self seedServerFloor:3];
    [_mgr performDatabaseOperation:^(IMDatabase *db) {
        [self->_mgr clearConvToFloor:self->_conv serverClearedAt:0 database:db];
        [db deleteCachedConversation:self->_conv];
    }];
    [self drainQueue];
    XCTAssertEqualObjects([self localSeqs], @[]);
    XCTAssertEqual([_db clearedUpToForConv:_conv], 12);
    XCTAssertEqual([self cachedServerFloor], 0, @"服务端下界缓存须丢");
}

/// 回包带 cleared_at：位点 = max(本机既有, cleared_at)；只清 <= 位点的行，之后到的新消息保留。
- (void)test_本机删除带cleared_at取其与既有位点的较大者 {
    [_mgr performDatabaseOperation:^(IMDatabase *db) {
        [self->_mgr clearConvToFloor:self->_conv serverClearedAt:8 database:db];
    }];
    XCTAssertEqual([_db clearedUpToForConv:_conv], 8);
    XCTAssertEqualObjects([self localSeqs], (@[@9, @10]), @"9、10 在位点之上，服务端仍可见，不得清");
    [_mgr performDatabaseOperation:^(IMDatabase *db) {
        [self->_mgr clearConvToFloor:self->_conv serverClearedAt:5 database:db];   // 更小的不得把位点拉低
    }];
    XCTAssertEqual([_db clearedUpToForConv:_conv], 8);
}

#pragma mark - ② 别的设备 conv_update(delete)

- (void)test_conv_update_delete帧带cleared_at写位点并丢下界缓存 {
    [self seedServerFloor:2];
    NSDictionary *frame = @{ @"conv_id": _conv, @"action": @"delete", @"cleared_at": @10 };
    XCTAssertTrue([_mgr applyConvDeleteFrame:frame convID:_conv]);
    [self drainQueue];
    XCTAssertEqual([_db clearedUpToForConv:_conv], 10);
    XCTAssertEqualObjects([self localSeqs], @[]);
    XCTAssertEqual([self cachedServerFloor], 0);
}

#pragma mark - ③ 会话列表快照

- (void)test_列表项cleared_at解析 {
    XCTAssertEqual([self snapshotWithClearedAt:7].firstObject.clearedAt, 7);
    XCTAssertEqual([self snapshotWithClearedAt:0].firstObject.clearedAt, 0, @"缺省 / 0 = 没删过");
}

/// 旧版本遗留的残留消息：快照 cleared_at(10) 高于本机位点(0) → 同一例程清到位点；位点之上的保留。
- (void)test_快照cleared_at高于本机位点清掉残留 {
    [self seedServerFloor:4];
    __block NSUInteger n = 0;
    [_mgr performDatabaseOperation:^(IMDatabase *db) {
        n = [self->_mgr alignClearFloorsFromConversations:[self snapshotWithClearedAt:8] database:db];
    }];
    [self drainQueue];
    XCTAssertEqual(n, 1u);
    XCTAssertEqual([_db clearedUpToForConv:_conv], 8);
    XCTAssertEqualObjects([self localSeqs], (@[@9, @10]));
    XCTAssertEqual([self cachedServerFloor], 0);
}

/// cleared_at 没超过本机位点：不触发（不清消息、不丢下界缓存）。
- (void)test_快照cleared_at不高于本机位点不触发 {
    [_db clearMessagesForConv:_conv];                                  // 本机位点 12
    [_db saveIncomingMessage:[self msgSeq:13] advancingSyncedConvSeq:13];
    [self seedServerFloor:4];
    __block NSUInteger n = 99;
    [_mgr performDatabaseOperation:^(IMDatabase *db) {
        n = [self->_mgr alignClearFloorsFromConversations:[self snapshotWithClearedAt:9] database:db];
    }];
    XCTAssertEqual(n, 0u);
    XCTAssertEqualObjects([self localSeqs], @[@13]);
    XCTAssertEqual([self cachedServerFloor], 4);
}

#pragma mark - 位点之后的收消息

/// 删除后：<= 位点的迟到消息不落库（落库闸），位点之后的新消息照常落库。
- (void)test_删除后位点以内不落库位点之后落库 {
    [_mgr performDatabaseOperation:^(IMDatabase *db) {
        [self->_mgr clearConvToFloor:self->_conv serverClearedAt:12 database:db];
        [db deleteCachedConversation:self->_conv];
    }];
    [_db saveIncomingMessage:[self msgSeq:12] advancingSyncedConvSeq:0];
    [_db saveIncomingMessage:[self msgSeq:5] advancingSyncedConvSeq:0];
    XCTAssertEqualObjects([self localSeqs], @[], @"<= 位点不得再存");
    [_db saveIncomingMessage:[self msgSeq:13] advancingSyncedConvSeq:13];
    XCTAssertEqualObjects([self localSeqs], @[@13], @"位点之后的新消息照常存");
}

#pragma mark - 健壮性 / 待发消息

/// 帧里 cleared_at 是 NSNull / 负数 / 非数字：不得崩（NSNull 无 longLongValue），按「没给」处理。
- (void)test_cleared_at异常类型不崩且视为未给 {
    XCTAssertEqual(IMClearedAtFromJSON([NSNull null]), 0);
    XCTAssertEqual(IMClearedAtFromJSON(@(-5)), 0);
    XCTAssertEqual(IMClearedAtFromJSON(@[@1]), 0);
    XCTAssertEqual(IMClearedAtFromJSON(@"7"), 7);
    NSDictionary *frame = @{ @"conv_id": _conv, @"action": @"delete", @"cleared_at": [NSNull null] };
    XCTAssertTrue([_mgr applyConvDeleteFrame:frame convID:_conv]);
    XCTAssertEqual([_db clearedUpToForConv:_conv], 12, @"没给位点 = 本机所知最新（head 12）");
}

/// 服务端给了位点时只清 conv_seq<=位点的行：还没拿到 conv_seq 的待发消息（conv_seq=0）必须留着。
- (void)test_带cleared_at时待发消息保留 {
    IMMessageModel *pending = [self msgSeq:0];
    pending.clientMsgID = @"pending-cdel"; pending.serverMsgID = @"";
    [_db saveMessage:pending];
    [_mgr performDatabaseOperation:^(IMDatabase *db) {
        [self->_mgr clearConvToFloor:self->_conv serverClearedAt:10 database:db];
    }];
    XCTAssertEqualObjects([self localSeqs], @[@0], @"只剩待发那条");
}

/// 迟到的 conv_update(delete) 回显：会话已被位点之后的新消息复活 → 不删行，只清 <= 位点，新消息保留。
- (void)test_迟到删除回显遇复活会话保留行与新消息 {
    [_db saveIncomingMessage:[self msgSeq:13] advancingSyncedConvSeq:13];
    NSArray *convs = [self snapshotWithClearedAt:0];
    [_db replaceCachedConversations:convs];
    NSDictionary *frame = @{ @"conv_id": _conv, @"action": @"delete", @"cleared_at": @10 };
    XCTAssertTrue([_mgr applyConvDeleteFrame:frame convID:_conv]);
    XCTAssertEqualObjects([self localSeqs], @[@13]);
    XCTAssertEqual([_db clearedUpToForConv:_conv], 10);
    XCTAssertTrue([_db convRevivedAfterClearedAt:10 forConv:_conv]);
    XCTAssertEqual([self cachedRowCount], 1u, @"会话行还在");
}

/// 没复活（位点 = 最新）照旧删行。
- (void)test_未复活的删除帧照旧删行 {
    [_db replaceCachedConversations:[self snapshotWithClearedAt:0]];
    NSDictionary *frame = @{ @"conv_id": _conv, @"action": @"delete", @"cleared_at": @12 };
    XCTAssertTrue([_mgr applyConvDeleteFrame:frame convID:_conv]);
    XCTAssertEqual([self cachedRowCount], 0u);
}

@end
