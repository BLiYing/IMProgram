//  IMMuteStateTests.m
//  IMIsMutedNow / IMMuteUntilLabelMake 纯函数单测：读三端共用向量
//  IMServer/docs/conformance/mute_state.json（isMutedNow 6 例 + untilLabel 8 例，NOTIFICATIONS_P1_DESIGN
//  §4.3）。按本文件相对路径找，也可用环境变量 IM_MUTE_STATE_VECTORS 指定。
//  找不到时**失败**而不是跳过——静默跳过等于没测（同 IMAlertDecisionTests 先例）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMMuteState.h"

@interface IMMuteStateTests : XCTestCase
@end

@implementation IMMuteStateTests

- (NSDictionary *)vectorRoot {
    NSString *path = NSProcessInfo.processInfo.environment[@"IM_MUTE_STATE_VECTORS"];
    if (path.length == 0) {
        NSString *repo = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]; // …/IMProgram
        path = [[repo stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"IMServer/docs/conformance/mute_state.json"];
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"找不到共用向量 %@（IM_MUTE_STATE_VECTORS 可指定）", path);
    NSDictionary *root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    XCTAssertTrue([root isKindOfClass:NSDictionary.class]);
    return root;
}

- (void)testIsMutedNowConformanceVectors {
    NSArray<NSDictionary *> *cases = self.vectorRoot[@"isMutedNow"];
    XCTAssertGreaterThanOrEqual(cases.count, 6u);
    for (NSDictionary *c in cases) {
        BOOL muted = [c[@"muted"] boolValue];
        int64_t muteUntil = [c[@"muteUntil"] longLongValue];
        int64_t nowMs = [c[@"nowMs"] longLongValue];
        BOOL expect = [c[@"expect"] boolValue];
        XCTAssertEqual(IMIsMutedNow(muted, muteUntil, nowMs), expect, @"%@", c[@"name"]);
    }
}

- (void)testUntilLabelConformanceVectors {
    NSArray<NSDictionary *> *cases = self.vectorRoot[@"untilLabel"];
    XCTAssertGreaterThanOrEqual(cases.count, 8u);
    for (NSDictionary *c in cases) {
        int64_t muteUntil = [c[@"muteUntil"] longLongValue];
        int64_t nowMs = [c[@"nowMs"] longLongValue];
        NSInteger tzOffsetMinutes = [c[@"tzOffsetMinutes"] integerValue];
        NSTimeZone *tz = [NSTimeZone timeZoneForSecondsFromGMT:tzOffsetMinutes * 60];
        IMMuteUntilLabel *label = IMMuteUntilLabelMake(muteUntil, nowMs, tz);
        NSDictionary *expect = c[@"expect"];
        NSString *name = c[@"name"];

        NSString *expectKind = expect[@"kind"];
        IMMuteUntilKind wantKind = [expectKind isEqualToString:@"forever"] ? IMMuteUntilKindForever
            : [expectKind isEqualToString:@"today"] ? IMMuteUntilKindToday
            : [expectKind isEqualToString:@"tomorrow"] ? IMMuteUntilKindTomorrow
            : IMMuteUntilKindDate;
        XCTAssertEqual(label.kind, wantKind, @"%@ (kind)", name);

        id expectTime = expect[@"time"];
        if (expectTime == NSNull.null || expectTime == nil) {
            XCTAssertNil(label.time, @"%@ (time should be nil)", name);
        } else {
            XCTAssertEqualObjects(label.time, expectTime, @"%@ (time)", name);
        }
        NSInteger wantMonth = [expect[@"month"] isKindOfClass:NSNull.class] ? 0 : [expect[@"month"] integerValue];
        NSInteger wantDay = [expect[@"day"] isKindOfClass:NSNull.class] ? 0 : [expect[@"day"] integerValue];
        XCTAssertEqual(label.month, wantMonth, @"%@ (month)", name);
        XCTAssertEqual(label.day, wantDay, @"%@ (day)", name);
    }
}

#pragma mark - 补充（向量之外的边界）

- (void)testMutedFalseIgnoresLeftoverMuteUntil {
    // muted=false 时残留的 muteUntil 不算免打扰——即便它还没到期。
    XCTAssertFalse(IMIsMutedNow(NO, 99999999999999LL, 0));
}

- (void)testExactlyAtMuteUntilIsUnmuted {
    // now == until 视为"已解除"，不是"还差一毫秒"。
    XCTAssertFalse(IMIsMutedNow(YES, 1000, 1000));
    XCTAssertTrue(IMIsMutedNow(YES, 1000, 999));
}

@end
