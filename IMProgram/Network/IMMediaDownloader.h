//  IMMediaDownloader.h
//  媒体/文件**下载**引擎（M4-7），与 IMChunkedUploader 镜像：HTTP Range 断点续传、可暂停/继续/取消、
//  界面重建后 taskForKey: 重新接管。下载从 /uploads/ 静态目录直取（无鉴权，URL 是不可猜的 UUID）。
//
//  断点：本地 `.part` 临时文件的当前大小即续传 offset（服务端 Go FileServer 原生支持 Range）。
//  暂停=掐断在飞请求、保留 `.part`；继续=按 `.part` 大小发新的 Range 请求。全程流式写盘，内存与文件大小无关。
//  **任务活在下载器单例里**（按 key 注册），不随聊天页销毁。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaDownloadTask : NSObject

@property (nonatomic, copy, readonly) NSString *key;          ///< 注册键（通常 server_msg_id 或 URL）
@property (nonatomic, assign, readonly) int64_t receivedBytes;
@property (nonatomic, assign, readonly) int64_t totalBytes;   ///< 0=未知（响应无 Content-Range/Length）
@property (nonatomic, assign, readonly) BOOL paused;

/// 回调可随时替换：新的聊天页据此接管一条仍在跑的下载。均在主线程调用。
@property (nonatomic, copy, nullable) void (^progressHandler)(int64_t receivedBytes, int64_t totalBytes);
@property (nonatomic, copy, nullable) void (^completionHandler)(NSURL *_Nullable localFileURL, NSError *_Nullable error);

- (void)pause;  ///< 停在当前字节，保留 `.part`
- (void)resume; ///< 从 `.part` 大小续传
- (void)cancel; ///< 不再续传、删 `.part`、不再回调、从注册表移除
@end

@interface IMMediaDownloader : NSObject

+ (instancetype)shared;

/// 下载文件的本地落地位置：`<Caches>/IMDownloads/<content 的 basename>`。
/// content 形如 `/uploads/<uuid>__name.ext`，basename 里的 uuid 保证唯一、且保留扩展名供 QuickLook 识别类型。
+ (nullable NSURL *)cachedFileURLForContent:(nullable NSString *)content;

/// 该文件是否已下载到本机（落地文件存在）。清缓存后回退未下载态即靠它判定。
+ (BOOL)isContentCached:(nullable NSString *)content;

/// 发送成功后把本地原件**收编**进下载缓存（自己发的文件点开即 QuickLook、免重下；仿视频 IMOriginalVideoCache）。
/// 优先 move（同沙盒近乎瞬时、与大小无关、不占额外空间），跨卷失败回退 copy。已存在则跳过。返回是否落地成功。
+ (BOOL)adoptFileAtPath:(nullable NSString *)path forContent:(nullable NSString *)content;

/// 取仍在进行中的任务（含暂停态）；无则 nil。用于界面重建后重新接管。
- (nullable IMMediaDownloadTask *)taskForKey:(NSString *)key;

/// 下载 remoteURL 到 destinationURL（最终落地文件）。同 key 已有任务时直接返回既有（不会重复下载）。
- (IMMediaDownloadTask *)downloadURL:(NSURL *)remoteURL
                       toDestination:(NSURL *)destinationURL
                                 key:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
