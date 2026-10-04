//  IMPowerSaving.m

#import "IMPowerSaving.h"

#import <UIKit/UIKit.h>
#import "IMAppearance.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "UIViewController+IMToast.h"

NSNotificationName const IMPowerSavingDidChangeNotification = @"IMPowerSavingDidChangeNotification";

static NSString * const kModeKey = @"im.powerSaving.mode";
static NSString * const kThresholdKey = @"im.powerSaving.threshold";
static NSString * const kFollowKey = @"im.powerSaving.followSystem";
static NSString * const kAutoDownloadKey = @"im.powerSaving.autoDownload";
static NSString * const kVideoPreloadKey = @"im.powerSaving.videoPreload";
static NSString * const kPromptShownKey = @"im.powerSaving.promptShown";
#if DEBUG
/// 模拟器读不到真实电量：`im.debug.battery = "10,false"`（电量,是否充电；空 / 缺省 = 未知）覆盖读数。对端 Web 同名键。
static NSString * const kDebugBatteryKey = @"im.debug.battery";
#endif

static int64_t NowMs(void) { return (int64_t)([NSDate date].timeIntervalSince1970 * 1000); }

@implementation IMPowerSaving {
    NSUserDefaults *_defaults;
    BOOL _realSource;           // 接系统电量 / 低电量模式通知（shared 才接）
    BOOL _started;
    NSNumber *_systemSaver;
    IMPowerSavePromptState *_prompt;
    IMPowerSaveContext *_ctx;
#if DEBUG
    NSString *_lastDebugOverride;
#endif
}

+ (IMPowerSaving *)shared {
    static IMPowerSaving *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [[IMPowerSaving alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        inst->_realSource = YES;
    });
    return inst;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) {
        _defaults = defaults;
        _prompt = [IMPowerSavePromptState new];
        _ctx = [IMPowerSaveContext new];
        [self loadPrefs];
        _autoToastHandler = ^BOOL(NSInteger threshold) {
            // 没有前台激活的 key window / 根控制器（冷启动早期）时 im_showGlobalToast 会静默空操作，所以先判，回报是否真弹了。
            UIViewController *top = [UIViewController im_topVisibleViewController];
            if (top == nil || top.viewIfLoaded.window == nil) { return NO; }
            [top im_showToast:IMLocalizedFormat(@"power_saving.auto_on_toast", (long)threshold)];
            return YES;
        };
    }
    return self;
}

- (void)loadPrefs {
    _mode = IMPowerSaveModeFromWire([_defaults stringForKey:kModeKey]);
    _threshold = IMPowerSaveClampThreshold([_defaults objectForKey:kThresholdKey] ? [_defaults integerForKey:kThresholdKey] : IMPowerSaveThresholdDefault);
    _followSystem = [_defaults objectForKey:kFollowKey] ? [_defaults boolForKey:kFollowKey] : YES;
    _autoDownloadPref = [_defaults objectForKey:kAutoDownloadKey] ? [_defaults boolForKey:kAutoDownloadKey] : YES;
    _videoPreloadPref = [_defaults objectForKey:kVideoPreloadKey] ? [_defaults boolForKey:kVideoPreloadKey] : YES;
}

#pragma mark - 启动与系统来源

- (void)start {
    if (_started) { return; }
    _started = YES;
    if (_realSource) {
        UIDevice.currentDevice.batteryMonitoringEnabled = YES;
        // 系统通知（NSProcessInfoPowerState / NSUserDefaults 等）可能在非主线程送达：一律先切主线程，
        // 保证 store 的全部状态（_active/_prompt/_ctx）与 applicationState 读取、Toast 都只在主线程。
        [self observeOnMain:UIDeviceBatteryLevelDidChangeNotification action:^(IMPowerSaving *s) { [s systemReadingChanged]; }];
        [self observeOnMain:UIDeviceBatteryStateDidChangeNotification action:^(IMPowerSaving *s) { [s systemReadingChanged]; }];
        [self observeOnMain:NSProcessInfoPowerStateDidChangeNotification action:^(IMPowerSaving *s) { [s systemReadingChanged]; }];
        [self observeOnMain:UIApplicationDidBecomeActiveNotification action:^(IMPowerSaving *s) { [s didBecomeActive]; }];
        // 冷启动时 didBecomeActive 可能早于场景进入前台激活态（Toast 弹不出）：场景激活时再补一次。
        [self observeOnMain:UISceneDidActivateNotification action:^(IMPowerSaving *s) { [s appDidBecomeActiveAtMs:NowMs()]; }];
        [self observeOnMain:IMAppearanceDidChangeNotification action:^(IMPowerSaving *s) { [s appearanceChanged]; }]; // 动画偏好变 → pausedCount / 生效值
#if DEBUG
        [self observeOnMain:NSUserDefaultsDidChangeNotification action:^(IMPowerSaving *s) { [s debugOverrideMayHaveChanged]; }];
#endif
        [self readSystemInto:NO];
    }
    [self beginWithCurrentReading];
}

- (void)observeOnMain:(NSNotificationName)name action:(void (^)(IMPowerSaving *s))action {
    __weak typeof(self) ws = self;
    [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        __strong typeof(ws) strongSelf = ws;
        if (strongSelf) { action(strongSelf); }
    }];
}

/// 首次读数：先定「本周期已提示」是否沿用（进程重启不重复弹，但已充电 / 不再触发的算新周期），再正常重算。
- (void)beginWithCurrentReading {
    IMPowerSaveReason first = [self currentReason];
    _prompt.shown = IMPowerSavePromptStartupShown([_defaults boolForKey:kPromptShownKey], first);
    [self persistShown:_prompt.shown];
    [self recomputeForeground:[self isForeground] nowMs:NowMs() notify:YES];
}

- (void)seedBatteryLevel:(NSNumber *)level charging:(NSNumber *)charging systemSaver:(NSNumber *)systemSaver {
    _batteryLevel = level; _charging = charging; _systemSaver = systemSaver;
}

- (void)appearanceChanged {
    [self recomputeForeground:[self isForeground] nowMs:NowMs() notify:YES];
}

- (BOOL)isForeground {
    if (!_realSource) { return YES; }
    return UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

- (void)systemReadingChanged {
    [self readSystemInto:YES];
}

#if DEBUG
/// defaults 里任何键变都会来；只在 im.debug.battery 本身变了才重读（`defaults write … im.debug.battery "10,false"` 即时生效）。
- (void)debugOverrideMayHaveChanged {
    NSString *now = [_defaults stringForKey:kDebugBatteryKey] ?: @"";
    if ([now isEqualToString:_lastDebugOverride ?: @""]) { return; }
    _lastDebugOverride = now;
    [self readSystemInto:YES];
}
#endif

- (void)didBecomeActive {
    [self readSystemInto:YES];
    [self appDidBecomeActiveAtMs:NowMs()];
}

/// 读系统（或 DEBUG 覆盖）电量并重算。
- (void)readSystemInto:(BOOL)recompute {
    NSNumber *level = nil, *charging = nil;
    UIDevice *dev = UIDevice.currentDevice;
    if (dev.batteryLevel >= 0) { level = @((NSInteger)lroundf(dev.batteryLevel * 100)); }
    switch (dev.batteryState) {
        case UIDeviceBatteryStateUnplugged: charging = @NO; break;
        case UIDeviceBatteryStateCharging:
        case UIDeviceBatteryStateFull: charging = @YES; break;
        default: break; // Unknown（模拟器）：未知
    }
#if DEBUG
    NSString *override = [_defaults stringForKey:kDebugBatteryKey];
    if (override.length > 0) {
        NSArray<NSString *> *parts = [override componentsSeparatedByString:@","];
        NSString *lv = [parts.firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *ch = parts.count > 1 ? [parts[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] : @"";
        BOOL digits = lv.length > 0 && [lv rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
        level = digits ? @(MIN(100, lv.integerValue)) : nil; // 解析失败（"abc"）按读不到，不是 0
        charging = [ch isEqualToString:@"true"] ? @YES : ([ch isEqualToString:@"false"] ? @NO : nil);
    }
#endif
#if DEBUG
    _lastDebugOverride = override ?: @"";
#endif
    _systemSaver = @(NSProcessInfo.processInfo.lowPowerModeEnabled);
    _batteryLevel = level; _charging = charging;
    if (recompute) { [self recomputeForeground:[self isForeground] nowMs:NowMs() notify:YES]; }
}

- (void)applyBatteryLevel:(NSNumber *)level charging:(NSNumber *)charging systemSaver:(NSNumber *)systemSaver
               foreground:(BOOL)foreground nowMs:(int64_t)nowMs {
    _batteryLevel = level; _charging = charging; _systemSaver = systemSaver;
    [self recomputeForeground:foreground nowMs:nowMs notify:YES];
}

#pragma mark - 重算

- (IMPowerSaveReason)currentReason {
    _ctx.mode = _mode; _ctx.threshold = _threshold; _ctx.level = _batteryLevel; _ctx.charging = _charging;
    _ctx.followSystem = _followSystem; _ctx.systemSaver = _systemSaver;
    return IMPowerSaveReasonFor(_ctx);
}

- (void)recomputeForeground:(BOOL)foreground nowMs:(int64_t)nowMs notify:(BOOL)notify {
    IMPowerSaveReason reason = [self currentReason];
    BOOL active = reason != IMPowerSaveReasonNone;
    BOOL changed = (active != _active) || (reason != _reason);
    _active = active; _reason = reason;
    _pausedCount = IMPowerSavePausedCount(active, @[@(IMAppearance.shared.animationsEnabled), @(_autoDownloadPref), @(_videoPreloadPref)]);

    IMPowerSavePromptStep *step = IMPowerSavePromptOnStatus(_prompt, active, reason, _charging, foreground, nowMs);
    _prompt = step.state;
    [self persistShown:_prompt.shown];
    if (changed) {
        IMLogWithTag(IMLogTagApp, @"power_saving_status active=%d reason=%ld level=%@ charging=%@ mode=%@",
                     active, (long)reason, _batteryLevel ?: @"-", _charging ?: @"-", IMPowerSaveModeToWire(_mode));
    }
    if (notify) { [self postChange]; }
    if (step.showNow) { [self presentAutoToastRetryFromMs:nowMs]; }
}

- (void)appDidBecomeActiveAtMs:(int64_t)nowMs {
    NSNumber *pending = _prompt.pendingAtMs;
    IMPowerSavePromptStep *step = IMPowerSavePromptOnForeground(_prompt, _active, nowMs);
    _prompt = step.state;
    if (step.showNow) { [self presentAutoToastRetryFromMs:pending ? pending.longLongValue : nowMs]; }
}

/// 弹自动开启提示。状态机已把本周期记为「已提示」，但 Toast 可能因没有可见窗口而没弹出（冷启动早期）：
/// 此时撤销 shown（含落盘）并重新排队 pendingAtMs，等下次回前台 / 场景激活再补（仍受 10 分钟窗口约束）。
- (void)presentAutoToastRetryFromMs:(int64_t)ms {
    _prompt = [_prompt copy];
    if (_autoToastHandler && _autoToastHandler(_threshold)) {
        _prompt.shown = YES; // 真弹出了（含重试成功）：本周期已提示，落盘
        [self persistShown:YES];
        return;
    }
    _prompt.shown = NO;
    _prompt.pendingAtMs = @(ms);
    [self persistShown:NO];
}

/// 「本周期已提示」落盘（不走偏好 setter：它们会再触发重算）。
- (void)persistShown:(BOOL)shown {
    if ([_defaults boolForKey:kPromptShownKey] != shown) { [_defaults setBool:shown forKey:kPromptShownKey]; }
}

- (void)postChange {
    void (^post)(void) = ^{ [NSNotificationCenter.defaultCenter postNotificationName:IMPowerSavingDidChangeNotification object:self]; };
    if (NSThread.isMainThread) { post(); } else { dispatch_async(dispatch_get_main_queue(), post); }
}

#pragma mark - 偏好 setter（先夹紧再比较，值没变就不写盘 / 不通知）

- (void)setMode:(IMPowerSaveMode)mode {
    if (mode == _mode) { return; }
    _mode = mode;
    [_defaults setObject:IMPowerSaveModeToWire(mode) forKey:kModeKey];
    [self recomputeForeground:[self isForeground] nowMs:NowMs() notify:YES];
}

- (void)setThreshold:(NSInteger)threshold {
    threshold = IMPowerSaveClampThreshold(threshold);
    if (threshold == _threshold) { return; }
    _threshold = threshold;
    [_defaults setInteger:threshold forKey:kThresholdKey];
    [self recomputeForeground:[self isForeground] nowMs:NowMs() notify:YES];
}

- (void)setFollowSystem:(BOOL)followSystem {
    if (followSystem == _followSystem) { return; }
    _followSystem = followSystem;
    [_defaults setBool:followSystem forKey:kFollowKey];
    [self recomputeForeground:[self isForeground] nowMs:NowMs() notify:YES];
}

- (void)setAutoDownloadPref:(BOOL)v {
    if (v == _autoDownloadPref) { return; }
    _autoDownloadPref = v;
    [_defaults setBool:v forKey:kAutoDownloadKey];
    [self recomputeForeground:[self isForeground] nowMs:NowMs() notify:YES];
}

- (void)setVideoPreloadPref:(BOOL)v {
    if (v == _videoPreloadPref) { return; }
    _videoPreloadPref = v;
    [_defaults setBool:v forKey:kVideoPreloadKey];
    [self recomputeForeground:[self isForeground] nowMs:NowMs() notify:YES];
}

#pragma mark - 生效值

- (BOOL)animationsEffective { return IMAppearance.shared.animationsEnabled && !_active; }
- (BOOL)autoDownloadEffective { return _autoDownloadPref && !_active; }
- (BOOL)videoPreloadEffective { return _videoPreloadPref && !_active; }

- (NSString *)entryRightValueText {
    if (_active) { return IMLocalized(@"power_saving.row.on"); }
    if (_mode == IMPowerSaveModeAuto) { return IMLocalizedFormat(@"power_saving.row.below", (long)_threshold); }
    return IMLocalized(@"common.off");
}

@end
