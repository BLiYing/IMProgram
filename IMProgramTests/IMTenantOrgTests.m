//  IMTenantOrgTests.m
//  集团（多租户）v2 T3 客户端规则（../im-spec/design/TENANT_DESIGN.md §3 / §4 / §8，交互稿 TENANT_CLIENT_UX_SKETCH）：
//  只读会话标记、重连抖动、面包屑、集团搜索词、入口选择、名片码 token、directory/me 解析、错误码文案、系统消息。
//  对端同名用例：im-web `tenantOrg.test.ts`、im-android `TenantOrgTest.kt`。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMOrgChatLocks.h"
#import "../IMProgram/Common/IMSysEventFormatter.h"
#import "../IMProgram/Common/IMLocalization.h"
#import "../IMProgram/Models/IMMessageModel.h"
#import "../IMProgram/Models/IMUserCard.h"
#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Network/IMHTTPService.h"
#import "../IMProgram/Network/IMReconnectBackoff.h"
#import "../IMProgram/Modules/Contacts/IMContactsViewController.h"
#import "../IMProgram/Modules/Detail/IMChatDetailViewController.h"
#import "../IMProgram/Modules/Org/IMDirectoryViewController.h"
#import "../IMProgram/Modules/Org/IMDirectorySearchViewController.h"
#import "../IMProgram/Modules/Org/IMMyTenantViewController.h"
#import "../IMProgram/Modules/Org/IMTenantStore.h"
#import "../IMProgram/Modules/QR/IMQRResultRouter.h"


/// 资料页私有状态（+Private.h 引了 Swift 桥接头，测试 target 取不到，这里只声明用到的）。
@interface IMChatDetailViewController (IMTenantOrgTesting)
@property (nonatomic, assign) BOOL peerIsFriend;
@property (nonatomic, assign) BOOL peerDirectChat;
@property (nonatomic, assign) BOOL peerUnreachable;
- (NSArray<NSDictionary *> *)actionPillSpecs;
- (NSArray<NSNumber *> *)sectionLayout;
@end

@interface IMTenantOrgTests : XCTestCase
@end

@implementation IMTenantOrgTests

#pragma mark - 只读会话（I-14）

- (void)testOrgChatLockTextKey {
    XCTAssertNil(IMOrgChatLockTextKey(nil));
    XCTAssertNil(IMOrgChatLockTextKey(@""));
    XCTAssertEqualObjects(IMOrgChatLockTextKey(IMOrgChatLockOrgLeft), @"chat.input.disabled_org_left");
    XCTAssertEqualObjects(IMOrgChatLockTextKey(IMOrgChatLockServiceEnded), @"chat.input.disabled_service_ended");
    XCTAssertNil(IMOrgChatLockTextKey(@"future_reason"), @"老客户端遇到新原因不误锁");
}

- (void)testConversationParsesPeerChatLock {
    NSArray *rows = @[ @{ @"conv_id": @"u_1_u_2", @"is_group": @NO, @"peer": @"2", @"peer_chat_lock": @"service_ended" },
                       @{ @"conv_id": @"u_1_u_3", @"is_group": @NO, @"peer": @"3" } ];
    NSArray<IMConversation *> *cs = [IMConversation conversationsFromArray:rows];
    XCTAssertEqualObjects(cs[0].peerChatLock, @"service_ended");
    XCTAssertEqual(cs[1].peerChatLock.length, 0u);
    NSArray *groups = @[ @{ @"conv_id": @"g_1", @"is_group": @YES, @"peer_chat_lock": @"org_left" } ];
    XCTAssertNil([IMConversation conversationsFromArray:groups].firstObject.peerChatLock, @"群聊不认这个字段");
}

/// 会话列表覆盖、即时信号（400120）先锁、资料页 direct_chat 解锁。
- (void)testOrgChatLocksStore {
    IMOrgChatLocks *locks = [IMOrgChatLocks new];
    IMConversation *c = [IMConversation conversationsFromArray:@[ @{ @"conv_id": @"u_1_u_9", @"peer": @"9", @"peer_chat_lock": @"org_left" } ]].firstObject;
    [locks ingestConversations:@[c]];
    [self drainMain];
    XCTAssertEqualObjects([locks lockTextKeyForPeer:@"9"], @"chat.input.disabled_org_left");
    [locks noteDirectChatForPeer:@"9"];
    [self drainMain];
    XCTAssertNil([locks lockTextKeyForPeer:@"9"]);
    [locks markOrgLeftForPeer:@"9"];
    [self drainMain];
    XCTAssertNotNil([locks lockTextKeyForPeer:@"9"]);
    c.peerChatLock = nil;
    [locks ingestConversations:@[c]];
    [self drainMain];
    XCTAssertNil([locks lockTextKeyForPeer:@"9"], @"会话列表以服务端为准覆盖");
}

- (void)drainMain {
    XCTestExpectation *e = [self expectationWithDescription:@"main"];
    dispatch_async(dispatch_get_main_queue(), ^{ [e fulfill]; });
    [self waitForExpectations:@[e] timeout:2];
}

#pragma mark - 重连抖动

- (void)testReconnectDelayJitterBounds {
    XCTAssertEqualWithAccuracy(IMReconnectDelay(0, 1, 30, 0), 0.8, 1e-9);
    XCTAssertEqualWithAccuracy(IMReconnectDelay(0, 1, 30, 1), 1.2, 1e-9);
    XCTAssertEqualWithAccuracy(IMReconnectDelay(2, 1, 30, 0.5), 4.0, 1e-9);
    XCTAssertEqualWithAccuracy(IMReconnectDelay(10, 1, 30, 0), 24.0, 1e-9, @"封顶 30 再抖");
    XCTAssertEqualWithAccuracy(IMReconnectDelay(10, 1, 30, 1), 36.0, 1e-9);
    XCTAssertEqualWithAccuracy(IMReconnectDelay(1000, 1, 30, 2), 36.0, 1e-9, @"rand 越界被夹、指数不溢出");
    XCTAssertGreaterThanOrEqual(IMReconnectDelay(-3, 0, 30, 0), 0.1);
}

#pragma mark - 组织架构

- (void)testDirectoryCrumbs {
    NSDictionary *page = @{ @"unit": @{ @"unit_id": @"U1", @"name": @"星海华东" },
                            @"path": @[ @{ @"dept_id": @"D1", @"name": @"研发中心" }, @{ @"dept_id": @"D2", @"name": @"技术部" }, @"junk" ] };
    NSArray *crumbs = IMDirectoryCrumbs(page);
    XCTAssertEqual(crumbs.count, 3u);
    NSArray *first = @[@"root", @"星海华东"], *last = @[@"D2", @"技术部"];
    XCTAssertEqualObjects(crumbs[0], first);
    XCTAssertEqualObjects(crumbs[2], last);
    XCTAssertEqual(IMDirectoryCrumbs(@{}).count, 1u, @"单位顶层只有单位一段");
}

- (void)testDirectorySearchQuery {
    XCTAssertNil(IMDirectorySearchQuery(nil));
    XCTAssertNil(IMDirectorySearchQuery(@"   "));
    XCTAssertEqualObjects(IMDirectorySearchQuery(@"  王 "), @"王");
    NSString *max = [@"" stringByPaddingToLength:32 withString:@"张" startingAtIndex:0];
    XCTAssertEqualObjects(IMDirectorySearchQuery(max), max);
    XCTAssertNil(IMDirectorySearchQuery([max stringByAppendingString:@"张"]), @"超过 32 字不发");
    NSString *emoji = [@"" stringByPaddingToLength:64 withString:@"👍" startingAtIndex:0]; // 32 个表情 = 64 个 UTF-16 码元
    XCTAssertEqualObjects(IMDirectorySearchQuery(emoji), emoji, @"按码点数不按码元");
    NSMutableString *family = [NSMutableString string]; // 每个「👨‍👩‍👧」1 个字素 = 5 个码点；7 个 = 35 码点
    for (int i = 0; i < 7; i++) { [family appendString:@"👨‍👩‍👧"]; }
    XCTAssertNil(IMDirectorySearchQuery(family), @"与服务端同口径：按码点数（ZWJ 组合算多个）");
}

- (void)testContactsOrgEntryKind {
    XCTAssertEqual(IMContactsOrgEntryKind(YES, YES, NO), IMContactsOrgEntryDirectory);
    XCTAssertEqual(IMContactsOrgEntryKind(YES, NO, YES), IMContactsOrgEntryNone, @"有集团但后台关了手机端入口");
    XCTAssertEqual(IMContactsOrgEntryKind(NO, YES, YES), IMContactsOrgEntryNoTenant, @"无集团：同名入口进空态页");
    XCTAssertEqual(IMContactsOrgEntryKind(NO, YES, NO), IMContactsOrgEntryNone, @"无集团且邀请码关着");
    XCTAssertEqual(IMContactsOrgEntryKind(NO, NO, NO), IMContactsOrgEntryNone);
}

- (void)testMyTenantShowsInvite {
    XCTAssertTrue(IMMyTenantShowsInvite(NO, NO, YES), @"无集团");
    XCTAssertTrue(IMMyTenantShowsInvite(YES, YES, YES), @"客户可再绑本集团别的子公司");
    XCTAssertFalse(IMMyTenantShowsInvite(YES, NO, YES), @"员工不绑码（服务端回 400106）");
    XCTAssertFalse(IMMyTenantShowsInvite(NO, NO, NO), @"邀请码功能关着");
}

#pragma mark - directory/me

- (void)testTenantStoreApplyMe {
    IMTenantStore *st = [IMTenantStore new];
    XCTAssertTrue([st applyMe:@{ @"bindings": @[] }]);
    XCTAssertTrue(st.loaded, @"拿到过 me（无集团）");
    XCTAssertFalse(st.hasTenant);
    XCTAssertFalse([st applyMe:@{ @"bindings": @[] }], @"同一份不算变化");
    NSDictionary *customer = @{ @"tenant": @{ @"tenant_id": @"T", @"name": @"星海集团", @"short_name": @"" },
                                @"kind": @"customer",
                                @"bindings": @[ @{ @"unit_id": @"U1", @"name": @"星海华东", @"kind": @"sub" }, @{ @"name": @"缺 id" } ],
                                @"notice_pending": @YES };
    XCTAssertTrue([st applyMe:customer]);
    XCTAssertTrue(st.hasTenant);
    XCTAssertTrue(st.isCustomer);
    XCTAssertEqualObjects(st.tenantName, @"星海集团");
    XCTAssertEqual(st.bindings.count, 1u);
    XCTAssertTrue(st.noticePending);
    [st markNoticeAcked];
    XCTAssertFalse(st.noticePending);
    [st applyMe:@{ @"tenant": @{ @"name": @"星海集团" }, @"kind": @"staff", @"is_cs": @YES,
                   @"unit": @{ @"name": @"星海华东" }, @"dept": @{ @"name": @"售后" }, @"bindings": @[] }];
    XCTAssertFalse(st.isCustomer);
    XCTAssertTrue(st.isCS);
    XCTAssertEqualObjects(st.deptName, @"售后");
}

#pragma mark - 资料 / 找人 / 扫码

- (void)testUserCardParsesTenantFields {
    NSArray *rows = @[ @{ @"user_id": @"1", @"direct_chat": @YES, @"org_label": @"星海华东 · 售后" } ];
    IMUserCard *c = [IMUserCard cardsFromArray:rows].firstObject;
    XCTAssertTrue(c.directChat);
    XCTAssertEqualObjects(c.orgLabel, @"星海华东 · 售后");
}

- (void)testQRUserCardToken {
    XCTAssertEqualObjects(IMQRUserCardToken(@"http://127.0.0.1:8080/q/u/Ab3dEf"), @"Ab3dEf");
    XCTAssertEqualObjects(IMQRUserCardToken(@" https://im.example.com/q/u/XYZ \n"), @"XYZ");
    XCTAssertNil(IMQRUserCardToken(@"https://im.example.com/q/g/XYZ"), @"群码不是名片码");
    XCTAssertNil(IMQRUserCardToken(@"https://im.example.com/q/u/"));
    XCTAssertNil(IMQRUserCardToken(@"hello"));
    XCTAssertNil(IMQRUserCardToken(nil));
    XCTAssertEqualObjects(IMQRUserCardToken(@"q/u/AbC"), @"AbC", @"裸串");
    XCTAssertEqualObjects(IMQRUserCardToken(@"https://h.com/im/q/u/AbC?x=1"), @"AbC", @"子路径部署 + query");
}

- (void)testErrorResponseDataRoundTrip {
    NSError *e = [NSError errorWithDomain:@"t" code:IMErrCodeOrgUnreachable userInfo:nil];
    XCTAssertNil(IMErrorResponseData(e));
    XCTAssertEqual(IMErrorAttachingResponseData(e, @{}), e, @"空 data 原样返回");
    NSDictionary *data = @{ @"nickname": @"王五" };
    NSError *w = IMErrorAttachingResponseData(e, data);
    XCTAssertEqual(w.code, IMErrCodeOrgUnreachable);
    XCTAssertEqualObjects(IMErrorResponseData(w)[@"nickname"], @"王五");
}

- (void)testTenantErrorCodesHaveText {
    for (NSNumber *code in @[@400101, @400103, @400104, @400105, @400106, @400120, @400121, @400122, @400125]) {
        NSString *key = [NSString stringWithFormat:@"err.%@", code];
        XCTAssertEqualObjects(IMFriendlyMessageForCode(code.integerValue), IMLocalized(key));
        XCTAssertNotEqualObjects(IMLocalized(key), key, @"%@ 缺文案", key);
    }
    XCTAssertNil(IMFriendlyMessageForCode(400111), @"后台码回退服务端原文");
}

- (void)testMemberOrgExitSysEvent {
    IMSysSegment *who = [IMSysSegment new];
    who.uid = @"u9";
    who.text = @"王芳";
    NSArray<IMSysSegment *> *out = IMSegmentsForSysEvent(@"member_org_exit", nil, @[who]);
    XCTAssertNotNil(out);
    BOOL hasName = NO;
    for (IMSysSegment *s in out) { if ([s.uid isEqualToString:@"u9"]) { hasName = YES; } }
    XCTAssertTrue(hasName, @"被移出者是可点的人名段");
}

#pragma mark - 资料页：免好友直聊与好友同等（2026-11-22）

static NSArray<NSString *> *IMPillActions(IMChatDetailViewController *vc) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *spec in [vc actionPillSpecs]) { [a addObject:spec[@"a"]]; }
    return a;
}

- (void)testProfileOfDirectChatPeerMatchesFriend {
    IMChatDetailViewController *vc = [[IMChatDetailViewController alloc] initSingleWithHost:@"127.0.0.1:59391" userID:@"t-me"
        peerID:@"8000000001" peerNickname:@"客服" peerAvatarURL:nil];
    vc.peerIsFriend = NO;
    vc.peerDirectChat = NO;
    XCTAssertEqualObjects(IMPillActions(vc), (@[@"addfriend"]), @"陌生人：只有加好友");
    XCTAssertEqual([vc sectionLayout].count, 0u, @"陌生人：不显示资料卡 / 设置 / 页签");

    vc.peerDirectChat = YES; // 集团客户 ↔ 所绑子公司客服
    NSArray *acts = IMPillActions(vc);
    for (NSString *want in @[@"call", @"video", @"search", @"more"]) {
        XCTAssertTrue([acts containsObject:want], @"免好友直聊应有 %@", want);
    }
    XCTAssertFalse([acts containsObject:@"addfriend"], @"加好友收进「更多」，不占操作排");
    XCTAssertGreaterThan([vc sectionLayout].count, 0u, @"免好友直聊：资料卡 / 设置 / 页签和好友一样");

    vc.peerDirectChat = NO; vc.peerUnreachable = YES; // 400120（applyPeerUnreachable 同时清直聊）：什么都不给
    XCTAssertEqual(IMPillActions(vc).count, 0u);
    XCTAssertEqual([vc sectionLayout].count, 0u);
    vc.peerIsFriend = YES; // 残留好友行也一样（三端同口径）
    XCTAssertEqual(IMPillActions(vc).count, 0u);
    XCTAssertEqual([vc sectionLayout].count, 0u, @"400120 的残留好友：只显头像昵称");
}

@end
