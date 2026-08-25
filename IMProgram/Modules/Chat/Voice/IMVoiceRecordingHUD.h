//
//  IMVoiceRecordingHUD.h
//  录制中的行内 HUD（voice P0）：贴在输入栏原位、遮盖整条输入栏，显示：
//    [ ● 0:23 · ‹ 向左滑动取消 ]  + 顶部悬浮 "🔒 上滑锁定" 提示条
//  按住状态下的一切都收进这一行 + 拇指正上方（Telegram B 案，见 VOICE_MESSAGE_DESIGN §5.2）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMVoiceRecordingHUD : UIView

/// 显示/隐藏（YES=蒙层入场，NO=淡出）。
- (void)setVisible:(BOOL)visible animated:(BOOL)animated;

/// 更新计时和振幅（recorder 每 100ms 触发）。amplitude 归一化 0..1，决定"红点脉冲"节奏。
- (void)updateAmplitude:(float)amplitude elapsedMillis:(int64_t)elapsedMillis;

/// 是否命中取消阈值（滑动距离 ≥ 行宽 40%）。命中态整条转红 + 文案变"松开 取消"。
- (void)setCancelReady:(BOOL)cancelReady;

/// 提示文字位移量（0=居中；负值=跟随手指左移；用于渐隐进度条式提示，见 §5.2 交互）。
- (void)setSlideOffset:(CGFloat)offsetX;

@end

NS_ASSUME_NONNULL_END
