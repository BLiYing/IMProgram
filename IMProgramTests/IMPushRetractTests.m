//  IMPushRetractTests.m
//  纯函数 IMPushUserInfoMatchesMessage：消息被撤回/删除时，通知中心里哪条通知该拿掉（M5）。
//  IMPushUserInfoMatchesAnyMessage：批量版（多选），一次扫描对一个 seq 集合。
//  IMPushUserInfoReadThrough / IMPushReadClearFromPayload：别的设备读过后清哪些（PUSH_M5_DESIGN §3.5）。

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

#pragma mark - 批量撤回/删除（多选）

/// 批量版：seq 在集合里就算匹配，不逐条比较——多选删除/撤回一次扫描通知中心用这个。
- (void)testMatchesAnyMessageInTheSet {
    NSSet<NSNumber *> *seqs = [NSSet setWithArray:@[ @811, @812, @813 ]];
    XCTAssertTrue(IMPushUserInfoMatchesAnyMessage([self userInfoWithConv:@"u_1_u_2" seq:@812], @"u_1_u_2", seqs));
    XCTAssertFalse(IMPushUserInfoMatchesAnyMessage([self userInfoWithConv:@"u_1_u_2" seq:@900], @"u_1_u_2", seqs));
}

- (void)testMatchesAnyMessageOnlyWithinThatConversation {
    NSSet<NSNumber *> *seqs = [NSSet setWithArray:@[ @5 ]];
    XCTAssertFalse(IMPushUserInfoMatchesAnyMessage([self userInfoWithConv:@"g_9" seq:@5], @"u_1_u_2", seqs));
}

- (void)testMatchesAnyMessageHandlesEmptyOrInvalidInput {
    NSSet<NSNumber *> *seqs = [NSSet setWithArray:@[ @812 ]];
    XCTAssertFalse(IMPushUserInfoMatchesAnyMessage([self userInfoWithConv:@"u_1_u_2" seq:@812], @"", seqs));
    XCTAssertFalse(IMPushUserInfoMatchesAnyMessage([self userInfoWithConv:@"u_1_u_2" seq:@812], @"u_1_u_2", nil));
    XCTAssertFalse(IMPushUserInfoMatchesAnyMessage([self userInfoWithConv:@"u_1_u_2" seq:@812], @"u_1_u_2", [NSSet set]));
    XCTAssertFalse(IMPushUserInfoMatchesAnyMessage(nil, @"u_1_u_2", seqs));
}

#pragma mark - 已读清通知

- (void)testReadThroughClearsUpToAndIncludingReadPosition {
    XCTAssertTrue(IMPushUserInfoReadThrough([self userInfoWithConv:@"u_1_u_2" seq:@811], @"u_1_u_2", 812));
    XCTAssertTrue(IMPushUserInfoReadThrough([self userInfoWithConv:@"u_1_u_2" seq:@812], @"u_1_u_2", 812));
}

/// 读的同时又来了新消息：位点之后那条的通知要留着。
- (void)testReadThroughLeavesNewerMessages {
    XCTAssertFalse(IMPushUserInfoReadThrough([self userInfoWithConv:@"u_1_u_2" seq:@813], @"u_1_u_2", 812));
}

- (void)testReadThroughOnlyTouchesThatConversation {
    XCTAssertFalse(IMPushUserInfoReadThrough([self userInfoWithConv:@"g_9" seq:@5], @"u_1_u_2", 812));
}

- (void)testReadThroughNeverMatchesUnknownTargets {
    XCTAssertFalse(IMPushUserInfoReadThrough([self userInfoWithConv:@"u_1_u_2" seq:nil], @"u_1_u_2", 812));
    XCTAssertFalse(IMPushUserInfoReadThrough([self userInfoWithConv:@"u_1_u_2" seq:@"5"], @"u_1_u_2", 812));
    XCTAssertFalse(IMPushUserInfoReadThrough([self userInfoWithConv:@"u_1_u_2" seq:@0], @"u_1_u_2", 812));
    XCTAssertFalse(IMPushUserInfoReadThrough([self userInfoWithConv:@"u_1_u_2" seq:@5], @"u_1_u_2", 0));
    XCTAssertFalse(IMPushUserInfoReadThrough(nil, @"u_1_u_2", 812));
}

- (void)testReadClearPayloadParsing {
    NSString *conv = nil;
    int64_t upTo = 0;
    NSDictionary *payload = @{ @"aps": @{ @"badge": @3, @"content-available": @1 },
                               @"conv_id": @"u_1_u_2", @"clear_up_to": @812 };
    XCTAssertTrue(IMPushReadClearFromPayload(payload, &conv, &upTo));
    XCTAssertEqualObjects(conv, @"u_1_u_2");
    XCTAssertEqual(upTo, 812);
}

/// 普通新消息推送 / 撤回推送都没有 clear_up_to：AppDelegate 不能把它们当成清通知。
- (void)testOrdinaryPushIsNotReadClear {
    NSString *conv = nil;
    int64_t upTo = 0;
    XCTAssertFalse(IMPushReadClearFromPayload([self userInfoWithConv:@"u_1_u_2" seq:@812], &conv, &upTo));
    XCTAssertFalse(IMPushReadClearFromPayload(@{ @"conv_id": @"u_1_u_2", @"clear_up_to": @"812" }, &conv, &upTo));
    XCTAssertFalse(IMPushReadClearFromPayload(@{ @"conv_id": @"", @"clear_up_to": @812 }, &conv, &upTo));
    XCTAssertFalse(IMPushReadClearFromPayload(@{ @"conv_id": @"u_1_u_2", @"clear_up_to": @0 }, &conv, &upTo));
    XCTAssertFalse(IMPushReadClearFromPayload(nil, &conv, &upTo));
}

@end
