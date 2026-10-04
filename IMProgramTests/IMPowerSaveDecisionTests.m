//  IMPowerSaveDecisionTests.m
//  IMPowerSaveActive 纯函数单测：读三端共用向量 IMServer/docs/conformance/power_save.json（改规则先改向量）。
//  按本文件相对路径找，也可用环境变量 IM_POWER_SAVE_VECTORS 指定。找不到时**失败**而不是跳过
//  （同 IMAlertDecisionTests 先例）。另含阈值夹紧、pausedCount、§5 提示状态机（对端 PowerSavePromptTest.kt 逐条对应）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMPowerSaveDecision.h"

static const int64_t kMin = 60000;

@interface IMPowerSaveDecisionTests : XCTestCase
@end

@implementation IMPowerSaveDecisionTests

- (NSArray<NSDictionary *> *)vectors {
    NSString *path = NSProcessInfo.processInfo.environment[@"IM_POWER_SAVE_VECTORS"];
    if (path.length == 0) {
        NSString *repo = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]; // …/IMProgram
        path = [[repo stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"IMServer/docs/conformance/power_save.json"];
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"找不到共用向量 %@（IM_POWER_SAVE_VECTORS 可指定）", path);
    NSDictionary *root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSArray *cases = root[@"cases"];
    XCTAssertGreaterThanOrEqual(cases.count, 10u);
    return cases;
}

static id NilIfNull(id v) { return (v == NSNull.null) ? nil : v; }

static IMPowerSaveContext *ContextFromDict(NSDictionary *c) {
    IMPowerSaveContext *ctx = [IMPowerSaveContext new];
    ctx.mode = IMPowerSaveModeFromWire(c[@"mode"]);
    ctx.threshold = [c[@"threshold"] integerValue];
    ctx.level = NilIfNull(c[@"level"]);
    ctx.charging = NilIfNull(c[@"charging"]);
    ctx.followSystem = [c[@"followSystem"] boolValue];
    ctx.systemSaver = NilIfNull(c[@"systemSaver"]);
    return ctx;
}

static IMPowerSaveContext *Ctx(IMPowerSaveMode mode, NSInteger thr, NSNumber *level, NSNumber *charging) {
    IMPowerSaveContext *ctx = [IMPowerSaveContext new];
    ctx.mode = mode; ctx.threshold = thr; ctx.level = level; ctx.charging = charging;
    return ctx;
}

#pragma mark - 向量

- (void)testConformanceVectors {
    for (NSDictionary *c in [self vectors]) {
        BOOL got = IMPowerSaveActive(ContextFromDict(c[@"ctx"]));
        XCTAssertEqual(got, [c[@"active"] boolValue], @"%@", c[@"name"]);
    }
}

#pragma mark - 向量之外的边界

- (void)testReasonPriorityAlwaysOverBatteryOverSystem {
    IMPowerSaveContext *ctx = Ctx(IMPowerSaveModeAlways, 15, @5, @NO);
    ctx.followSystem = YES; ctx.systemSaver = @YES;
    XCTAssertEqual(IMPowerSaveReasonFor(ctx), IMPowerSaveReasonAlways);
    ctx.mode = IMPowerSaveModeAuto;
    XCTAssertEqual(IMPowerSaveReasonFor(ctx), IMPowerSaveReasonBattery);
    ctx.level = @80;
    XCTAssertEqual(IMPowerSaveReasonFor(ctx), IMPowerSaveReasonSystem);
    ctx.followSystem = NO;
    XCTAssertEqual(IMPowerSaveReasonFor(ctx), IMPowerSaveReasonNone);
}

- (void)testClampThreshold {
    XCTAssertEqual(IMPowerSaveClampThreshold(-3), 5);
    XCTAssertEqual(IMPowerSaveClampThreshold(0), 5);
    XCTAssertEqual(IMPowerSaveClampThreshold(5), 5);
    XCTAssertEqual(IMPowerSaveClampThreshold(33), 33); // 不对齐步长，步长由滑块保证
    XCTAssertEqual(IMPowerSaveClampThreshold(50), 50);
    XCTAssertEqual(IMPowerSaveClampThreshold(99), 50);
}

- (void)testOutOfRangeThresholdIsClampedBeforeComparing {
    XCTAssertTrue(IMPowerSaveActive(Ctx(IMPowerSaveModeAuto, 99, @50, @NO)));  // 99 -> 50，level 50 触发
    XCTAssertFalse(IMPowerSaveActive(Ctx(IMPowerSaveModeAuto, 99, @51, @NO)));
    XCTAssertFalse(IMPowerSaveActive(Ctx(IMPowerSaveModeAuto, 0, @6, @NO)));   // 0 -> 5，level 6 不触发
    XCTAssertTrue(IMPowerSaveActive(Ctx(IMPowerSaveModeAuto, 0, @5, @NO)));
}

- (void)testModeWire {
    XCTAssertEqual(IMPowerSaveModeFromWire(@"auto"), IMPowerSaveModeAuto);
    XCTAssertEqual(IMPowerSaveModeFromWire(@"always"), IMPowerSaveModeAlways);
    XCTAssertEqual(IMPowerSaveModeFromWire(@"garbage"), IMPowerSaveModeOff);
    XCTAssertEqual(IMPowerSaveModeFromWire(nil), IMPowerSaveModeOff);
    XCTAssertEqualObjects(IMPowerSaveModeToWire(IMPowerSaveModeAuto), @"auto");
    XCTAssertEqualObjects(IMPowerSaveModeToWire(IMPowerSaveModeAlways), @"always");
    XCTAssertEqualObjects(IMPowerSaveModeToWire(IMPowerSaveModeOff), @"off");
}

#pragma mark - pausedCount

- (void)testPausedCountOnlyCountsUserOnItemsAndOnlyWhenActive {
    XCTAssertEqual(IMPowerSavePausedCount(YES, @[@YES, @YES, @YES]), 3);
    XCTAssertEqual(IMPowerSavePausedCount(YES, @[@YES, @NO, @YES]), 2);   // 用户自己关掉的不算
    XCTAssertEqual(IMPowerSavePausedCount(YES, @[@NO, @NO, @NO]), 0);
    XCTAssertEqual(IMPowerSavePausedCount(NO, @[@YES, @YES, @YES]), 0);   // 未生效恒 0
}

#pragma mark - §5 提示状态机（对应 Android PowerSavePromptTest）

- (void)testForegroundRisingEdgeShowsOnceUntilCharging {
    IMPowerSavePromptState *s = [IMPowerSavePromptState new];
    IMPowerSavePromptStep *st = IMPowerSavePromptOnStatus(s, YES, IMPowerSaveReasonBattery, @NO, YES, 0);
    XCTAssertTrue(st.showNow); s = st.state;
    st = IMPowerSavePromptOnStatus(s, YES, IMPowerSaveReasonBattery, @NO, YES, kMin); s = st.state; // 电量继续掉：不重弹
    XCTAssertFalse(st.showNow);
    st = IMPowerSavePromptOnStatus(s, NO, IMPowerSaveReasonNone, @YES, YES, 2 * kMin); s = st.state; // 开始充电：重置
    XCTAssertFalse(s.shown);
    st = IMPowerSavePromptOnStatus(s, NO, IMPowerSaveReasonNone, @NO, YES, 3 * kMin); s = st.state;
    st = IMPowerSavePromptOnStatus(s, YES, IMPowerSaveReasonBattery, @NO, YES, 4 * kMin);            // 下一个放电周期再弹
    XCTAssertTrue(st.showNow);
}

- (void)testManualAlwaysAndSystemNeverPrompt {
    for (NSNumber *r in @[@(IMPowerSaveReasonAlways), @(IMPowerSaveReasonSystem)]) {
        IMPowerSavePromptStep *st = IMPowerSavePromptOnStatus([IMPowerSavePromptState new], YES, (IMPowerSaveReason)r.integerValue, @NO, YES, 0);
        XCTAssertFalse(st.showNow);
    }
}

- (void)testBackgroundTriggerShowsOnReturnWithinTenMinutesOnlyOnce {
    IMPowerSavePromptStep *st = IMPowerSavePromptOnStatus([IMPowerSavePromptState new], YES, IMPowerSaveReasonBattery, @NO, NO, 0);
    XCTAssertFalse(st.showNow);
    IMPowerSavePromptStep *back = IMPowerSavePromptOnForeground(st.state, YES, 10 * kMin);
    XCTAssertTrue(back.showNow);
    XCTAssertFalse(IMPowerSavePromptOnForeground(back.state, YES, 10 * kMin).showNow); // 只补一次
}

- (void)testBackgroundTriggerExpiresAfterTenMinutesOrWhenNoLongerActive {
    IMPowerSavePromptState *st = IMPowerSavePromptOnStatus([IMPowerSavePromptState new], YES, IMPowerSaveReasonBattery, @NO, NO, 0).state;
    XCTAssertFalse(IMPowerSavePromptOnForeground(st, YES, 10 * kMin + 1).showNow);
    XCTAssertFalse(IMPowerSavePromptOnForeground(st, NO, kMin).showNow);
}

- (void)testChargingBeforeReturnCancelsPending {
    IMPowerSavePromptState *s = IMPowerSavePromptOnStatus([IMPowerSavePromptState new], YES, IMPowerSaveReasonBattery, @NO, NO, 0).state;
    s = IMPowerSavePromptOnStatus(s, NO, IMPowerSaveReasonNone, @YES, NO, kMin).state;
    XCTAssertFalse(IMPowerSavePromptOnForeground(s, YES, 2 * kMin).showNow);
}

- (void)testAlwaysToAutoWhileAlreadyActiveIsNotRisingEdge {
    IMPowerSavePromptState *s = IMPowerSavePromptOnStatus([IMPowerSavePromptState new], YES, IMPowerSaveReasonAlways, @NO, YES, 0).state;
    XCTAssertFalse(IMPowerSavePromptOnStatus(s, YES, IMPowerSaveReasonBattery, @NO, YES, kMin).showNow);
}

- (void)testStartupShownSurvivesOnlyWhileStillBatteryTriggered {
    XCTAssertTrue(IMPowerSavePromptStartupShown(YES, IMPowerSaveReasonBattery));
    XCTAssertFalse(IMPowerSavePromptStartupShown(YES, IMPowerSaveReasonNone));   // 已充电 / 回到阈值以上
    XCTAssertFalse(IMPowerSavePromptStartupShown(YES, IMPowerSaveReasonAlways));
    XCTAssertFalse(IMPowerSavePromptStartupShown(NO, IMPowerSaveReasonBattery));
}

- (void)testRestartedInSameCycleDoesNotPromptAgain {
    IMPowerSavePromptState *s = [IMPowerSavePromptState new];
    s.shown = IMPowerSavePromptStartupShown(YES, IMPowerSaveReasonBattery); // 持久化为真 + 仍电量触发
    XCTAssertFalse(IMPowerSavePromptOnStatus(s, YES, IMPowerSaveReasonBattery, @NO, YES, 0).showNow);
}

- (void)testStateMachineDoesNotMutateInput {
    IMPowerSavePromptState *s = [IMPowerSavePromptState new];
    IMPowerSavePromptOnStatus(s, YES, IMPowerSaveReasonBattery, @NO, YES, 0);
    XCTAssertFalse(s.shown);
    XCTAssertFalse(s.prevActive);
}

@end
