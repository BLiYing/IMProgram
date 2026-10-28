//  IMExportDownloader.h
//  导出 ZIP 下载（DATA_EXPORT_DESIGN §5）：URLSession downloadTask 落盘到 NSTemporaryDirectory()，
//  不进内存（可能数百 MB）。下载地址是一次性 token URL，不带登录头。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const IMExportDownloadErrorDomain;

/// 进度回调（主线程）：written = 已收字节；expected = 总字节，<= 0 表示未知（走不定长）。
typedef void (^IMExportDownloadProgress)(int64_t written, int64_t expected);

/// 进度节流（纯函数，便于单测）：首次必发；收齐必发；距上次 >= 0.1s，或较上次推进 >= 总长度 1% 才发。lastEmit < 0 表示尚未发过。
FOUNDATION_EXPORT BOOL IMExportDownloadShouldEmitProgress(NSTimeInterval lastEmit, NSTimeInterval now,
                                                          int64_t lastBytes, int64_t bytes, int64_t expected);

@interface IMExportDownloader : NSObject

/// 下载到 NSTemporaryDirectory()/fileName（同名旧文件先删）。completion 回主线程：成功给本地 URL；
/// 失败 error.domain = IMExportDownloadErrorDomain，code = HTTP 状态码（传输层失败为 -1，落盘失败为 -2）。
/// 返回 task 供调用方取消（取消后 completion 以 NSURLErrorCancelled 回调，domain 为 NSURLErrorDomain）。
+ (NSURLSessionDownloadTask *)downloadFromURL:(NSURL *)url
                                     fileName:(NSString *)fileName
                                   completion:(void (^)(NSURL *_Nullable fileURL, NSError *_Nullable error))completion;

/// 同上，另带进度回调（主线程、节流；completion 触发后不再回调 progress）。progress 可为 nil。
+ (NSURLSessionDownloadTask *)downloadFromURL:(NSURL *)url
                                     fileName:(NSString *)fileName
                                     progress:(nullable IMExportDownloadProgress)progress
                                   completion:(void (^)(NSURL *_Nullable fileURL, NSError *_Nullable error))completion;

/// 仅测试用：给之后创建的下载会话注入 NSURLProtocol 桩（传 nil 还原）。
+ (void)setProtocolClassesForTesting:(nullable NSArray<Class> *)classes;

@end

NS_ASSUME_NONNULL_END
