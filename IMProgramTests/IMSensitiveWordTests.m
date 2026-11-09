//  IMSensitiveWordTests.m
//  敏感词拦截 100004 ContentBlocked 的客户端映射（../IMServer/docs/design/SENSITIVE_WORDS_DESIGN.md §3）：
//  ① send_msg 被拦 → 气泡下说明 chat.reject.sensitive、不给重发；② msg_op 编辑被拦 → 吐司 err.100004、带回原负载还原编辑框；
//  ③ HTTP 表单被拦 → err.100004。

#import <XCTest/XCTest.h>

#import "IMSocketManager.h"
#import "IMSocketManager+Private.h"
#import "IMProtocol.h"
#import "IMHTTPService.h"
#import "IMChatMessageLogic.h"
#import "IMMessageModel.h"
#import "IMLocalization.h"

@interface IMSocketManager (SensitiveTestHooks)
- (void)enqueueSendWithClientMsgID:(NSString *)clientMsgID payload:(NSDictionary *)payload completion:(IMSendCompletion)completion;
@end

@interface IMSensitiveWordTests : XCTestCase
@end

@implementation IMSensitiveWordTests {
    IMSocketManager *_mgr;
}

- (dispatch_queue_t)queue { return [_mgr valueForKey:@"_queue"]; }

- (void)setUp {
    [super setUp];
    _mgr = IMSocketManager.sharedManager;
}

- (void)tearDown {
    dispatch_sync(self.queue, ^{
        NSMutableDictionary *pending = [self->_mgr valueForKey:@"_pending"];
        for (id p in pending.allValues) {
            id timer = [p valueForKey:@"ackTimer"];
            if (timer) { dispatch_source_cancel((dispatch_source_t)timer); }
        }
        [pending removeAllObjects];
        [[self->_mgr valueForKey:@"_pendingOps"] removeAllObjects];
    });
    [super tearDown];
}

- (void)drainMain {
    XCTestExpectation *e = [self expectationWithDescription:@"drain"];
    dispatch_async(dispatch_get_main_queue(), ^{ [e fulfill]; });
    [self waitForExpectations:@[e] timeout:2];
}

#pragma mark - 码表

/// HTTP 表单（资料 / 群资料 / 好友申请附言）与 msg_op 吐司都走这张表：100004 → err.100004，不回退服务端中文原文。
- (void)test_友好文案_100004映射err100004 {
    XCTAssertEqualObjects(IMFriendlyMessageForCode(100004), IMLocalized(@"err.100004"));
    XCTAssertEqual(IMErrCodeContentBlocked, 100004);
}

/// 发送被拦：挂气泡下说明、不给红❗重发（原样重发必然再被拦）。
- (void)test_100004算拒收_挂note_不可重发 {
    XCTAssertTrue(IMSendRejectionShowsNote(100004));
    NSError *err = [NSError errorWithDomain:@"im" code:100004 userInfo:@{ NSLocalizedDescriptionKey: @"x" }];
    NSInteger noteCode = 0;
    XCTAssertEqualObjects(IMSendRejectionNote(NO, err, &noteCode), @"x");
    XCTAssertEqual(noteCode, 100004);
    IMMessageModel *m = [IMMessageModel new];
    m.status = IMMessageStatusFailed;
    m.content = @"hello";
    m.note = @"x";
    XCTAssertEqual(IMResendPolicyForMessage(m, YES), IMResendPolicyNone);
}

#pragma mark - WS send_msg 被拦

/// error 帧（带 client_msg_id、code=100004）→ 该条立刻失败，文案为 chat.reject.sensitive（不是服务端原文；
/// 服务端原文刻意给个不同的串，否则与本地文案碰巧同字时映射丢了也测不出来）。
- (void)test_send_msg被拦_说明为chat_reject_sensitive {
    __block NSError *got = nil;
    IMSendCompletion done = ^(BOOL ok, NSError *err, int64_t seq) { got = err; };
    dispatch_sync(self.queue, ^{
        [self->_mgr enqueueSendWithClientMsgID:@"s1" payload:@{ @"content": @"hi", @"client_msg_id": @"s1" } completion:done];
        [self->_mgr handleErrorFrame:@{ @"client_msg_id": @"s1", @"code": @100004, @"message": @"server raw text" }];
    });
    [self drainMain];
    XCTAssertEqual(got.code, 100004);
    XCTAssertEqualObjects(got.localizedDescription, IMLocalized(@"chat.reject.sensitive"));
}

#pragma mark - WS msg_op 编辑被拦

/// 编辑被拦：拒绝通知带本地化文案 err.100004 + 业务码 + 原负载（含 content），据此能还原编辑框。
- (void)test_编辑被拦_通知带err100004与原负载 {
    NSDictionary *op = @{ @"op": kIMMsgOpEdit, @"conv_id": @"c_1", @"target_conv_seq": @7,
                          @"content": @"改后的字", @"client_msg_id": @"op1" };
    __block NSDictionary *info = nil;
    id token = [NSNotificationCenter.defaultCenter addObserverForName:IMSocketDidRejectMsgOpNotification object:nil
                                                                queue:nil usingBlock:^(NSNotification *n) { info = n.userInfo; }];
    dispatch_sync(self.queue, ^{
        [self->_mgr valueForKey:@"_pendingOps"][@"op1"] = op;
        [self->_mgr handleErrorFrame:@{ @"client_msg_id": @"op1", @"code": @100004, @"message": @"server raw text" }];
    });
    [self drainMain];
    [NSNotificationCenter.defaultCenter removeObserver:token];
    XCTAssertEqualObjects(info[kIMMsgOpRejectMessageKey], IMLocalized(@"err.100004"));
    XCTAssertEqualObjects(info[kIMMsgOpRejectCodeKey], @100004);
    XCTAssertEqualObjects(IMRejectedEditDraft(info, @"c_1"), @"改后的字");
}

/// 只在「编辑 + 100004 + 本会话」时还原；别的码（如超窗 300007）、别的操作、别的会话都不还原。
- (void)test_还原编辑稿的判据 {
    NSDictionary *edit = @{ @"op": kIMMsgOpEdit, @"conv_id": @"c_1", @"target_conv_seq": @7, @"content": @"abc" };
    NSDictionary *(^info)(NSInteger, NSDictionary *) = ^(NSInteger code, NSDictionary *op) {
        return @{ kIMMsgOpRejectMessageKey: @"m", kIMMsgOpRejectCodeKey: @(code), kIMMsgOpRejectPayloadKey: op };
    };
    XCTAssertEqualObjects(IMRejectedEditDraft(info(100004, edit), @"c_1"), @"abc");
    XCTAssertNil(IMRejectedEditDraft(info(300007, edit), @"c_1"));
    XCTAssertNil(IMRejectedEditDraft(info(100004, edit), @"c_2"));
    NSMutableDictionary *recall = [edit mutableCopy]; recall[@"op"] = kIMMsgOpRecall;
    XCTAssertNil(IMRejectedEditDraft(info(100004, recall), @"c_1"));
    NSMutableDictionary *empty = [edit mutableCopy]; empty[@"content"] = @"";
    XCTAssertNil(IMRejectedEditDraft(info(100004, empty), @"c_1"));
    XCTAssertNil(IMRejectedEditDraft(nil, @"c_1"));
}

@end
