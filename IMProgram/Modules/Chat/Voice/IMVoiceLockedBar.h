//
//  IMVoiceLockedBar.h
//  锁定态录制行（P1，B 案锁定行 · VOICE_MESSAGE_DESIGN §5.3）：
//    [🗑 删除] | 计时+迷你波形 | [⏸/▶ 暂停·继续] | [➤ 发送]
//  贴输入栏原地——手已可离开屏幕（免提录制），中断（来电/切后台）也自动进入本行的暂停态。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMVoiceLockedBar : UIView

@property (nonatomic, copy, nullable) void (^onDelete)(void);
/// 右侧键点击（三态切换语义）：
///   - 录制中（!previewMode）→ toPause=YES：上层 recorder.pause + setPreviewMode:YES amplitudes:...
///   - 试听态（previewMode）→ toPause=NO：上层停试听 + recorder.resume + setPreviewMode:NO
@property (nonatomic, copy, nullable) void (^onPauseResume)(BOOL toPause);
/// 点中间胶囊（仅 previewMode 下有效）：上层调 IMVoicePlayer 播/暂 preview URL。
@property (nonatomic, copy, nullable) void (^onPreviewToggle)(void);
@property (nonatomic, copy, nullable) void (^onSend)(void);

/// 每 100ms 由 recorder 委托驱动（录制态波形跑马灯 + 计时）。
- (void)updateAmplitude:(float)amplitude elapsedMillis:(int64_t)elapsedMillis;

/// 切换暂停/继续按钮的图标（外部按 previewMode 状态调用）。
- (void)setPausedIcon:(BOOL)paused;

/// §14 试听态切换：YES→中间胶囊变迷你播放器（IMWaveformView 显完整已录波形，点即播）；
/// NO→恢复录制态（跑马灯波形 + 红点）。amplitudes 是 IMVoiceRecorder.currentAmplitudes（0~1 归一）。
- (void)setPreviewMode:(BOOL)previewMode amplitudes:(nullable NSArray<NSNumber *> *)amplitudes;

/// 试听中：上层每 tick 传当前进度（0..1）+ 是否在播——驱动波形扫过 + 中间 ▶/❚❚ 图标。
- (void)applyPreviewPlaying:(BOOL)playing progress:(double)progress totalMillis:(int64_t)totalMillis;

/// 显示/隐藏（YES=弹性入场，NO=淡出）。
- (void)setVisible:(BOOL)visible animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
