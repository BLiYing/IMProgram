//  IMDeletedUserDisplayTests.m
//  「已注销用户」显示口径（PROTOCOL §6.16.3）与别的设备注销踢下线帧（§6.16.2）、对已注销者发消息的拒收（300003）。
//  错法都是静默的：备注 / 群昵称把「已注销用户」压回去、恢复账号后仍显已注销、收到注销帧没清缓存也没停重连。

#import <XCTest/XCTest.h>

#import "IMConversation.h"
#import "IMGroupInfo.h"
#import "IMLocalization.h"
#import "IMRemarkStore.h"
#import "IMSocketManager.h"
#import "IMSocketManager+Private.h"
#import "IMUserCard.h"

@interface IMDeletedUserDisplayTests : XCTestCase
@end

@implementation IMDeletedUserDisplayTests

- (NSString *)label { return IMLocalized(@"delete_account.deleted_user"); }

- (void)setUp {
    [super setUp];
    [IMRemarkStore.sharedStore ingestFriends:@[] authoritative:YES];
    [IMRemarkStore.sharedStore setUser:@"u1" deleted:NO];
}

- (void)tearDown {
    [IMRemarkStore.sharedStore setUser:@"u1" deleted:NO];
    [IMRemarkStore.sharedStore ingestFriends:@[] authoritative:YES];
    [super tearDown];
}

/// 已注销压过备注与 fallback（群昵称 / 服务端昵称）；撤销（账号恢复）后备注与昵称回来。
- (void)testStoreDeletedBeatsRemarkAndIsReversible {
    IMRemarkStore *store = IMRemarkStore.sharedStore;
    [store applyRemark:@"老王" forUser:@"u1"];
    XCTAssertEqualObjects([store displayNameForUser:@"u1" fallback:@"群昵称"], @"老王");
    [store setUser:@"u1" deleted:YES];
    XCTAssertTrue([store isDeletedUser:@"u1"]);
    XCTAssertEqualObjects([store displayNameForUser:@"u1" fallback:@"群昵称"], [self label]);
    [store setUser:@"u1" deleted:NO];
    XCTAssertEqualObjects([store displayNameForUser:@"u1" fallback:@"群昵称"], @"老王");
}

/// 解析即登记：用户对象 deleted=true → 登记；下一次不带 deleted（恢复账号）→ 撤销。
- (void)testCardParseRegistersAndUnregisters {
    IMUserCard *c = [IMUserCard cardsFromArray:@[@{ @"user_id": @"u1", @"nickname": @"已注销用户", @"deleted": @YES }]].firstObject;
    XCTAssertTrue(c.deleted);
    XCTAssertTrue([IMRemarkStore.sharedStore isDeletedUser:@"u1"]);
    [IMUserCard cardsFromArray:@[@{ @"user_id": @"u1", @"nickname": @"小明" }]].firstObject;
    XCTAssertFalse([IMRemarkStore.sharedStore isDeletedUser:@"u1"]);
}

/// 会话列表：peer_deleted 压过会话备注与好友备注；群聊不受 peer_deleted 影响。
- (void)testConversationPeerDeletedBeatsAllRemarks {
    [IMRemarkStore.sharedStore applyRemark:@"好友备注" forUser:@"u1"];
    NSDictionary *d = @{ @"conv_id": @"c1", @"peer": @"u1", @"peer_nickname": @"小明", @"remark": @"会话备注", @"peer_deleted": @YES };
    IMConversation *c = [IMConversation conversationsFromArray:@[d]].firstObject;
    XCTAssertTrue(c.peerDeleted);
    XCTAssertEqualObjects(c.displayName, [self label]);
    XCTAssertEqualObjects(c.knownDisplayName, [self label]);
    IMConversation *g = [IMConversation conversationsFromArray:@[@{ @"conv_id": @"g1", @"is_group": @YES, @"name": @"群", @"peer_deleted": @YES }]].firstObject;
    XCTAssertFalse(g.peerDeleted);
    XCTAssertEqualObjects(g.displayName, @"群");
    // 恢复：下一次列表不带 peer_deleted → 回到备注
    IMConversation *back = [IMConversation conversationsFromArray:@[@{ @"conv_id": @"c1", @"peer": @"u1", @"peer_nickname": @"小明", @"remark": @"会话备注" }]].firstObject;
    XCTAssertEqualObjects(back.displayName, @"会话备注");
}

/// 群成员：deleted 压过群昵称；nicknameOfMember 同口径（气泡 / 系统行都经它取名）。
- (void)testGroupMemberDeletedBeatsGroupNickname {
    IMGroupMember *m = [IMGroupMember memberFromDictionary:@{ @"user_id": @"u1", @"nickname": @"已注销用户", @"group_nickname": @"群里的小明", @"deleted": @YES }];
    XCTAssertTrue(m.deleted);
    XCTAssertEqualObjects(m.displayName, [self label]);
    XCTAssertEqualObjects(m.localDisplayName, [self label]);
    IMGroupInfo *g = [IMGroupInfo new];
    g.members = @[m];
    XCTAssertEqualObjects([g nicknameOfMember:@"u1"], [self label]);
}

#pragma mark - WS

- (void)drainMain {
    XCTestExpectation *e = [self expectationWithDescription:@"drain"];
    dispatch_async(dispatch_get_main_queue(), ^{ [e fulfill]; });
    [self waitForExpectations:@[e] timeout:2];
}

/// error{reason:account_deleted}：广播通知 + 停自动重连；没有 reason 的 error 不广播。
- (void)testAccountDeletedFramePostsNotificationAndStopsReconnect {
    IMSocketManager *mgr = IMSocketManager.sharedManager;
    dispatch_queue_t q = [mgr valueForKey:@"_queue"];
    __block BOOL manualBefore = NO;
    dispatch_sync(q, ^{ manualBefore = [[mgr valueForKey:@"_manualClose"] boolValue]; });
    XCTestExpectation *posted = [self expectationForNotification:IMSocketDidReceiveAccountDeletedNotification object:nil handler:nil];
    dispatch_sync(q, ^{ [mgr handleErrorFrame:@{ @"code": @200005, @"reason": @"account_deleted", @"delete_at": @1760600000000 }]; });
    [self waitForExpectations:@[posted] timeout:2];
    __block BOOL manualAfter = NO;
    dispatch_sync(q, ^{ manualAfter = [[mgr valueForKey:@"_manualClose"] boolValue]; [mgr setValue:@(manualBefore) forKey:@"_manualClose"]; });
    XCTAssertTrue(manualAfter, @"注销帧后必须停自动重连");

    id obs = [NSNotificationCenter.defaultCenter addObserverForName:IMSocketDidReceiveAccountDeletedNotification object:nil queue:nil
                                                         usingBlock:^(NSNotification *n) { XCTFail(@"普通 error 不应触发注销通知"); }];
    dispatch_sync(q, ^{ [mgr handleErrorFrame:@{ @"code": @100001, @"message": @"x" }]; });
    [self drainMain];
    [NSNotificationCenter.defaultCenter removeObserver:obs];
}

/// 向已注销者单聊发消息 → error{300003, client_msg_id}：该条判失败（不卡发送中），文案是「对方账号已注销」而非英文原文。
- (void)testSendToDeletedPeerFailsWithFriendlyMessage {
    IMSocketManager *mgr = IMSocketManager.sharedManager;
    dispatch_queue_t q = [mgr valueForKey:@"_queue"];
    __block NSError *got = nil;
    __block BOOL ok = YES;
    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    dispatch_sync(q, ^{
        [mgr enqueueSendWithClientMsgID:@"cmid-300003" payload:@{ @"content": @"hi", @"client_msg_id": @"cmid-300003" }
                             completion:^(BOOL success, NSError *err, int64_t seq) { ok = success; got = err; [done fulfill]; }];
        [mgr handleErrorFrame:@{ @"code": @300003, @"message": @"recipient not found", @"client_msg_id": @"cmid-300003" }];
    });
    [self waitForExpectations:@[done] timeout:2];
    XCTAssertFalse(ok);
    XCTAssertEqual(got.code, 300003);
    XCTAssertEqualObjects(got.localizedDescription, IMLocalized(@"chat.reject.recipient_deleted"));
    NSMutableDictionary *pending = [mgr valueForKey:@"_pending"];
    __block id left = nil;
    dispatch_sync(q, ^{ left = pending[@"cmid-300003"]; });
    XCTAssertNil(left, @"拒收后待确认项必须清掉，否则一直转圈");
}

@end
