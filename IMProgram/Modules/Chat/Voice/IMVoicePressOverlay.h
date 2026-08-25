//
//  IMVoicePressOverlay.h
//  按住录音的浮层（设计 §5.2，2026-08-26 补齐）：
//    - 58pt 渐变大圆钮：按下瞬间从语音钮位置弹出，全程跟随手指位移；
//    - 振幅呼吸环：大圆钮外圈，实时振幅驱动 scale（"确实在收音"的信任信号）；
//    - 磁吸小锁钮：锚点上方 ~86pt 的 36×52 玻璃锁钮（🔒 + 呼吸上箭头）——
//      指尖进入 70pt 高亮放大 1.1×，34pt 内到位即锁（无需松手）。
//  浮层加在聊天页 self.view（不在输入栏内，避免被裁剪）；仅做展示与命中判定，录音状态机仍在 +Voice.m。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMVoiceLockPhase) {
    IMVoiceLockPhaseNone = 0,  ///< 手指远离锁钮
    IMVoiceLockPhaseNear,      ///< 进入 70pt 高亮圈（磁吸放大提示）
    IMVoiceLockPhaseLocked,    ///< 进入 34pt 磁吸圈 → 上层应立即转锁定态
};

@interface IMVoicePressOverlay : UIView

/// 弹出浮层：anchor=语音钮中心（self.view 坐标系），fingerPoint=当前手指位置。
- (void)presentAtAnchor:(CGPoint)anchor fingerPoint:(CGPoint)finger;

/// 手指移动：大圆钮跟手 + 磁吸判定。返回当前 phase（Locked 时上层转锁定态并 dismissLocked）。
- (IMVoiceLockPhase)updateFingerPoint:(CGPoint)finger;

/// 实时振幅（0..1）：驱动呼吸环 scale。
- (void)updateAmplitude:(float)amplitude;

/// 左滑取消过阈值：大圆钮转红提示（松手即取消）。
- (void)setCancelHint:(BOOL)cancelReady;

/// 锁定成功：锁钮亮起后整体淡出（比普通 dismiss 多一拍确认动画）。
- (void)dismissLocked;

/// 普通收场（松手发送/取消/出错）。
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
