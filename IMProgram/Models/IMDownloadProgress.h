//  IMDownloadProgress.h
//  一条媒体/文件的**下载**进度（M4-7）。与 IMUploadProgress 镜像对称：上传把 ↑ 当"续传"，
//  下载把 ↓ 当"下载/继续"；中心圆钮状态机复用同一套 SF Symbol（✕/⏸/↓/↻）。
//
//  三条铁律（见 docs/DOWNLOAD_UX_SKETCH.html）：① 下载全程不跳页；② 完成即止**绝不自动打开/播放**
//  （Done 态不给中心按钮，由 cell 各自呈现清晰图/▶/文件图标，用户主动点才打开）；③ 手动点击永远优先。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMDownloadPhase) {
    IMDownloadPhaseNotStarted = 0, ///< 未下载：中心 ↓ + 尺寸角标（关闭自动下载 / 超阈值的常驻态）
    IMDownloadPhaseDownloading,    ///< 下载中：环形进度 + ⏸（可暂停）/ ✕（不可暂停时取消）
    IMDownloadPhasePaused,         ///< 已暂停：↓ 继续（服务端文件长驻，按已下字节续传）
    IMDownloadPhaseFailed,         ///< 失败：↻ 重试（网络错）；服务端已清理（expired）则显"文件已失效"、不给重试
    IMDownloadPhaseDone,           ///< 就绪：无中心按钮，cell 显清晰图/▶/文件图标，点才打开
};

@interface IMDownloadProgress : NSObject

@property (nonatomic, assign, readonly) IMDownloadPhase phase;
@property (nonatomic, assign, readonly) int64_t receivedBytes; ///< 已下载字节
@property (nonatomic, assign, readonly) int64_t totalBytes;    ///< 媒体本体字节数（0=未知 → 环形进度回退百分比不可算，只显菊花）
@property (nonatomic, assign, readonly) BOOL pausable;         ///< 走分片/大文件的下载可暂停（点 ⏸ 停在边界）；小文件几秒下完不值得暂停
/// 失败分因（草图 §08-05）：YES=服务端已清理/过期（404/410），**不给重试**、文案「文件已失效」；
/// NO=网络错，给 ↻ 重试。仅 Failed 态有意义。
@property (nonatomic, assign, readonly) BOOL expired;

/// 0..1 总进度（环形进度用）；totalBytes=0 时回退 0。
@property (nonatomic, assign, readonly) double fraction;

+ (instancetype)notStartedWithTotalBytes:(int64_t)totalBytes;
+ (instancetype)downloadingWithReceived:(int64_t)received total:(int64_t)total pausable:(BOOL)pausable;
+ (instancetype)pausedWithReceived:(int64_t)received total:(int64_t)total;
+ (instancetype)failedWithReceived:(int64_t)received total:(int64_t)total;
/// 服务端已清理/过期：终态，无重试入口。
+ (instancetype)expiredWithTotalBytes:(int64_t)totalBytes;
+ (instancetype)done;

/// 媒体（图片/视频）角标文案：未下载=尺寸（如 `2.4 MB`）；下载中/暂停=`已下 / 总`；失败=`下载失败`；就绪=空串。
- (NSString *)displayText;

/// VoiceOver 文案（草图 §08-09）：未下载=`下载，2.4 MB`；下载中=`下载中 45%`；暂停=`已暂停，点按继续`；
/// 失败=`下载失败，点按重试` / `文件已失效`；就绪=`已下载`。
- (NSString *)accessibilityText;

/// 文件气泡第二行文案：未下载=`点击下载`；下载中/暂停=`已下 / 总`；失败=`下载失败，点击重试`；就绪=`点击打开`。
/// （尺寸由 cell 在未下载态另行拼在前面，与上传路径 IMBubbleCell 对称。）
- (NSString *)fileLineText;

@end

/// 中心圆钮的 SF Symbol 名（占播放键位置，下载完成前视频本也不能播）。与上传状态机镜像：
///   未下载/已暂停 → `arrow.down.circle.fill`（↓ 下载/继续，与上传"已暂停 ↑ 续传"呼应）；
///   下载中·可暂停 → `pause.circle.fill`（⏸）；下载中·不可暂停 → `xmark.circle.fill`（✕ 取消）；
///   失败 → `arrow.clockwise.circle.fill`（↻ 重试）；**失败·已失效 → nil**（无从重试）；就绪 → nil（不给按钮，绝不自动打开）。
FOUNDATION_EXPORT NSString *_Nullable IMDownloadCenterSymbolName(IMDownloadProgress *progress);

NS_ASSUME_NONNULL_END
