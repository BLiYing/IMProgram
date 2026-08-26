//
//  UIView+IMFade.h
//  带「最新意图自查」的淡入淡出。
//
//  为什么不是各页面各写一遍 UIView animateWithDuration + completion 里 hidden=YES：
//  淡出动画未完时又被要求显示（松手后 0.2s 内再次按住录音），**旧动画的完成回调仍会带着
//  visible=NO 触发**，无条件 hidden=YES 就把刚点亮的 UI 又隐掉。这条修法 2026-08-26 在
//  IMVoiceRecordingHUD / IMVoiceLockedBar 各手写了一份逐字相同的 wantsVisible 自查
//  （IMVoicePressOverlay 还是第三种写法），收在这里，第四处不必再踩一次。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIView (IMFade)

/// 淡入/淡出并在**确实淡出后**置 hidden。damping > 0 走弹簧曲线，否则线性。
/// animated=NO 时立即生效（同样走意图自查）。
- (void)im_setVisible:(BOOL)visible
             animated:(BOOL)animated
             duration:(NSTimeInterval)duration
              damping:(CGFloat)damping;

@end

NS_ASSUME_NONNULL_END
