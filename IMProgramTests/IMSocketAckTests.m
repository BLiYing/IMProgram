//  IMSocketAckTests.m
//  文本/媒体发送的 ACK 状态机：待确认项 → ack / 超时重发 / 服务端拒收 / 取消（IMSocketManager）。
//
//  错法全是**静默**的：丢消息（该重发没重发）、重复（该停没停、ack 之后又判失败）、串号（旧账号的
//  待发在新账号连接上重发）。所以按「会怎么错」钉，用例名就是那个错法。
//
//  用 `IMSocketManager.sharedManager`（未连接：writeData 是空操作），私有方法只借名字调用。
//  不等 5s 定时器：直接触发 `handleAckTimeout:`。completion 是 dispatch_async 到主队列的，断言前先排空主队列。

#import <XCTest/XCTest.h>

#import "IMSocketManager.h"
#import "IMSocketManager+Private.h"
#import "IMProtocol.h"

@interface IMSocketManager (AckTestHooks)
- (void)enqueueSendWithClientMsgID:(NSString *)clientMsgID payload:(NSDictionary *)payload completion:(IMSendCompletion)completion;
- (void)handleAck:(NSDictionary *)data;
- (void)handleAckTimeout:(id)pending;
- (void)handleSendRejected:(NSString *)clientMsgID code:(NSInteger)code message:(NSString *)message;
@end

@interface IMSocketAckTests : XCTestCase
@end

@implementation IMSocketAckTests {
    IMSocketManager *_mgr;
    NSMutableArray<NSDictionary *> *_results; // 每次 completion 回调：{cid, ok, code, msg, seq}
}

- (dispatch_queue_t)queue { return [_mgr valueForKey:@"_queue"]; }
- (NSMutableDictionary *)pending { return [_mgr valueForKey:@"_pending"]; }

- (void)setUp {
    [super setUp];
    _mgr = IMSocketManager.sharedManager;
    _results = [NSMutableArray array];
    dispatch_sync(self.queue, ^{ [[self pending] removeAllObjects]; });
}

- (void)tearDown {
    dispatch_sync(self.queue, ^{
        for (id p in [[self pending] allValues]) {
            id timer = [p valueForKey:@"ackTimer"];
            if (timer) { dispatch_source_cancel((dispatch_source_t)timer); }
        }
        [[self pending] removeAllObjects];
    });
    [super tearDown];
}

/// completion 是 dispatch_async 到主队列的：排空它。
- (void)drainMain {
    XCTestExpectation *e = [self expectationWithDescription:@"drain"];
    dispatch_async(dispatch_get_main_queue(), ^{ [e fulfill]; });
    [self waitForExpectations:@[e] timeout:2];
}

- (void)send:(NSString *)cid {
    NSMutableArray<NSDictionary *> *results = _results; // completion 只持有数组，不持有 self
    IMSendCompletion done = ^(BOOL ok, NSError *err, int64_t seq) {
        [results addObject:@{ @"cid": cid, @"ok": @(ok), @"code": @(err.code), @"msg": err.localizedDescription ?: @"", @"seq": @(seq) }];
    };
    dispatch_sync(self.queue, ^{
        [self->_mgr enqueueSendWithClientMsgID:cid payload:@{ @"content": @"hi", @"client_msg_id": cid } completion:done];
    });
}

- (id)pendingFor:(NSString *)cid {
    __block id p;
    dispatch_sync(self.queue, ^{ p = [self pending][cid]; });
    return p;
}

- (void)onQueue:(void (^)(void))block { dispatch_sync(self.queue, block); }

#pragma mark - ack

/// 正常：ack 到 → 回调成功带 conv_seq、待确认项清掉。
- (void)test_ack成功回调并清掉待确认项 {
    [self send:@"c1"];
    XCTAssertNotNil([self pendingFor:@"c1"]);
    [self onQueue:^{ [self->_mgr handleAck:@{ @"client_msg_id": @"c1", @"conv_seq": @42 }]; }];
    [self drainMain];
    XCTAssertEqual(_results.count, 1u);
    XCTAssertEqualObjects(_results[0][@"ok"], @YES);
    XCTAssertEqualObjects(_results[0][@"seq"], @42);
    XCTAssertNil([self pendingFor:@"c1"]);
}

/// 重发会产生重复 ack：第二次必须忽略（回调只能一次，否则 UI 状态被覆盖两遍）。
- (void)test_重复ack忽略_回调只一次 {
    [self send:@"c1"];
    [self onQueue:^{
        [self->_mgr handleAck:@{ @"client_msg_id": @"c1", @"conv_seq": @1 }];
        [self->_mgr handleAck:@{ @"client_msg_id": @"c1", @"conv_seq": @1 }];
    }];
    [self drainMain];
    XCTAssertEqual(_results.count, 1u);
}

/// 不认识的 / 缺失的 client_msg_id：忽略，不崩、不影响别的待确认项。
- (void)test_未知或缺失的ack不影响别的待确认项 {
    [self send:@"c1"];
    [self onQueue:^{
        [self->_mgr handleAck:@{ @"client_msg_id": @"nope", @"conv_seq": @9 }];
        [self->_mgr handleAck:@{ @"conv_seq": @9 }];
    }];
    [self drainMain];
    XCTAssertEqual(_results.count, 0u);
    XCTAssertNotNil([self pendingFor:@"c1"]);
}

#pragma mark - 超时重发

/// 超时：同一个 client_msg_id 原样重发（换新 ID 会在「服务端其实已存下、只是 ack 丢了」时让对端收两条）；
/// 重发耗尽才判失败，错误码 5002；失败后待确认项清掉、回调只一次。
- (void)test_超时重发三次后判失败 {
    [self send:@"c1"];
    id p = [self pendingFor:@"c1"];
    for (NSInteger i = 1; i <= 3; i++) {
        [self onQueue:^{ [self->_mgr handleAckTimeout:p]; }];
        XCTAssertEqual([[p valueForKey:@"retries"] integerValue], i, @"第 %ld 次超时应重发", (long)i);
        XCTAssertNotNil([self pendingFor:@"c1"], @"重发期间待确认项必须还在");
    }
    [self drainMain];
    XCTAssertEqual(_results.count, 0u, @"重发期间不能提前回调");
    [self onQueue:^{ [self->_mgr handleAckTimeout:p]; }]; // 第 4 次：耗尽
    [self drainMain];
    XCTAssertEqual(_results.count, 1u);
    XCTAssertEqualObjects(_results[0][@"ok"], @NO);
    XCTAssertEqualObjects(_results[0][@"code"], @5002);
    XCTAssertNil([self pendingFor:@"c1"]);
}

/// 重发途中 ack 到了：成功，且之后再来的超时（旧定时器）必须无效，不能把已成功的判成失败。
- (void)test_重发后ack到了_迟到的超时无效 {
    [self send:@"c1"];
    id p = [self pendingFor:@"c1"];
    [self onQueue:^{ [self->_mgr handleAckTimeout:p]; }];
    [self onQueue:^{ [self->_mgr handleAck:@{ @"client_msg_id": @"c1", @"conv_seq": @7 }]; }];
    [self onQueue:^{ [self->_mgr handleAckTimeout:p]; }]; // 已不在待确认表：no-op
    [self drainMain];
    XCTAssertEqual(_results.count, 1u);
    XCTAssertEqualObjects(_results[0][@"ok"], @YES);
}

/// 判失败之后迟到的 ack：忽略（回调只一次）。
- (void)test_判失败后迟到的ack忽略 {
    [self send:@"c1"];
    id p = [self pendingFor:@"c1"];
    for (int i = 0; i < 4; i++) { [self onQueue:^{ [self->_mgr handleAckTimeout:p]; }]; }
    [self onQueue:^{ [self->_mgr handleAck:@{ @"client_msg_id": @"c1", @"conv_seq": @7 }]; }];
    [self drainMain];
    XCTAssertEqual(_results.count, 1u);
    XCTAssertEqualObjects(_results[0][@"ok"], @NO);
}

#pragma mark - 服务端拒收

/// 拒收：立刻判失败、**不重发**（重发必然再被拒）；业务码透传给 UI 区分提示。
- (void)test_拒收立刻失败_码透传_不再重发 {
    [self send:@"c1"];
    id p = [self pendingFor:@"c1"];
    [self onQueue:^{ [self->_mgr handleSendRejected:@"c1" code:200103 message:@"not friend"]; }];
    [self drainMain];
    XCTAssertEqual(_results.count, 1u);
    XCTAssertEqualObjects(_results[0][@"ok"], @NO);
    XCTAssertEqualObjects(_results[0][@"code"], @200103);
    XCTAssertNil([self pendingFor:@"c1"]);
    [self onQueue:^{ [self->_mgr handleAckTimeout:p]; }]; // 旧定时器触发：no-op
    [self drainMain];
    XCTAssertEqual(_results.count, 1u, @"拒收之后不能再有任何回调");
}

/// 缺 code（0）按拒收（拉黑 200102）处理——宁可给出「被拒收」也不吐一个 code=0 的成功样错误。
- (void)test_拒收缺code兜底成200102 {
    [self send:@"c1"];
    [self onQueue:^{ [self->_mgr handleSendRejected:@"c1" code:0 message:nil]; }];
    [self drainMain];
    XCTAssertEqualObjects(_results[0][@"code"], @200102);
}

/// 文案：已收录的码用本地友好文案；未收录的码回退服务端原文；原文也没有就用通用「发送失败」。**不能空吐字**。
- (void)test_拒收文案回退链不为空 {
    [self send:@"a"]; [self send:@"b"]; [self send:@"c"];
    [self onQueue:^{
        [self->_mgr handleSendRejected:@"a" code:999999 message:@"server says no"];
        [self->_mgr handleSendRejected:@"b" code:999998 message:@""];
        [self->_mgr handleSendRejected:@"c" code:999997 message:nil];
    }];
    [self drainMain];
    NSMutableDictionary *byCid = [NSMutableDictionary dictionary];
    for (NSDictionary *r in _results) { byCid[r[@"cid"]] = r; }
    XCTAssertEqualObjects(byCid[@"a"][@"msg"], @"server says no");
    XCTAssertGreaterThan([byCid[@"b"][@"msg"] length], 0u);
    XCTAssertGreaterThan([byCid[@"c"][@"msg"] length], 0u);
}

/// 不认识的 client_msg_id 被拒收：忽略（不崩、别的待确认项不受影响）。
- (void)test_拒收未知id忽略 {
    [self send:@"c1"];
    [self onQueue:^{ [self->_mgr handleSendRejected:@"nope" code:200103 message:@"x"]; }];
    [self drainMain];
    XCTAssertEqual(_results.count, 0u);
    XCTAssertNotNil([self pendingFor:@"c1"]);
}

#pragma mark - 取消

/// 切账号 / 退出：全部未决发送立刻失败（5005）并清空待确认表——否则旧账号的负载会被定时器在新账号连接上重发（串号）。
- (void)test_取消全部未决发送_失败5005并清空 {
    [self send:@"a"]; [self send:@"b"];
    id pa = [self pendingFor:@"a"];
    [self onQueue:^{ [self->_mgr cancelAllPendingSendsWithMessage:@"切换账号"]; }];
    [self drainMain];
    XCTAssertEqual(_results.count, 2u);
    for (NSDictionary *r in _results) {
        XCTAssertEqualObjects(r[@"ok"], @NO);
        XCTAssertEqualObjects(r[@"code"], @5005);
        XCTAssertEqualObjects(r[@"msg"], @"切换账号");
    }
    XCTAssertEqual([[self pending] count], 0u);
    // 被取消项的旧定时器再触发：no-op，不重发、不再回调。
    [self onQueue:^{ [self->_mgr handleAckTimeout:pa]; }];
    [self drainMain];
    XCTAssertEqual(_results.count, 2u);
}

@end
