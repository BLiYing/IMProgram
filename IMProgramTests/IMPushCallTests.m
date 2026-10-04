//  IMPushCallTests.m
//  来电横幅（离线推送，PUSH_M5_DESIGN §3.8）App 侧的纯逻辑：认出通话提醒、按钮动作等来电到了只执行一次。

#import <XCTest/XCTest.h>
#import "IMPushCall.h"

@interface IMPushCallTests : XCTestCase
@end

@implementation IMPushCallTests

- (void)testCallIDFromUserInfo {
    XCTAssertEqualObjects(IMPushCallIDFromUserInfo(@{@"call_id": @"call-1", @"call_kind": @"incoming"}), @"call-1");
    XCTAssertNil(IMPushCallIDFromUserInfo(@{@"conv_id": @"g_1", @"conv_seq": @5}), @"普通消息推送不是通话提醒");
    XCTAssertNil(IMPushCallIDFromUserInfo(@{@"call_id": @""}));
    XCTAssertNil(IMPushCallIDFromUserInfo(@{@"call_id": @42}));
    XCTAssertNil(IMPushCallIDFromUserInfo(nil));
}

- (void)testPendingActionConsumedOnceForThatCallOnly {
    IMPushCallPendingAction *p = [IMPushCallPendingAction new];
    [p requestCallID:@"c1" accept:YES nowMS:1000];
    XCTAssertNil([p consumeCallID:@"c2" nowMS:2000], @"别的来电不执行");
    XCTAssertEqualObjects([p consumeCallID:@"c1" nowMS:2000], @YES);
    XCTAssertNil([p consumeCallID:@"c1" nowMS:2000], @"只执行一次");
}

- (void)testPendingActionExpiresAfterRingWindow {
    IMPushCallPendingAction *p = [IMPushCallPendingAction new];
    [p requestCallID:@"c1" accept:NO nowMS:0];
    XCTAssertNil([p consumeCallID:@"c1" nowMS:120001]);
}

@end
