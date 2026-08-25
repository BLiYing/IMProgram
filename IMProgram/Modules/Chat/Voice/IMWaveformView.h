//
//  IMWaveformView.h
//  波形可视化（播放气泡 + 录制 HUD 共用）。
//
//  数据源：base64(≤120 bytes, 每字节 0~100 振幅百分比) → 收端按可绘制宽度下采样。
//  bar 宽 3pt / 间距 2.5pt / 高度 5~26pt 映射（voice 气泡 tokens，见 VOICE_MESSAGE_DESIGN §6.1）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMWaveformView : UIView

/// 振幅数据（0~1 归一化）。改动会触发重画。
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *amplitudes;
/// 播放进度 0..1；决定填充色的 mask 宽度。
@property (nonatomic, assign) CGFloat progress;
/// 未填充色（灰）。
@property (nonatomic, strong) UIColor *inactiveColor;
/// 已填充色（进度扫过部分）。
@property (nonatomic, strong) UIColor *activeColor;
/// bar 宽 / 间距 / 圆角。默认 3/2.5/1.5。
@property (nonatomic, assign) CGFloat barWidth;
@property (nonatomic, assign) CGFloat barSpacing;
@property (nonatomic, assign) CGFloat barCornerRadius;

/// 便捷：解 base64 → amplitudes。非法/空 → nil（调用方决定回退等高条纹）。
+ (nullable NSArray<NSNumber *> *)amplitudesFromBase64:(nullable NSString *)base64;

@end

NS_ASSUME_NONNULL_END
