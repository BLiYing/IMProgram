//  IMPendingNotificationRouteTests.m
//  纯函数 IMPushConvIDFromUserInfo：通知 userInfo → conv_id（M5，点通知进会话的解析口径）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMPendingNotificationRoute.h"
#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Common/IMConversationRouter.h"

@interface IMPendingNotificationRouteTests : XCTestCase
@end

@implementation IMPendingNotificationRouteTests

- (void)testExtractsConvIDWhenPresent {
    NSDictionary *userInfo = @{ @"conv_id": @"u_1001_u_1002", @"conv_seq": @812 };
    XCTAssertEqualObjects(IMPushConvIDFromUserInfo(userInfo), @"u_1001_u_1002");
}

- (void)testReturnsNilWhenKeyMissing {
    XCTAssertNil(IMPushConvIDFromUserInfo(@{ @"conv_seq": @812 }));
}

- (void)testReturnsNilWhenValueIsNotAString {
    // APNs 自定义字段理论上都是字符串，但防御非法/被篡改的 payload。
    XCTAssertNil(IMPushConvIDFromUserInfo(@{ @"conv_id": @1002 }));
}

- (void)testReturnsNilWhenValueIsEmptyString {
    XCTAssertNil(IMPushConvIDFromUserInfo(@{ @"conv_id": @"" }));
}

- (void)testReturnsNilForNilUserInfo {
    XCTAssertNil(IMPushConvIDFromUserInfo(nil));
}

- (void)testReturnsNilForEmptyDictionary {
    XCTAssertNil(IMPushConvIDFromUserInfo(@{}));
}

#pragma mark - IMPlaceholderConversationForPush

- (void)testPlaceholderP2PPicksTheOtherSideAsPeer {
    IMConversation *c = IMPlaceholderConversationForPush(@"u_1001_u_1002", @"1002", @"张曼玉");
    XCTAssertNotNil(c);
    XCTAssertFalse(c.isGroup);
    XCTAssertEqualObjects(c.peer, @"1001");
    XCTAssertEqualObjects(c.peerNickname, @"张曼玉");
    XCTAssertEqualObjects(c.convID, @"u_1001_u_1002");
    XCTAssertEqualObjects(IMPlaceholderConversationForPush(@"u_1001_u_1002", @"1001", nil).peer, @"1002");
}

- (void)testPlaceholderGroupUsesTitleAsName {
    IMConversation *c = IMPlaceholderConversationForPush(@"g_abc", @"1001", @"周末爬山群");
    XCTAssertTrue(c.isGroup);
    XCTAssertEqualObjects(c.name, @"周末爬山群");
}

- (void)testPlaceholderNilWhenUnparseableOrNotMine {
    XCTAssertNil(IMPlaceholderConversationForPush(@"u_1001_u_1002", @"1003", @"x")); // 两端都不是自己
    XCTAssertNil(IMPlaceholderConversationForPush(@"weird", @"1001", @"x"));
    XCTAssertNil(IMPlaceholderConversationForPush(@"u_1001", @"1001", @"x"));
    XCTAssertNil(IMPlaceholderConversationForPush(@"u_1001_u_1002", nil, @"x"));
}

#pragma mark - tryRouteWithHost:userID: 在 opener 报"没打开"时要重试，不能当场清掉 pending

- (void)tearDown {
    IMConversationRouter.opener = nil;
    [super tearDown];
}

/// 复现真机上的坑：会话对象凑出来了（这里走占位会话那条路，不依赖真实 IMDatabase 内容），
/// 但 opener 第一次报 NO（模拟冷启动早期窗口还没建好）——必须重试到 opener 真的返回 YES 为止，
/// 而不是第一次调用完就把 pending 清掉、日志却打一行"已打开"。
- (void)testRetriesUntilOpenerActuallySucceeds {
    __block NSInteger calls = 0;
    XCTestExpectation *opened = [self expectationWithDescription:@"最终打开成功"];
    IMConversationRouter.opener = ^BOOL(NSString *host, NSString *userID, IMConversation *conv) {
        calls++;
        if (calls < 3) { return NO; } // 前两次都当作"窗口还没就绪"，逼着走下面的退避重试
        [opened fulfill];
        return YES;
    };
    [IMPendingNotificationRoute.shared setPendingConvID:@"u_1001_u_1002" title:@"张三"];
    // 只手动驱动一次；后续两次交给内部的 dispatch_after 退避定时器自动补——与真机上
    // "opener 第一次报 NO"完全同一条路径，不是靠测试代码硬凑次数。
    [IMPendingNotificationRoute.shared tryRouteWithHost:@"h" userID:@"1001"];
    // 退避名义上 0.5s + 1.0s；全量串行跑时主队列很挤，3s 偶发超时（2026-09-30 全量红过一次、单跑必绿），放宽到 8s。
    [self waitForExpectations:@[opened] timeout:8.0];
    XCTAssertGreaterThanOrEqual(calls, 3); // 第 1、2 次都失败过，不是侥幸第一次就"成功"
    NSInteger callsAfterSuccess = calls;
    // 已成功过一次：pending 已清空，再调用不该又触发 opener。
    [IMPendingNotificationRoute.shared tryRouteWithHost:@"h" userID:@"1001"];
    XCTAssertEqual(calls, callsAfterSuccess);
}

@end
