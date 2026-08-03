//  IMUploadProgress.h
//  一条待发媒体的进度。视频要先转码再上传，两段必须**融合成一条只增不减的进度**——
//  否则用户会看到进度走到 100% 又跳回 0（转码结束、上传开始）。
//
//  文案分阶段：转码期拿不到产物体积，只能显百分比；上传期显「已传 / 总大小」。
//  宫格里的环形进度统一用 overallFraction，跨阶段连续推进。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMUploadPhase) {
    IMUploadPhaseQueued = 0,  ///< 已上屏、尚未开工（显"等待中"）
    IMUploadPhaseTranscoding, ///< 视频转码中（显"压缩中 42%"）
    IMUploadPhaseUploading,   ///< 上传中（显"3.9 MB / 12.4 MB"）
    IMUploadPhaseFailed,      ///< 失败（显"发送失败"，宫格标 !）
};

@interface IMUploadProgress : NSObject

@property (nonatomic, assign, readonly) IMUploadPhase phase;
@property (nonatomic, assign, readonly) double fraction;    ///< **当前阶段**内的 0..1
@property (nonatomic, assign, readonly) int64_t totalBytes; ///< 媒体本体字节数（0=未知 → 只显百分比）
@property (nonatomic, assign, readonly) BOOL failed;

/// 本条是否经历过转码阶段：决定上传进度落在总刻度的哪一段（图片/直传视频不该凭空从 35% 起跳）。
@property (nonatomic, assign, readonly) BOOL afterTranscode;

/// 转码与上传融合后的总进度 0..1（环形进度用；无转码阶段时等于上传进度）。
@property (nonatomic, assign, readonly) double overallFraction;

+ (instancetype)queued;
/// fraction=AVAssetExportSession.progress。
+ (instancetype)transcodingWithFraction:(double)fraction;
/// totalBytes 用**媒体本体**字节数（非 multipart 整包），否则与文件属性对不上。
/// previous 传该条上一次的进度对象（可空），用于继承"是否转码过"，避免刻度跳变。
+ (instancetype)uploadingWithFraction:(double)fraction
                           totalBytes:(int64_t)totalBytes
                             previous:(nullable IMUploadProgress *)previous;
+ (instancetype)failedProgress;

/// 覆盖层文案：`等待中` / `压缩中 42%` / `3.9 MB / 12.4 MB` / `发送失败`。
- (NSString *)displayText;

/// 文件气泡第二行文案：在 displayText 后追加可操作提示（`· 点击暂停` / `· 点击继续` / `· 点击重试`）。
- (NSString *)fileLineText;

/// 暂停态（用户主动停在分片边界，服务端保留已传字节）。
@property (nonatomic, assign) BOOL pausedByUser;

@end

NS_ASSUME_NONNULL_END
