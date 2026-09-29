//  IMAlertPlayer.h
//  应用内提示音 + 触感反馈播放器（NOTIFICATIONS_DESIGN §3.2 iOS 落地注意）：
//  AudioServicesCreateSystemSoundID + AudioServicesPlaySystemSound——天然遵守静音键，不需要自己判、
//  不碰 AVAudioSession（不打断用户正在播的音乐）；UIImpactFeedbackGenerator(.light) 做振动，
//  未开系统触感时系统自己吞掉。
//
//  本类同时是「上次响铃时刻」的唯一权威（喂给 IMAlertDecision 的 lastSoundAtMs）——
//  判据本身是纯函数不持有任何状态，节流时钟必须有唯一归属，否则多处各记一份时钟会漂移。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAlertPlayer : NSObject

@property (class, nonatomic, readonly) IMAlertPlayer *shared;

/// 上次真正响铃的时刻（毫秒，`IMNowMillis()` 同口径）；从未响过为 0。
@property (nonatomic, assign, readonly) int64_t lastSoundAtMs;

/// 按 soundId 播放一次（"none" 或未知 id 已在上游 IMAlertDecision 判过滤掉，这里假定已是合法非 none 的 id，
/// 但仍做防御性 normalize）。播放即刷新 lastSoundAtMs。
- (void)playSoundNamed:(NSString *)soundID;

/// 轻触感振动一次。
- (void)vibrate;

/// 提示音选择页用：点一下试听（**不**计入节流时钟——用户主动点选，不该被「1.5 秒内响过一次」拦掉）。
- (void)previewSoundNamed:(NSString *)soundID;

/// 提示音选择页离场时调用。系统音效播放是 fire-and-forget、无停止 API（且素材规格已限定 ≤1 秒，
/// 见 NOTIFICATIONS_DESIGN §5），这里仅登记「不再需要为试听保留新 SystemSoundID」，无实际截断效果。
- (void)stopPreview;

@end

NS_ASSUME_NONNULL_END
