//  IMPendingNotificationRouteTests.m
//  纯函数 IMPushConvIDFromUserInfo：通知 userInfo → conv_id（M5，点通知进会话的解析口径）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMPendingNotificationRoute.h"
#import "../IMProgram/Models/IMConversation.h"

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

@end
