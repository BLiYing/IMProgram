//  IMVideoThumbnailLoader.h
//  视频首帧（封面）异步加载：AVAssetImageGenerator 抽第一帧 + 内存缓存；completion 必在主线程。
//  与 IMImageLoader 平行，供图片/视频 cell 与全屏查看器共用（避免重复抽帧）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMVideoThumbnailLoader : NSObject

+ (instancetype)shared;

/// 抽取视频首帧作为封面图。urlString 为完整 http(s) 视频地址。空/失败 → completion(nil)。
/// completion 总在主线程回调；同一 URL 命中内存缓存直接回调。
- (void)loadPosterForVideoURL:(nullable NSString *)urlString completion:(void (^)(UIImage *_Nullable poster))completion;

@end

NS_ASSUME_NONNULL_END
