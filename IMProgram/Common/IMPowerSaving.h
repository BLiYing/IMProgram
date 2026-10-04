//  IMPowerSaving.h
//  省电模式的**唯一持有者**（POWER_SAVING_DESIGN；对端 im-android PowerSavingStore.kt）：本机偏好 + 电量 / 系统低电量模式读数
//  → 耗电项**生效值**（`effective = userValue && !active`，退出省电自然回到用户原值，没有「恢复」这一步）。
//  偏好存 NSUserDefaults（前缀 im.powerSaving.），每设备本地、退出登录保留、不上传。
//  「界面动画」与外观页「动画」是同一个值（IMAppearance.animationsEnabled），这里只给生效值。
//  电量来自 UIDevice.batteryLevel/batteryState，低电量模式来自 NSProcessInfo.lowPowerModeEnabled，都不需要权限。

#import <Foundation/Foundation.h>
#import "IMPowerSaveDecision.h"

NS_ASSUME_NONNULL_BEGIN

/// 偏好或判定结果变化（含电量变化导致 active / 读数变）。主线程发出。
extern NSNotificationName const IMPowerSavingDidChangeNotification;

@interface IMPowerSaving : NSObject

@property (class, nonatomic, readonly) IMPowerSaving *shared;

/// 测试用：注入独立的 defaults（不接系统电量通知，读数由 -applyBatteryLevel:... 喂）。
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;

/// App 启动时调一次（与登录无关）：开电量监控、读初值、挂通知。幂等。
- (void)start;

#pragma mark 用户偏好（持久化）
@property (nonatomic, assign) IMPowerSaveMode mode;
@property (nonatomic, assign) NSInteger threshold;      // 读写都夹到 5..50
@property (nonatomic, assign) BOOL followSystem;        // 默认开
@property (nonatomic, assign) BOOL autoDownloadPref;    // 默认开
@property (nonatomic, assign) BOOL videoPreloadPref;    // 默认开

#pragma mark 读数与判定结果
@property (nonatomic, readonly, nullable) NSNumber *batteryLevel;   // 0..100；nil = 读不到
@property (nonatomic, readonly, nullable) NSNumber *charging;       // BOOL；nil = 未知
@property (nonatomic, readonly) BOOL active;
@property (nonatomic, readonly) IMPowerSaveReason reason;
@property (nonatomic, readonly) NSInteger pausedCount;

#pragma mark 生效值（业务调用点只读这三个）
@property (nonatomic, readonly) BOOL animationsEffective;     // IMAppearance 动画偏好 && !active
@property (nonatomic, readonly) BOOL autoDownloadEffective;
@property (nonatomic, readonly) BOOL videoPreloadEffective;

/// 「我」页入口行右值：已开启 / 低于 N% / 关闭。
- (NSString *)entryRightValueText;

/// 启动前种读数（不重算、不通知）+ 按当前读数完成启动（决定「本周期已提示」是否沿用）。`-start` 内部就是这两步；
/// 单测直接用它们模拟「进程重启」。
- (void)seedBatteryLevel:(nullable NSNumber *)level charging:(nullable NSNumber *)charging systemSaver:(nullable NSNumber *)systemSaver;
- (void)beginWithCurrentReading;

/// 喂一次读数并重算（真机由系统通知调用；测试 / DEBUG 覆盖直接调）。nil = 未知。
- (void)applyBatteryLevel:(nullable NSNumber *)level charging:(nullable NSNumber *)charging
              systemSaver:(nullable NSNumber *)systemSaver foreground:(BOOL)foreground nowMs:(int64_t)nowMs;
/// 回前台：补弹后台排队的提示。
- (void)appDidBecomeActiveAtMs:(int64_t)nowMs;

/// 自动开启提示的展示器（默认：在可见的顶层控制器上弹 Toast）。**返回是否真的展示了**：返回 NO（例如冷启动早期
/// 还没有前台窗口）时本周期的「已提示」会被撤销并排队，下次回前台 / 场景激活时重试（10 分钟内）。测试替换它来观察。
@property (nonatomic, copy, nullable) BOOL (^autoToastHandler)(NSInteger threshold);

@end

NS_ASSUME_NONNULL_END
