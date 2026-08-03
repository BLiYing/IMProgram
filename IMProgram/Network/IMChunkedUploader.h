//  IMChunkedUploader.h
//  分片上传（对应服务端 /api/v1/upload/init|chunk|status|complete）。
//
//  为什么不用一次性 multipart：
//    - 大文件一次性上传中断即全部作废（真机实测 74MB 视频传到 46s 超时，白干）；
//    - 无法暂停/恢复；
//    - 客户端与服务端都要吃下一整份文件的内存。
//  分片方案按 offset 顺序追加，中断后问一次 status 就能接着传，全程从磁盘流式读，内存与文件大小无关。
//
//  **任务活在 uploader 单例里**（按 key 注册），不随聊天页销毁：退出会话再进来可用 taskForKey:
//  重新接管进度与完成回调，否则上传还在跑但界面既看不到也停不掉。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 单个上传任务的句柄：可暂停、可恢复、可取消，可被新的界面重新接管。
@interface IMChunkedUploadTask : NSObject

/// 注册键（调用方传入，通常是 clientMsgID）。
@property (nonatomic, copy, readonly) NSString *key;
/// 服务端分配的上传 ID；持久化它即可跨 App 启动续传（配合本地文件路径）。
@property (nonatomic, copy, readonly, nullable) NSString *uploadID;
@property (nonatomic, assign, readonly) int64_t sentBytes;
@property (nonatomic, assign, readonly) int64_t totalBytes;
@property (nonatomic, assign, readonly) BOOL paused;

/// 回调可随时替换：新的聊天页实例据此接管一条仍在跑的上传。均在主线程调用。
@property (nonatomic, copy, nullable) void (^progressHandler)(int64_t sentBytes, int64_t totalBytes);
@property (nonatomic, copy, nullable) void (^completionHandler)(NSString *_Nullable url,
                                                                NSString *_Nullable contentType,
                                                                NSError *_Nullable error);
/// 拿到服务端 upload_id 时回调一次（主线程），供调用方持久化以便跨启动续传。
@property (nonatomic, copy, nullable) void (^uploadIDHandler)(NSString *uploadID);

/// 暂停：停在当前分片边界，已传字节保留在服务端。
- (void)pause;
/// 恢复：先向服务端要 offset 再续传（服务端才是"传到哪了"的唯一权威）。
- (void)resume;
/// 取消：不再续传，也不再回调；从 uploader 注册表移除。
- (void)cancel;
@end

@interface IMChunkedUploader : NSObject

+ (instancetype)shared;

/// 超过该大小才值得走分片（小文件多三次往返反而更慢）。
@property (class, nonatomic, readonly) NSUInteger chunkedThresholdBytes;

/// 取仍在进行中的任务（含暂停态）；无则 nil。用于界面重建后重新接管。
- (nullable IMChunkedUploadTask *)taskForKey:(NSString *)key;

/// 从本地文件分片上传。同 key 已有任务时直接返回既有任务（不会重复上传）。
/// @param key      注册键（clientMsgID）
/// @param fileURL  本地文件（不读进内存，按片读）
/// @param resumeID 已有的 upload_id（续传）；nil 表示新开一次
- (IMChunkedUploadTask *)uploadFileAtURL:(NSURL *)fileURL
                                fileName:(NSString *)fileName
                                   token:(NSString *)token
                                     key:(NSString *)key
                                resumeID:(nullable NSString *)resumeID;

@end

NS_ASSUME_NONNULL_END
