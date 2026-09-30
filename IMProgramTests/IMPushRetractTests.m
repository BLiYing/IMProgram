//  IMPushRetractTests.m
//  纯函数 IMPushUserInfoMatchesMessage：消息被撤回/删除时，通知中心里哪条通知该拿掉（M5）。

#import <XCTest/XCTest.h>
#import "IMPushRetract.h"

@interface IMPushRetractTests : XCTestCase
@end

@implementation IMPushRetractTests

- (NSDictionary *)userInfoWithConv:(id)conv seq:(id)seq {
    NSMutableDictionary *d = [@{ @"aps": @{ @"alert": @{ @"title": @"张三", @"body": @"在吗" } } } mutableCopy];
    if (conv) { d[@"conv_id"] = conv; }
    if (seq) { d[@"conv_seq"] = seq; }
    return d;
}

- (void)testMatchesSameConversationAndSeq {
    XCTAssertTrue(IMPushUserInfoMatchesMessage([self userInfoWithConv:@"u_1_u_2" seq:@812], @"u_1_u_2", 812));
}

- (void)testOtherMessageInSameConversationIsLeftAlone {
    XCTAssertFalse(IMPushUserInfoMatchesMessage([self userInfoWithConv:@"u_1_u_2" seq:@813], @"u_1_u_2", 812));
}

- (void)testSameSeqInAnotherConversationIsLeftAlone {
    XCTAssertFalse(IMPushUserInfoMatchesMessage([self userInfoWithConv:@"g_9" seq:@812], @"u_1_u_2", 812));
}

/// 服务端替换后的撤回提示带着同样的 conv_id/conv_seq（多一个 retract 字段）——人回到 App 后一并清掉。
- (void)testReplacedRetractionNoticeAlsoMatches {
    NSMutableDictionary *d = [[self userInfoWithConv:@"u_1_u_2" seq:@812] mutableCopy];
    d[@"retract"] = @"recall";
    XCTAssertTrue(IMPushUserInfoMatchesMessage(d, @"u_1_u_2", 812));
}

- (void)testMissingOrMistypedFieldsNeverMatch {
    XCTAssertFalse(IMPushUserInfoMatchesMessage([self userInfoWithConv:@"u_1_u_2" seq:nil], @"u_1_u_2", 812));
    XCTAssertFalse(IMPushUserInfoMatchesMessage([self userInfoWithConv:nil seq:@812], @"u_1_u_2", 812));
    XCTAssertFalse(IMPushUserInfoMatchesMessage([self userInfoWithConv:@"u_1_u_2" seq:@"812"], @"u_1_u_2", 812));
    XCTAssertFalse(IMPushUserInfoMatchesMessage([self userInfoWithConv:@1002 seq:@812], @"u_1_u_2", 812));
    XCTAssertFalse(IMPushUserInfoMatchesMessage(nil, @"u_1_u_2", 812));
}

- (void)testInvalidTargetNeverMatches {
    XCTAssertFalse(IMPushUserInfoMatchesMessage([self userInfoWithConv:@"u_1_u_2" seq:@0], @"u_1_u_2", 0));
    XCTAssertFalse(IMPushUserInfoMatchesMessage([self userInfoWithConv:@"" seq:@812], @"", 812));
    XCTAssertFalse(IMPushUserInfoMatchesMessage([self userInfoWithConv:@"u_1_u_2" seq:@812], nil, 812));
}

@end
