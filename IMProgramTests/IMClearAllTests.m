#import <XCTest/XCTest.h>

#import "IMBacklogTracker.h"
#import "IMClearAll.h"
#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMDatabase+ClearAll.h"
#import "IMDatabase+ClearFloor.h"
#import "IMDatabase+Ranges.h"
#import "IMMessageModel.h"
#import "IMSocketManager.h"
#import "IMSocketManager+ClearAll.h"
#import "IMSocketManager+ConvClear.h"
#import "IMSocketManager+Private.h"

/// 「清除所有对话」（CLEAR_ALL_CONVERSATIONS_DESIGN §4）：HTTP 成功后对 items[] 批量跑 §6.7.1「清除到位点」。
/// 错法全是静默的：位点没写 / 清过头吞了新消息 / 待发被删 / 回声不幂等 / 失败仍改了本机 → 界面照常，只是之后历史冒出来。
@interface IMClearAllTests : XCTestCase
@end

@implementation IMClearAllTests {
    IMSocketManager *_mgr;
    IMDatabase *_db;
    NSString *_prevOwner;
    NSString *_a, *_b;
}

- (dispatch_queue_t)queue { return [_mgr valueForKey:@"_queue"]; }

- (void)setUp {
    [super setUp];
    _mgr = IMSocketManager.sharedManager;
    _db = IMDatabase.sharedDatabase;
    _prevOwner = _db.ownerUserID;
    IMDatabaseAccountContext *ctx = [_db useOwnerUserID:@"clear_all_test"];
    [_mgr setValue:ctx forKey:@"_databaseContext"];
    NSString *u = NSUUID.UUID.UUIDString;
    _a = [NSString stringWithFormat:@"g_ca_a_%@", u];
    _b = [NSString stringWithFormat:@"g_ca_b_%@", u];
    for (NSString *c in @[_a, _b]) {
        for (int64_t i = 1; i <= 10; i++) { [_db saveIncomingMessage:[self msg:i conv:c] advancingSyncedConvSeq:i]; }
        [_db updateHeadConvSeq:10 forConv:c];
    }
}

- (void)tearDown {
    for (NSString *c in @[_a, _b]) { [_db clearMessagesForConv:c]; [_db deleteCachedConversation:c]; }
    [_mgr setValue:nil forKey:@"_databaseContext"];
    [_db useOwnerUserID:_prevOwner];
    [super tearDown];
}

- (IMMessageModel *)msg:(int64_t)seq conv:(NSString *)conv {
    return [IMMessageModel receivedMessageWithNewMsgData:@{
        @"server_msg_id": [NSString stringWithFormat:@"%@-%lld", conv, seq], @"conv_id": conv, @"from": @"peer",
        @"content": [NSString stringWithFormat:@"#%lld", seq], @"content_type": @"text",
        @"conv_seq": @(seq), @"timestamp": @(1788000000000 + seq) }];
}

- (NSArray<NSNumber *> *)seqsIn:(NSString *)conv {
    NSMutableArray *out = [NSMutableArray array];
    for (IMMessageModel *m in [_db messagesForConv:conv]) { [out addObject:@(m.convSeq)]; }
    return out;
}

- (BOOL)hasRow:(NSString *)conv {
    return [[_db cachedConversationWithID:conv] isKindOfClass:IMConversation.class];
}

- (NSArray<IMClearAllItem *> *)items:(int64_t)atA :(int64_t)atB {
    return @[[[IMClearAllItem alloc] initWithConvID:_a clearedAt:atA], [[IMClearAllItem alloc] initWithConvID:_b clearedAt:atB]];
}

#pragma mark - 批量落库

/// 只清 conv_seq <= cleared_at 的行（每个会话各取各的位点）；位点之上的新消息保留；位点写进去。
- (void)test_批量只清位点以内的行各取各的位点 {
    NSDictionary *removed = [_db clearConversationsToFloors:[self items:8 :10]];
    XCTAssertNotNil(removed);
    XCTAssertEqualObjects([self seqsIn:_a], (@[@9, @10]), @"位点之上的行服务端仍可见，不得清");
    XCTAssertEqualObjects([self seqsIn:_b], @[]);
    XCTAssertEqual([removed[_a] integerValue], 8);
    XCTAssertEqual([removed[_b] integerValue], 10);
    XCTAssertEqual([_db clearedUpToForConv:_a], 8);
    XCTAssertEqual([_db clearedUpToForConv:_b], 10);
}

/// 待发消息（conv_seq=0）保留；位点之后的新消息落库闸放行。
- (void)test_待发消息保留_位点之后的新消息照常落库 {
    IMMessageModel *pending = [self msg:0 conv:_a];
    pending.clientMsgID = @"pending-clear-all"; pending.serverMsgID = @"";
    [_db saveMessage:pending];
    XCTAssertNotNil([_db clearConversationsToFloors:[self items:10 :10]]);
    XCTAssertEqualObjects([self seqsIn:_a], @[@0], @"只剩待发那条");
    [_db saveIncomingMessage:[self msg:5 conv:_a] advancingSyncedConvSeq:0];
    XCTAssertEqualObjects([self seqsIn:_a], @[@0], @"<= 位点的迟到消息不得再落库");
    [_db saveIncomingMessage:[self msg:11 conv:_a] advancingSyncedConvSeq:11];
    XCTAssertTrue([[self seqsIn:_a] containsObject:@11], @"位点之后的新消息照常存");
}

/// 会话行被移除，但位点在独立小表里，行删后仍在（否则重建壳行后历史被拉回）。
- (void)test_会话行删除后位点仍在 {
    [_db replaceCachedConversations:@[]];  // 保证无干扰；下面直接造行
    [_db saveIncomingMessage:[self msg:11 conv:_a] advancingSyncedConvSeq:11]; // 建会话壳行
    XCTAssertTrue([self hasRow:_a]);
    XCTAssertNotNil([_db clearConversationsToFloors:@[[[IMClearAllItem alloc] initWithConvID:_a clearedAt:11]]]);
    XCTAssertFalse([self hasRow:_a], @"会话行移除");
    XCTAssertEqual([_db clearedUpToForConv:_a], 11, @"位点不随会话行丢");
}

/// 迟到的新消息已让会话复活（行 head 超过位点）：保留行，不把新会话藏掉。
- (void)test_已复活的会话保留行 {
    [_db saveIncomingMessage:[self msg:11 conv:_a] advancingSyncedConvSeq:11];
    XCTAssertNotNil([_db clearConversationsToFloors:@[[[IMClearAllItem alloc] initWithConvID:_a clearedAt:10]]]);
    XCTAssertTrue([self hasRow:_a]);
    XCTAssertEqualObjects([self seqsIn:_a], @[@11], @"位点之上的新消息保留");
}

/// cleared_at<=0（服务端该会话没有消息）：不碰消息（待发也不删），仍移除会话行。
- (void)test_cleared_at为0不碰消息只移除行 {
    [_db saveIncomingMessage:[self msg:11 conv:_a] advancingSyncedConvSeq:11];
    XCTAssertNotNil([_db clearConversationsToFloors:@[[[IMClearAllItem alloc] initWithConvID:_a clearedAt:0]]]);
    XCTAssertFalse([self hasRow:_a]);
    XCTAssertEqual([self seqsIn:_a].count, 11u);
    XCTAssertEqual([_db clearedUpToForConv:_a], 0);
}

#pragma mark - 回声幂等

/// 批量清除之后到达的 conv_update(delete, cleared_at) 回声：不报错、不改结果、位点不降；批量本身重复调用同样幂等。
- (void)test_回声幂等 {
    XCTAssertTrue([_mgr applyClearAllItems:[self items:8 :10]]);
    NSArray *aAfter = [self seqsIn:_a];
    NSDictionary *echoA = @{ @"conv_id": _a, @"action": @"delete", @"cleared_at": @8 };
    NSDictionary *echoB = @{ @"conv_id": _b, @"action": @"delete", @"cleared_at": @10 };
    XCTAssertTrue([_mgr applyConvDeleteFrame:echoA convID:_a]);
    XCTAssertTrue([_mgr applyConvDeleteFrame:echoB convID:_b]);
    XCTAssertEqualObjects([self seqsIn:_a], aAfter);
    XCTAssertEqual([_db clearedUpToForConv:_a], 8);
    XCTAssertEqual([_db clearedUpToForConv:_b], 10);
    XCTAssertTrue([_mgr applyClearAllItems:[self items:8 :10]], @"重复批量同样成功");
    XCTAssertEqualObjects([self seqsIn:_a], aAfter);
    XCTAssertEqual([_db clearedUpToForConv:_a], 8);
}

/// 网络层：内存游标推到位点、服务端下界缓存丢掉。
- (void)test_批量后下界缓存丢弃 {
    IMBacklogTracker *backlog = [_mgr valueForKey:@"_backlog"];
    dispatch_sync([self queue], ^{ [backlog noteHistoryFloor:3 forConv:self->_a]; });
    XCTAssertTrue([_mgr applyClearAllItems:[self items:10 :10]]);
    dispatch_sync([self queue], ^{});
    __block int64_t f = -1;
    dispatch_sync([self queue], ^{ f = [backlog historyFloorForConv:self->_a]; });
    XCTAssertEqual(f, 0);
}

#pragma mark - 失败不改本机

/// 账号上下文失效（performDatabaseOperation 不执行）：返回 NO，本机消息 / 位点一概不动。
- (void)test_库操作未执行时返回NO且本机不变 {
    [_mgr setValue:nil forKey:@"_databaseContext"];
    XCTAssertFalse([_mgr applyClearAllItems:[self items:10 :10]]);
    XCTAssertEqual([self seqsIn:_a].count, 10u);
    XCTAssertEqual([_db clearedUpToForConv:_a], 0);
}

#pragma mark - 回包解析 / 文案

- (void)test_回包解析 {
    IMClearAllResult *r = IMClearAllParseResponse(@{ @"cleared": @2, @"items": @[
        @{ @"conv_id": @"c1", @"cleared_at": @7 }, @{ @"conv_id": @"", @"cleared_at": @1 }, @{ @"cleared_at": @1 },
        @{ @"conv_id": @"c2", @"cleared_at": [NSNull null] }, @"junk" ] });
    XCTAssertEqual(r.cleared, 2);
    XCTAssertEqual(r.items.count, 2u);
    XCTAssertEqualObjects(r.items[0].convID, @"c1");
    XCTAssertEqual(r.items[0].clearedAt, 7);
    XCTAssertEqual(r.items[1].clearedAt, 0);
    IMClearAllResult *empty = IMClearAllParseResponse(@{ @"cleared": @0, @"items": @[] });
    XCTAssertEqual(empty.cleared, 0);
    XCTAssertNil(IMClearAllParseResponse(nil), @"回包不是对象 = 失败，不得据此动本机");
    XCTAssertNil(IMClearAllParseResponse(@[@1]));
    XCTAssertEqual(IMClearAllParseResponse(@{ @"cleared": @(-3) }).cleared, 0);
}

- (void)test_toast与确认文案带N {
    XCTAssertTrue([IMClearAllToastText(12) containsString:@"12"]);
    XCTAssertFalse([IMClearAllToastText(0) containsString:@"0"]);
    XCTAssertNotEqualObjects(IMClearAllToastText(0), IMClearAllToastText(1));
    XCTAssertTrue([IMClearAllConfirmBody(7) containsString:@"7"]);
}

@end
