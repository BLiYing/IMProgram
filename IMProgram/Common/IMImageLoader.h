//  IMImageLoader.h
//  头像图片异步加载：支持 data:image 内联 base64 与 http(s) 远程；内存缓存；completion 必在主线程。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMImageLoader : NSObject

+ (instancetype)shared;

/// 加载头像图：urlString 可为 data:image base64 或 http(s)。空/失败 → completion(nil)。completion 总在主线程回调。
- (void)loadImageURL:(nullable NSString *)urlString completion:(void (^)(UIImage *_Nullable image))completion;

/// 预置缓存：上传完成后把本地预览图种到该 URL 名下，气泡切服务器 URL 时无需重新下载（不闪图）。
- (void)cacheImage:(nullable UIImage *)image forURL:(nullable NSString *)urlString;

/// 同步取内存缓存（命中即返回，否则 nil）。供列表/头像 reloadData 时**直接显图不回退首字母**、消除闪动。
- (nullable UIImage *)cachedImageForURL:(nullable NSString *)urlString;

@end

NS_ASSUME_NONNULL_END
