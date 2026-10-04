//  IMPowerSavingTests.m
//  IMPowerSaving 持有者：偏好持久化 / 默认值 / 夹紧、耗电项生效值（effective = 用户值 && !active）、
//  自动开启提示的上升沿 + 持久化（promptShown）、入口行右值。读数由 -applyBatteryLevel:… 注入，不碰真实电量。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMPowerSaving.h"
#import "../IMProgram/Common/IMAppearance.h"
#import "../IMProgram/Common/IMLocalization.h"

static const int64_t kMinute = 60000;

@interface IMPowerSavingTests : XCTestCase
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, assign) BOOL savedAnimations;
@end

@implementation IMPowerSavingTests

- (void)setUp {
    [super setUp];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:@"im.test.powerSaving"];
    [self.defaults removePersistentDomainForName:@"im.test.powerSaving"];
    self.savedAnimations = IMAppearance.shared.animationsEnabled;
    IMAppearance.shared.animationsEnabled = YES;
}

- (void)tearDown {
    [self.defaults removePersistentDomainForName:@"im.test.powerSaving"];
    IMAppearance.shared.animationsEnabled = self.savedAnimations;
    [super tearDown];
}

- (IMPowerSaving *)store { return [[IMPowerSaving alloc] initWithDefaults:self.defaults]; }

- (void)feed:(IMPowerSaving *)s level:(NSInteger)level charging:(BOOL)charging at:(int64_t)ms foreground:(BOOL)fg {
    [s applyBatteryLevel:@(level) charging:@(charging) systemSaver:nil foreground:fg nowMs:ms];
}

#pragma mark - 偏好

- (void)testDefaults {
    IMPowerSaving *s = [self store];
    XCTAssertEqual(s.mode, IMPowerSaveModeOff);
    XCTAssertEqual(s.threshold, 15);
    XCTAssertTrue(s.followSystem);
    XCTAssertTrue(s.autoDownloadPref);
    XCTAssertTrue(s.videoPreloadPref);
    XCTAssertFalse(s.active);
}

- (void)testPrefsPersistAndReloadWithPrefixedKeys {
    IMPowerSaving *s = [self store];
    s.mode = IMPowerSaveModeAuto; s.threshold = 30; s.followSystem = NO; s.autoDownloadPref = NO; s.videoPreloadPref = NO;
    XCTAssertEqualObjects([self.defaults stringForKey:@"im.powerSaving.mode"], @"auto");
    XCTAssertEqual([self.defaults integerForKey:@"im.powerSaving.threshold"], 30);
    IMPowerSaving *again = [self store];
    XCTAssertEqual(again.mode, IMPowerSaveModeAuto);
    XCTAssertEqual(again.threshold, 30);
    XCTAssertFalse(again.followSystem);
    XCTAssertFalse(again.autoDownloadPref);
    XCTAssertFalse(again.videoPreloadPref);
}

- (void)testThresholdClampedOnWriteAndOnLoad {
    IMPowerSaving *s = [self store];
    s.threshold = 99;
    XCTAssertEqual(s.threshold, 50);
    s.threshold = 1;
    XCTAssertEqual(s.threshold, 5);
    [self.defaults setInteger:200 forKey:@"im.powerSaving.threshold"];
    XCTAssertEqual([self store].threshold, 50);
}

- (void)testBrokenStoredModeFallsBackToOff {
    [self.defaults setObject:@"turbo" forKey:@"im.powerSaving.mode"];
    XCTAssertEqual([self store].mode, IMPowerSaveModeOff);
}

#pragma mark - 生效值 / pausedCount / 入口右值

- (void)testEffectiveValuesFollowUserValueAndActive {
    IMPowerSaving *s = [self store];
    s.mode = IMPowerSaveModeAuto;
    [self feed:s level:62 charging:NO at:0 foreground:YES];
    XCTAssertFalse(s.active);
    XCTAssertTrue(s.animationsEffective); XCTAssertTrue(s.autoDownloadEffective); XCTAssertTrue(s.videoPreloadEffective);
    s.videoPreloadPref = NO;                      // 用户自己关的
    XCTAssertFalse(s.videoPreloadEffective);
    [self feed:s level:12 charging:NO at:1 foreground:YES];
    XCTAssertTrue(s.active);
    XCTAssertEqual(s.reason, IMPowerSaveReasonBattery);
    XCTAssertFalse(s.animationsEffective); XCTAssertFalse(s.autoDownloadEffective); XCTAssertFalse(s.videoPreloadEffective);
    XCTAssertEqual(s.pausedCount, 2);             // 视频预加载本来就关，不算被省电暂停
    [self feed:s level:80 charging:YES at:2 foreground:YES];   // 退出：回到用户原值，没有「恢复」动作
    XCTAssertTrue(s.animationsEffective); XCTAssertTrue(s.autoDownloadEffective); XCTAssertFalse(s.videoPreloadEffective);
    XCTAssertTrue(s.videoPreloadPref == NO && s.autoDownloadPref);
    XCTAssertEqual(s.pausedCount, 0);
}

- (void)testEachEffectiveFlagIsOffWhileActiveWhenUserValueIsOn {
    IMPowerSaving *s = [self store];
    s.mode = IMPowerSaveModeAlways;
    XCTAssertFalse(s.animationsEffective);
    XCTAssertFalse(s.autoDownloadEffective);
    XCTAssertFalse(s.videoPreloadEffective);
    XCTAssertEqual(s.pausedCount, 3);
    s.mode = IMPowerSaveModeOff;
    XCTAssertTrue(s.autoDownloadEffective);
    XCTAssertTrue(s.videoPreloadEffective);
}

- (void)testAnimationsEffectiveUsesAppearancePrefAndDoesNotWriteIt {
    IMPowerSaving *s = [self store];
    s.mode = IMPowerSaveModeAlways;
    XCTAssertTrue(s.active);
    XCTAssertFalse(s.animationsEffective);
    XCTAssertTrue(IMAppearance.shared.animationsEnabled);   // 外观页的值不被省电改写
    IMAppearance.shared.animationsEnabled = NO;
    s.mode = IMPowerSaveModeOff;
    XCTAssertFalse(s.animationsEffective);                  // 用户关了动画，退出省电后仍是关
}

- (void)testChargingUnknownNeverActivatesAuto {
    IMPowerSaving *s = [self store];
    s.mode = IMPowerSaveModeAuto;
    [s applyBatteryLevel:@5 charging:nil systemSaver:nil foreground:YES nowMs:0];
    XCTAssertFalse(s.active);
}

- (void)testFollowSystemActivatesAndRespectsToggle {
    IMPowerSaving *s = [self store];
    [s applyBatteryLevel:@80 charging:@NO systemSaver:@YES foreground:YES nowMs:0];
    XCTAssertTrue(s.active);                        // followSystem 默认开
    XCTAssertEqual(s.reason, IMPowerSaveReasonSystem);
    s.followSystem = NO;
    XCTAssertFalse(s.active);
}

- (void)testEntryRightValueText {
    IMPowerSaving *s = [self store];
    XCTAssertEqualObjects([s entryRightValueText], IMLocalized(@"common.off"));
    s.mode = IMPowerSaveModeAuto;
    XCTAssertEqualObjects([s entryRightValueText], IMLocalizedFormat(@"power_saving.row.below", (long)15));
    [self feed:s level:10 charging:NO at:0 foreground:YES];
    XCTAssertEqualObjects([s entryRightValueText], IMLocalized(@"power_saving.row.on"));
}

- (void)testChangeNotificationOnlyWhenSomethingChanged {
    IMPowerSaving *s = [self store];
    __block int n = 0;
    id obs = [NSNotificationCenter.defaultCenter addObserverForName:IMPowerSavingDidChangeNotification object:s queue:nil
                                                         usingBlock:^(NSNotification *note) { n++; }];
    s.mode = IMPowerSaveModeAuto;
    XCTAssertEqual(n, 1);
    s.mode = IMPowerSaveModeAuto;       // 值没变：不写不通知
    s.threshold = 15;
    XCTAssertEqual(n, 1);
    [NSNotificationCenter.defaultCenter removeObserver:obs];
}

#pragma mark - §5 自动开启提示

- (IMPowerSaving *)storeCountingToastsInto:(NSMutableArray<NSNumber *> *)toasts {
    IMPowerSaving *s = [self store];
    s.autoToastHandler = ^BOOL(NSInteger t) { [toasts addObject:@(t)]; return YES; };
    return s;
}

- (void)testAutoToastOnRisingEdgeOnlyOncePerDischargeCycle {
    NSMutableArray *toasts = [NSMutableArray array];
    IMPowerSaving *s = [self storeCountingToastsInto:toasts];
    s.mode = IMPowerSaveModeAuto;
    [self feed:s level:20 charging:NO at:0 foreground:YES];
    XCTAssertEqual(toasts.count, 0u);
    [self feed:s level:15 charging:NO at:1 foreground:YES];     // level == threshold 触发
    XCTAssertEqualObjects(toasts, (@[@15]));
    [self feed:s level:14 charging:NO at:2 foreground:YES];     // 继续掉：不重弹
    XCTAssertEqual(toasts.count, 1u);
    [self feed:s level:14 charging:YES at:3 foreground:YES];    // 充电：重置
    [self feed:s level:13 charging:NO at:4 foreground:YES];     // 新放电周期：再弹
    XCTAssertEqual(toasts.count, 2u);
}

- (void)testPromptShownPersistedAndClearedOnCharging {
    IMPowerSaving *s = [self store];
    s.autoToastHandler = ^BOOL(NSInteger t) { return YES; };
    s.mode = IMPowerSaveModeAuto;
    [self feed:s level:10 charging:NO at:0 foreground:YES];
    XCTAssertTrue([self.defaults boolForKey:@"im.powerSaving.promptShown"]);
    [self feed:s level:10 charging:YES at:1 foreground:YES];
    XCTAssertFalse([self.defaults boolForKey:@"im.powerSaving.promptShown"]);
}

- (void)testRestartInSameCycleDoesNotToastAgain {
    [self.defaults setObject:@"auto" forKey:@"im.powerSaving.mode"];
    [self.defaults setBool:YES forKey:@"im.powerSaving.promptShown"];
    NSMutableArray *toasts = [NSMutableArray array];
    IMPowerSaving *s = [self storeCountingToastsInto:toasts];
    [s seedBatteryLevel:@10 charging:@NO systemSaver:nil];
    [s beginWithCurrentReading];                                // 进程重启：仍是电量触发 → 沿用已提示
    XCTAssertTrue([self.defaults boolForKey:@"im.powerSaving.promptShown"]);
    [self feed:s level:9 charging:NO at:5 foreground:YES];
    XCTAssertEqual(toasts.count, 0u);
}

- (void)testStartupNotBatteryActiveClearsPersistedPromptShown {
    [self.defaults setObject:@"auto" forKey:@"im.powerSaving.mode"];
    [self.defaults setBool:YES forKey:@"im.powerSaving.promptShown"];
    IMPowerSaving *s = [self store];
    [s seedBatteryLevel:@60 charging:@NO systemSaver:nil];      // 重启时电量回到阈值以上
    [s beginWithCurrentReading];
    XCTAssertFalse([self.defaults boolForKey:@"im.powerSaving.promptShown"]);
}

- (void)testBackgroundTriggerToastsOnReturnWithinTenMinutes {
    NSMutableArray *toasts = [NSMutableArray array];
    IMPowerSaving *s = [self storeCountingToastsInto:toasts];
    s.mode = IMPowerSaveModeAuto;
    [self feed:s level:10 charging:NO at:0 foreground:NO];
    XCTAssertEqual(toasts.count, 0u);
    [s appDidBecomeActiveAtMs:9 * 60000];
    XCTAssertEqual(toasts.count, 1u);
    [s appDidBecomeActiveAtMs:9 * 60000 + 1];                   // 只补一次
    XCTAssertEqual(toasts.count, 1u);
}

/// P2：Toast 没弹出来（没有可见窗口）时不能把「本周期已提示」吃掉，要在下次回前台重试。
- (void)testToastNotPresentedIsRetriedOnNextForegroundAndNotPersistedAsShown {
    __block BOOL canPresent = NO;
    NSMutableArray *shown = [NSMutableArray array];
    IMPowerSaving *s = [self store];
    s.autoToastHandler = ^BOOL(NSInteger t) { if (canPresent) { [shown addObject:@(t)]; } return canPresent; };
    s.mode = IMPowerSaveModeAuto;
    [self feed:s level:10 charging:NO at:0 foreground:YES];            // 上升沿，但没弹成
    XCTAssertEqual(shown.count, 0u);
    XCTAssertFalse([self.defaults boolForKey:@"im.powerSaving.promptShown"]);
    [s appDidBecomeActiveAtMs:kMinute];                                  // 仍没窗口：继续排队
    XCTAssertEqual(shown.count, 0u);
    canPresent = YES;
    [s appDidBecomeActiveAtMs:2 * kMinute];                              // 有窗口了：补弹
    XCTAssertEqual(shown.count, 1u);
    XCTAssertTrue([self.defaults boolForKey:@"im.powerSaving.promptShown"]);
    [s appDidBecomeActiveAtMs:3 * kMinute];                              // 只补一次
    XCTAssertEqual(shown.count, 1u);
}

- (void)testToastRetryExpiresAfterTenMinutesFromTheOriginalTrigger {
    NSMutableArray *shown = [NSMutableArray array];
    __block BOOL canPresent = NO;
    IMPowerSaving *s = [self store];
    s.autoToastHandler = ^BOOL(NSInteger t) { if (canPresent) { [shown addObject:@(t)]; } return canPresent; };
    s.mode = IMPowerSaveModeAuto;
    [self feed:s level:10 charging:NO at:0 foreground:YES];
    [s appDidBecomeActiveAtMs:9 * kMinute];                              // 失败的重试不刷新起点
    canPresent = YES;
    [s appDidBecomeActiveAtMs:10 * kMinute + 1];
    XCTAssertEqual(shown.count, 0u);
}

- (void)testAlwaysOnNeverToasts {
    NSMutableArray *toasts = [NSMutableArray array];
    IMPowerSaving *s = [self storeCountingToastsInto:toasts];
    s.mode = IMPowerSaveModeAlways;
    [self feed:s level:5 charging:NO at:0 foreground:YES];
    XCTAssertEqual(toasts.count, 0u);
}

#pragma mark - DEBUG 电量覆盖（shared，主线程消费 defaults 变更）

- (void)spinRunLoop { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]]; }

- (void)testDebugBatteryOverrideParsesAndMalformedLevelIsUnknownNotZero {
    NSUserDefaults *std = NSUserDefaults.standardUserDefaults;
    [self addTeardownBlock:^{ [std removeObjectForKey:@"im.debug.battery"]; [self spinRunLoop]; }];
    [std setObject:@"42,false" forKey:@"im.debug.battery"];
    [self spinRunLoop];
    XCTAssertEqualObjects(IMPowerSaving.shared.batteryLevel, @42);
    XCTAssertEqualObjects(IMPowerSaving.shared.charging, @NO);
    [std setObject:@"abc,false" forKey:@"im.debug.battery"];
    [self spinRunLoop];
    XCTAssertNil(IMPowerSaving.shared.batteryLevel);                      // 不是 0
    [std setObject:@"-5,true" forKey:@"im.debug.battery"];
    [self spinRunLoop];
    XCTAssertNil(IMPowerSaving.shared.batteryLevel);
}

@end
