//  IMOriginalVideoCache.h
//  原视频本地缓存（Caches/im_original_videos/<url-hash>.mp4），两类来源：
//    1. 查看器里点「查看原视频」下载完成后落入；
//    2. **自己发送成功的视频**：上传完成后把本地待发副本直接收编进来——字节与服务器上的
//       完全相同，重开查看器立即本地播放，不再显示「查看原视频 xxMB」、不再流式拉远端。
//  key 用查看器同款的完整 URL（IMMediaFullURL 补 host 后），两边命中同一份文件。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMOriginalVideoCache : NSObject

/// 该完整 URL 对应的缓存文件路径（不保证存在）。
+ (NSURL *)cacheURLForFullURL:(NSString *)fullURL;

/// 是否已有本地原件。
+ (BOOL)hasCacheForFullURL:(NSString *)fullURL;

/// 把一个本地文件收编为该 URL 的原件缓存（move，源文件消失；已存在则覆盖）。失败静默（下次走网络）。
+ (void)adoptFileAtPath:(NSString *)path forFullURL:(NSString *)fullURL;

@end

NS_ASSUME_NONNULL_END
