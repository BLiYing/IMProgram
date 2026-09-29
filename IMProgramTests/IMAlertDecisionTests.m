//  IMAlertDecisionTests.m
//  IMAlertDecide 纯函数单测：读三端共用向量 IMServer/docs/conformance/alert_decision.json（30 条，
//  改规则先改向量）。按本文件相对路径找，也可用环境变量 IM_ALERT_DECISION_VECTORS 指定。
//  找不到时**失败**而不是跳过——静默跳过等于没测（同 IMCallRecordTests 先例）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMAlertDecision.h"

@interface IMAlertDecisionTests : XCTestCase
@end

@implementation IMAlertDecisionTests

- (NSArray<NSDictionary *> *)vectors {
    NSString *path = NSProcessInfo.processInfo.environment[@"IM_ALERT_DECISION_VECTORS"];
    if (path.length == 0) {
        NSString *repo = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]; // …/IMProgram
        path = [[repo stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"IMServer/docs/conformance/alert_decision.json"];
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"找不到共用向量 %@（IM_ALERT_DECISION_VECTORS 可指定）", path);
    NSDictionary *root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSArray *cases = root[@"cases"];
    XCTAssertGreaterThanOrEqual(cases.count, 30u);
    return cases;
}

static IMAlertTypeSettings *TypeSettingsFromDict(NSDictionary *d) {
    IMAlertTypeSettings *s = [IMAlertTypeSettings new];
    s.enabled = [d[@"enabled"] boolValue];
    s.preview = [d[@"preview"] boolValue];
    s.sound = d[@"sound"] ?: @"default";
    return s;
}

static IMAlertContext *ContextFromDict(NSDictionary *caseDict) {
    NSDictionary *c = caseDict[@"ctx"]; // 向量每条是 {name, ctx, expect}——上下文字段嵌在 "ctx" 下一层
    IMAlertContext *ctx = [IMAlertContext new];
    ctx.platform = c[@"platform"];
    ctx.isLive = [c[@"isLive"] boolValue];
    ctx.isSelf = [c[@"isSelf"] boolValue];
    ctx.isSystem = [c[@"isSystem"] boolValue];
    ctx.isRecalled = [c[@"isRecalled"] boolValue];
    ctx.isCallRecord = [c[@"isCallRecord"] boolValue];
    ctx.missedCallForMe = [c[@"missedCallForMe"] boolValue];
    ctx.convType = c[@"convType"];
    ctx.muted = [c[@"muted"] boolValue];
    ctx.mentionsMe = [c[@"mentionsMe"] boolValue];
    ctx.appActive = [c[@"appActive"] boolValue];
    ctx.windowFocused = [c[@"windowFocused"] boolValue];
    ctx.viewingConv = [c[@"viewingConv"] boolValue];
    ctx.inCall = [c[@"inCall"] boolValue];
    ctx.nowMs = [c[@"nowMs"] longLongValue];
    ctx.lastSoundAtMs = [c[@"lastSoundAtMs"] longLongValue];

    NSDictionary *settings = c[@"settings"];
    IMAlertSettingsSnapshot *snapshot = [IMAlertSettingsSnapshot new];
    snapshot.privateType = TypeSettingsFromDict(settings[@"private"]);
    snapshot.groupType = TypeSettingsFromDict(settings[@"group"]);

    IMAlertInAppSettings *inApp = [IMAlertInAppSettings new];
    inApp.sound = [settings[@"inApp"][@"sound"] boolValue];
    inApp.vibrate = [settings[@"inApp"][@"vibrate"] boolValue];
    inApp.preview = [settings[@"inApp"][@"preview"] boolValue];
    snapshot.inApp = inApp;

    IMAlertBadgeSettings *badge = [IMAlertBadgeSettings new];
    badge.includeMuted = [settings[@"badge"][@"includeMuted"] boolValue];
    snapshot.badge = badge;

    IMAlertDesktopSettings *desktop = [IMAlertDesktopSettings new];
    desktop.enabled = [settings[@"desktop"][@"enabled"] boolValue];
    desktop.sound = [settings[@"desktop"][@"sound"] boolValue];
    desktop.volume = [settings[@"desktop"][@"volume"] integerValue];
    snapshot.desktop = desktop;

    ctx.settings = snapshot;
    return ctx;
}

- (void)testConformanceVectors {
    for (NSDictionary *c in [self vectors]) {
        IMAlertContext *ctx = ContextFromDict(c);
        IMAlertResult *result = IMAlertDecide(ctx);
        NSDictionary *e = c[@"expect"];
        NSString *name = c[@"name"];
        XCTAssertEqual(result.sound, [e[@"sound"] boolValue], @"%@ (sound)", name);
        XCTAssertEqual(result.vibrate, [e[@"vibrate"] boolValue], @"%@ (vibrate)", name);
        XCTAssertEqual(result.banner, [e[@"banner"] boolValue], @"%@ (banner)", name);
        XCTAssertEqual(result.osNotify, [e[@"osNotify"] boolValue], @"%@ (osNotify)", name);
        id expectSoundId = e[@"soundId"];
        if (expectSoundId == NSNull.null || expectSoundId == nil) {
            XCTAssertNil(result.soundId, @"%@ (soundId should be nil)", name);
        } else {
            XCTAssertEqualObjects(result.soundId, expectSoundId, @"%@ (soundId)", name);
        }
    }
}

#pragma mark - 补充（向量之外的边界，覆盖 IMNotificationSoundIDNormalize 与函数纯度）

- (void)testUnknownSoundIdFallsBackToDefault {
    IMAlertContext *ctx = [self baseMobileContext];
    ctx.settings.privateType.sound = @"totally-unknown";
    IMAlertResult *result = IMAlertDecide(ctx);
    XCTAssertTrue(result.sound);
    XCTAssertEqualObjects(result.soundId, @"default");
}

- (void)testPureFunctionDoesNotMutateInput {
    IMAlertContext *ctx = [self baseMobileContext];
    int64_t originalLastSound = ctx.lastSoundAtMs;
    IMAlertDecide(ctx);
    XCTAssertEqual(ctx.lastSoundAtMs, originalLastSound); // 纯函数：不改写入参
}

- (IMAlertContext *)baseMobileContext {
    IMAlertContext *ctx = [IMAlertContext new];
    ctx.platform = IMAlertPlatformMobile;
    ctx.isLive = YES;
    ctx.convType = IMAlertConvTypePrivate;
    ctx.appActive = YES;
    ctx.nowMs = 100000;
    ctx.lastSoundAtMs = 0;
    IMAlertSettingsSnapshot *s = [IMAlertSettingsSnapshot new];
    IMAlertTypeSettings *priv = [IMAlertTypeSettings new];
    priv.enabled = YES; priv.preview = YES; priv.sound = @"default";
    s.privateType = priv;
    IMAlertTypeSettings *group = [IMAlertTypeSettings new];
    group.enabled = YES; group.preview = YES; group.sound = @"default";
    s.groupType = group;
    IMAlertInAppSettings *inApp = [IMAlertInAppSettings new];
    inApp.sound = YES; inApp.vibrate = YES; inApp.preview = YES;
    s.inApp = inApp;
    s.badge = [IMAlertBadgeSettings new];
    IMAlertDesktopSettings *desktop = [IMAlertDesktopSettings new];
    desktop.enabled = YES; desktop.sound = YES; desktop.volume = 7;
    s.desktop = desktop;
    ctx.settings = s;
    return ctx;
}

@end
