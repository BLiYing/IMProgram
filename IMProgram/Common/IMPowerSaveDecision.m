//  IMPowerSaveDecision.m

#import "IMPowerSaveDecision.h"

const NSInteger IMPowerSaveThresholdMin = 5;
const NSInteger IMPowerSaveThresholdMax = 50;
const NSInteger IMPowerSaveThresholdStep = 5;
const NSInteger IMPowerSaveThresholdDefault = 15;
const int64_t IMPowerSavePromptLateWindowMs = 10 * 60 * 1000;

NSString *IMPowerSaveModeToWire(IMPowerSaveMode mode) {
    switch (mode) {
        case IMPowerSaveModeAuto: return @"auto";
        case IMPowerSaveModeAlways: return @"always";
        case IMPowerSaveModeOff: break;
    }
    return @"off";
}

IMPowerSaveMode IMPowerSaveModeFromWire(NSString *wire) {
    if ([wire isEqualToString:@"auto"]) { return IMPowerSaveModeAuto; }
    if ([wire isEqualToString:@"always"]) { return IMPowerSaveModeAlways; }
    return IMPowerSaveModeOff; // 未知 / 缺失回落关闭
}

NSInteger IMPowerSaveClampThreshold(NSInteger threshold) {
    return MIN(IMPowerSaveThresholdMax, MAX(IMPowerSaveThresholdMin, threshold));
}

@implementation IMPowerSaveContext
@end

IMPowerSaveReason IMPowerSaveReasonFor(IMPowerSaveContext *ctx) {
    if (ctx.mode == IMPowerSaveModeAlways) { return IMPowerSaveReasonAlways; }
    // charging 未知（nil）不触发 auto：宁可不省电，也不在插着电时误开。level == threshold 算触发。
    if (ctx.mode == IMPowerSaveModeAuto && ctx.level != nil && ctx.charging != nil && !ctx.charging.boolValue
        && ctx.level.integerValue <= IMPowerSaveClampThreshold(ctx.threshold)) {
        return IMPowerSaveReasonBattery;
    }
    if (ctx.followSystem && ctx.systemSaver != nil && ctx.systemSaver.boolValue) { return IMPowerSaveReasonSystem; }
    return IMPowerSaveReasonNone;
}

BOOL IMPowerSaveActive(IMPowerSaveContext *ctx) {
    return IMPowerSaveReasonFor(ctx) != IMPowerSaveReasonNone;
}

NSInteger IMPowerSavePausedCount(BOOL active, NSArray<NSNumber *> *userValues) {
    if (!active) { return 0; }
    NSInteger n = 0;
    for (NSNumber *v in userValues) { if (v.boolValue) { n++; } }
    return n;
}

#pragma mark - §5 提示状态机

@implementation IMPowerSavePromptState
- (id)copyWithZone:(NSZone *)zone {
    IMPowerSavePromptState *c = [IMPowerSavePromptState new];
    c.prevActive = _prevActive; c.shown = _shown; c.pendingAtMs = _pendingAtMs;
    return c;
}
@end

@implementation IMPowerSavePromptStep
@end

static IMPowerSavePromptStep *Step(IMPowerSavePromptState *state, BOOL showNow) {
    IMPowerSavePromptStep *s = [IMPowerSavePromptStep new];
    s.state = state; s.showNow = showNow;
    return s;
}

BOOL IMPowerSavePromptStartupShown(BOOL persisted, IMPowerSaveReason reason) {
    return persisted && reason == IMPowerSaveReasonBattery;
}

IMPowerSavePromptStep *IMPowerSavePromptOnStatus(IMPowerSavePromptState *state, BOOL active, IMPowerSaveReason reason,
                                                 NSNumber *charging, BOOL foreground, int64_t nowMs) {
    IMPowerSavePromptState *next = [state copy];
    next.prevActive = active;
    if (charging != nil && charging.boolValue) { next.shown = NO; next.pendingAtMs = nil; } // 开始充电：新周期
    BOOL rising = active && !state.prevActive && reason == IMPowerSaveReasonBattery;
    if (!rising || next.shown) { return Step(next, NO); }
    next.shown = YES;
    if (foreground) { next.pendingAtMs = nil; return Step(next, YES); }
    next.pendingAtMs = @(nowMs); // 后台触发：排队，回前台补弹
    return Step(next, NO);
}

IMPowerSavePromptStep *IMPowerSavePromptOnForeground(IMPowerSavePromptState *state, BOOL stillActive, int64_t nowMs) {
    if (state.pendingAtMs == nil) { return Step(state, NO); }
    int64_t elapsed = nowMs - state.pendingAtMs.longLongValue;
    BOOL show = stillActive && elapsed >= 0 && elapsed <= IMPowerSavePromptLateWindowMs;
    IMPowerSavePromptState *next = [state copy];
    next.pendingAtMs = nil;
    return Step(next, show);
}
