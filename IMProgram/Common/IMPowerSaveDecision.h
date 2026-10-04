//  IMPowerSaveDecision.h
//  省电模式判定（纯函数，可测）：powerSaveActive + 阈值夹紧 + 「N 项已暂停」计数 + §5 自动开启提示状态机。
//  四端同名判据，共用向量 IMServer/docs/conformance/power_save.json（改规则先改向量）。
//  设计：IMServer/docs/design/POWER_SAVING_DESIGN.md §3 / §5。对端 im-android data/PowerSaveDecision.kt +
//  PowerSavePrompt.kt、im-web src/powerSave.ts。本文件不读任何全局态（电量、偏好、时钟都由调用方传入）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 开启方式（wire 值与向量、存储一致：off / auto / always）。
typedef NS_ENUM(NSInteger, IMPowerSaveMode) {
    IMPowerSaveModeOff = 0,
    IMPowerSaveModeAuto,
    IMPowerSaveModeAlways,
};

/// 生效原因（状态行副标题用）。优先级：始终开启 > 电量 > 跟随系统。None = 未生效。
typedef NS_ENUM(NSInteger, IMPowerSaveReason) {
    IMPowerSaveReasonNone = 0,
    IMPowerSaveReasonAlways,
    IMPowerSaveReasonBattery,
    IMPowerSaveReasonSystem,
};

FOUNDATION_EXPORT const NSInteger IMPowerSaveThresholdMin;     // 5
FOUNDATION_EXPORT const NSInteger IMPowerSaveThresholdMax;     // 50
FOUNDATION_EXPORT const NSInteger IMPowerSaveThresholdStep;    // 5
FOUNDATION_EXPORT const NSInteger IMPowerSaveThresholdDefault; // 15
/// §5：后台触发的提示，回前台多久内补弹（10 分钟）。
FOUNDATION_EXPORT const int64_t IMPowerSavePromptLateWindowMs;

/// wire 值互转；未知 / nil 回落 Off。
FOUNDATION_EXPORT NSString *IMPowerSaveModeToWire(IMPowerSaveMode mode);
FOUNDATION_EXPORT IMPowerSaveMode IMPowerSaveModeFromWire(NSString *_Nullable wire);

/// 越界夹到 5..50（不对齐步长：步长由滑块保证）。
FOUNDATION_EXPORT NSInteger IMPowerSaveClampThreshold(NSInteger threshold);

/// `powerSaveActive` 的输入（对应向量 JSON 的 `ctx`）。level 为 0..100，nil = 读不到；charging / systemSaver nil = 未知。
@interface IMPowerSaveContext : NSObject
@property (nonatomic, assign) IMPowerSaveMode mode;
@property (nonatomic, assign) NSInteger threshold;
@property (nonatomic, strong, nullable) NSNumber *level;
@property (nonatomic, strong, nullable) NSNumber *charging;    // BOOL
@property (nonatomic, assign) BOOL followSystem;
@property (nonatomic, strong, nullable) NSNumber *systemSaver; // BOOL
@end

/// 生效原因；None = 未生效。`charging == nil` 不触发 auto；`level == threshold` 算触发。
FOUNDATION_EXPORT IMPowerSaveReason IMPowerSaveReasonFor(IMPowerSaveContext *ctx);
/// 向量对应的判据：reason != None。
FOUNDATION_EXPORT BOOL IMPowerSaveActive(IMPowerSaveContext *ctx);

/// 状态行「N 项已暂停」：生效时**用户值为开**的耗电项数（真正被省电暂停的），不是总数；未生效为 0。
FOUNDATION_EXPORT NSInteger IMPowerSavePausedCount(BOOL active, NSArray<NSNumber *> *userValues);

#pragma mark - §5 自动开启提示状态机

/// 提示状态（值语义：状态机函数返回新实例，不改入参）。
@interface IMPowerSavePromptState : NSObject <NSCopying>
@property (nonatomic, assign) BOOL prevActive;
@property (nonatomic, assign) BOOL shown;                         // 本放电周期已提示（或已排队补弹）
@property (nonatomic, strong, nullable) NSNumber *pendingAtMs;    // 后台触发的时刻（int64）；回前台据此判补弹
@end

@interface IMPowerSavePromptStep : NSObject
@property (nonatomic, strong) IMPowerSavePromptState *state;
@property (nonatomic, assign) BOOL showNow;
@end

/// 进程重启后「本周期已提示」是否仍有效：持久化为真，且此刻仍是电量触发的生效态才算同一放电周期。
FOUNDATION_EXPORT BOOL IMPowerSavePromptStartupShown(BOOL persisted, IMPowerSaveReason reason);
/// 状态（电量 / 偏好 / 充电）变化时调。仅 active 上升沿 + 原因为电量才提示；充电即重置；后台触发的排队。
FOUNDATION_EXPORT IMPowerSavePromptStep *IMPowerSavePromptOnStatus(IMPowerSavePromptState *state, BOOL active,
                                                                   IMPowerSaveReason reason, NSNumber *_Nullable charging,
                                                                   BOOL foreground, int64_t nowMs);
/// 回前台时调：后台排队的，10 分钟内且仍生效则补弹一次。
FOUNDATION_EXPORT IMPowerSavePromptStep *IMPowerSavePromptOnForeground(IMPowerSavePromptState *state,
                                                                       BOOL stillActive, int64_t nowMs);

NS_ASSUME_NONNULL_END
