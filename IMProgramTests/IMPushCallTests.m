//  IMPushCallTests.m
//  来电横幅（离线推送，PUSH_M5_DESIGN §3.8）App 侧的纯逻辑：认出通话提醒、按钮动作等来电到了只执行一次。

#import <XCTest/XCTest.h>
#import "IMPushCall.h"
#import <UserNotifications/UserNotifications.h>

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

- (void)testTapFromResponse {
    NSDictionary *incoming = @{@"call_id": @"call-1", @"call_kind": @"incoming"};
    XCTAssertEqual(IMPushCallTapFrom(IMPushCallActionAccept, incoming), IMPushCallTapAccept);
    XCTAssertEqual(IMPushCallTapFrom(IMPushCallActionReject, incoming), IMPushCallTapReject);
    XCTAssertEqual(IMPushCallTapFrom(UNNotificationDefaultActionIdentifier, incoming), IMPushCallTapShow, @"点来电横幅本身 = 看接听页");
    XCTAssertEqual(IMPushCallTapFrom(UNNotificationDefaultActionIdentifier, (@{@"call_id": @"call-1", @"call_kind": @"missed"})),
                   IMPushCallTapNone, @"未接提醒点开进会话");
    XCTAssertEqual(IMPushCallTapFrom(UNNotificationDefaultActionIdentifier, (@{@"call_id": @"call-1", @"call_kind": @"ended"})), IMPushCallTapNone);
    XCTAssertEqual(IMPushCallTapFrom(UNNotificationDismissActionIdentifier, incoming), IMPushCallTapNone, @"划掉横幅不算");
    XCTAssertEqual(IMPushCallTapFrom(UNNotificationDefaultActionIdentifier, (@{@"call_id": @"call-1", @"call_kind": @1})), IMPushCallTapNone);
    XCTAssertEqual(IMPushCallTapFrom(nil, nil), IMPushCallTapNone);
}

/// 点横幅本身（要看接听页）与按钮同一套「记一条、来了取走」（BACKLOG B3），后点的覆盖先点的。
- (void)testPendingShowOverwritesAndIsConsumedOnce {
    IMPushCallPendingAction *p = [IMPushCallPendingAction new];
    [p requestCallID:@"c1" tap:IMPushCallTapShow nowMS:0];
    [p requestCallID:@"c1" tap:IMPushCallTapAccept nowMS:10];
    XCTAssertEqualObjects([p consumeCallID:@"c1" nowMS:20], @(IMPushCallTapAccept), @"后点的按钮为准");
    [p requestCallID:@"c2" tap:IMPushCallTapShow nowMS:30];
    XCTAssertEqualObjects([p consumeCallID:@"c2" nowMS:40], @(IMPushCallTapShow));
    XCTAssertNil([p consumeCallID:@"c2" nowMS:50]);
}

- (void)testPendingActionConsumedOnceForThatCallOnly {
    IMPushCallPendingAction *p = [IMPushCallPendingAction new];
    [p requestCallID:@"c1" tap:IMPushCallTapAccept nowMS:1000];
    XCTAssertNil([p consumeCallID:@"c2" nowMS:2000], @"别的来电不执行");
    XCTAssertEqualObjects([p consumeCallID:@"c1" nowMS:2000], @(IMPushCallTapAccept));
    XCTAssertNil([p consumeCallID:@"c1" nowMS:2000], @"只执行一次");
}

- (void)testPendingActionExpiresAfterRingWindow {
    IMPushCallPendingAction *p = [IMPushCallPendingAction new];
    [p requestCallID:@"c1" tap:IMPushCallTapReject nowMS:0];
    XCTAssertNil([p consumeCallID:@"c1" nowMS:120001]);
}

@end
