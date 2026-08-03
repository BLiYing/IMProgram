//  IMMediaFormat.h
//  媒体气泡的纯函数工具：时长/字节/上传进度文案 + 按原比例的显示尺寸计算。
//  全部无副作用、不依赖 UIKit 状态，便于 XCTest 直接覆盖（见 IMMediaFormatTests）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 尺寸未知时的方形占位边长（与改造前的 180×180 一致；加载完成拿到真实尺寸后会重排）。
extern const CGFloat kIMMediaFallbackSide;

/// 视频时长（毫秒）→ 角标文案：`0:07` / `1:05` / `1:02:03`（≥1 小时才带小时段）。
/// millis <= 0（未知/非视频）返回 nil —— 调用方据此隐藏时长角标。
NSString *_Nullable IMFormatMediaDuration(int64_t millis);

/// 字节数 → `892 KB` / `7.9 MB`（1024 进制，MB 及以上保留 1 位小数）。bytes <= 0 返回 nil。
NSString *_Nullable IMFormatByteSize(int64_t bytes);

/// 上传进度文案：`3.2 MB / 7.9 MB`。totalBytes <= 0（未知大小）时回退百分比 `45%`；
/// fraction <= 0 视为排队中，返回 `等待中`。
NSString *IMFormatUploadProgress(double fraction, int64_t totalBytes);

/// 按原始像素比例算气泡显示尺寸（点）：等比缩放到 maxBox 内，**不放大超过 1pt/px**（小图保持小图，不糊）。
/// 极端长条（短边 < minSide）会按短边等比放大，但绝不越出 maxBox。
/// pixelW/pixelH <= 0（尺寸未知）→ 返回 kIMMediaFallbackSide 方块（收到真实尺寸后调用方重排）。
CGSize IMMediaDisplaySize(CGFloat pixelW, CGFloat pixelH, CGSize maxBox, CGFloat minSide);

NS_ASSUME_NONNULL_END
