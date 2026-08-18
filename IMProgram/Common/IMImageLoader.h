//  IMImageLoader.h
//  图片异步加载：支持 data:image 内联 base64 与 http(s) 远程。
//  内存缓存（按解码字节数限容）+ 磁盘缓存（LRU，冷启动免重下）+ 降采样解码（不在主线程解大图）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMImageLoader : NSObject

+ (instancetype)shared;

/// 从本地文件**同步**降采样解码缩略图（须在后台线程调用）：ImageIO 直接吐 maxPixelSize 内的小图、
/// 尊重 EXIF 方向，绝不整图解码。失败返回 nil。与内部 http/磁盘解码共用同一降采样口径，
/// 供发件箱本地待发图缩略等场景复用，避免各处重抄一份 CGImageSourceCreateThumbnail 配方。
+ (nullable UIImage *)downsampledImageAtFileURL:(NSURL *)fileURL maxPixelSize:(CGFloat)maxPixelSize;

/// 加载图片：urlString 可为 data:image base64 或 http(s)。空/失败 → completion(nil)。
/// **命中内存缓存时同步回调**（调用线程），其余情况在主线程回调——同步命中是为了消除
/// "先置空再填图"造成的滚动闪烁，调用方可安全地在 cellForRow 里直接用返回值。
- (void)loadImageURL:(nullable NSString *)urlString completion:(void (^)(UIImage *_Nullable image))completion;

/// 预置缓存：上传完成后把本地预览图种到该 URL 名下，气泡切服务器 URL 时无需重新下载（不闪图）。
- (void)cacheImage:(nullable UIImage *)image forURL:(nullable NSString *)urlString;

/// 同步取内存缓存（命中即返回，否则 nil）。供列表/头像 reloadData 时**直接显图不回退首字母**、消除闪动。
- (nullable UIImage *)cachedImageForURL:(nullable NSString *)urlString;

/// 清空图片缓存（内存 + 磁盘）。设置页「清除缓存」调用：只删本机，云端保留可重下。
/// 必须连内存一起清——否则 `hasCachedImageForURL:` 仍回 YES，图片卡片清完缓存也退不回"未下载"态。
- (void)clearCache;

/// 该 URL 是否已在缓存（内存或磁盘，不发起网络）。data: 内联视为已有。M4-7 图片门控据此判定"已下载不再门控"。
- (BOOL)hasCachedImageForURL:(nullable NSString *)urlString;

@end

NS_ASSUME_NONNULL_END
