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
@property (nonatomic, copy, nullable) void (^onPauseResume)(BOOL toPause);
@property (nonatomic, copy, nullable) void (^onSend)(void);

/// 每 100ms 由 recorder 委托驱动。amplitude 归一 0..1；elapsed 毫秒。
- (void)updateAmplitude:(float)amplitude elapsedMillis:(int64_t)elapsedMillis;

/// 切换暂停/继续按钮的图标（外部知道状态后调用）。
- (void)setPausedIcon:(BOOL)paused;

/// 显示/隐藏（YES=弹性入场，NO=淡出）。
- (void)setVisible:(BOOL)visible animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
