//  IMAvatarCropViewController.h
//  圆形头像裁切（方案 C · iOS）。全屏纯黑；圆窗 ⌀ = 屏宽 − 32pt、圆心 y = 屏高 × 0.44；
//  拖动 + 双指捏合缩放（1×–4×）；底部左下 Liquid Glass 返回、右下系统蓝确定（规格见 docs/design/sketches/UX_SKETCH.html §iOS）。
//  确定后输出**圆的外接正方形**裁切并缩到 256×256 的 JPEG（存方图、显示时切圆，与 Web 一致）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAvatarCropViewController : UIViewController

/// image 为待裁切图片；onComplete 回调裁切后的 JPEG data（点确定），取消则回 nil。主线程回调。
- (instancetype)initWithImage:(UIImage *)image;
@property (nonatomic, copy, nullable) void (^onComplete)(NSData *_Nullable jpegData);

@end

NS_ASSUME_NONNULL_END
