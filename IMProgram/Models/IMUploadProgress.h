//  IMUploadProgress.h
//  一条待发媒体的上传进度（聊天页 outbox 用）。原先只在字典里存一个 NSNumber(0..1)，
//  改造后要显示「已传 3.2 MB / 7.9 MB」，必须同时带上总字节数，故收敛为一个小值对象。
//
//  失败沿用旧语义（原来是 -2 哨兵）：failed=YES，界面显"发送失败"。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMUploadProgress : NSObject

@property (nonatomic, assign, readonly) double fraction;   ///< 0..1 上传比例（排队中=0）
@property (nonatomic, assign, readonly) int64_t totalBytes; ///< 媒体本体字节数（0=未知 → 只显百分比）
@property (nonatomic, assign, readonly) BOOL failed;        ///< YES=发送失败（显"发送失败"，可重试）

+ (instancetype)progressWithFraction:(double)fraction totalBytes:(int64_t)totalBytes;
/// 排队中（尚未开始上传）：fraction=0，界面显"等待中"。
+ (instancetype)queuedWithTotalBytes:(int64_t)totalBytes;
+ (instancetype)failedProgress;

/// 覆盖层文案：`等待中` / `3.2 MB / 7.9 MB`（总大小未知时回退 `45%`）/ `发送失败`。
- (NSString *)displayText;

@end

NS_ASSUME_NONNULL_END
