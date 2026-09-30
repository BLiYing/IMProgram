//  IMConversationRouterTests.m
//  IMConversationRouter.openConversation: 必须原样传回 opener 的返回值（M5 /code-review：
//  IMPendingNotificationRoute 靠这个返回值判断"是不是真的跳转了"，传丢了会让"日志说打开了、
//  屏幕其实没跳"这种坑再犯一次）。

#import <XCTest/XCTest.h>
#import "../IMProgram/Common/IMConversationRouter.h"
#import "../IMProgram/Models/IMConversation.h"

@interface IMConversationRouterTests : XCTestCase
@end

@implementation IMConversationRouterTests

- (void)tearDown {
    IMConversationRouter.opener = nil; // 不同测试用例、不同文件之间不许互相沾光
    [super tearDown];
}

- (void)testReturnsNoWhenNoOpenerRegistered {
    IMConversation *c = [IMConversation new];
    c.convID = @"u_1001_u_1002";
    XCTAssertFalse([IMConversationRouter openConversation:c host:@"h" userID:@"1001"]);
}

- (void)testReturnsNoWhenConversationIsNil {
    IMConversationRouter.opener = ^BOOL(NSString *host, NSString *userID, IMConversation *conv) { return YES; };
    XCTAssertFalse([IMConversationRouter openConversation:nil host:@"h" userID:@"1001"]);
}

- (void)testPassesThroughOpenerReturnValue {
    IMConversation *c = [IMConversation new];
    c.convID = @"u_1001_u_1002";
    __block NSString *seenHost, *seenUserID;
    __block IMConversation *seenConv;
    IMConversationRouter.opener = ^BOOL(NSString *host, NSString *userID, IMConversation *conv) {
        seenHost = host; seenUserID = userID; seenConv = conv;
        return NO; // 模拟"窗口还没就绪，这次没打开"
    };
    XCTAssertFalse([IMConversationRouter openConversation:c host:@"h" userID:@"1001"]);
    XCTAssertEqualObjects(seenHost, @"h");
    XCTAssertEqualObjects(seenUserID, @"1001");
    XCTAssertEqualObjects(seenConv, c);

    IMConversationRouter.opener = ^BOOL(NSString *host, NSString *userID, IMConversation *conv) { return YES; };
    XCTAssertTrue([IMConversationRouter openConversation:c host:@"h" userID:@"1001"]);
}

@end
