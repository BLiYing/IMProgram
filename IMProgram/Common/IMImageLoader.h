//  IMImageLoader.h
//  头像图片异步加载：支持 data:image 内联 base64 与 http(s) 远程；内存缓存；completion 必在主线程。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMImageLoader : NSObject

+ (instancetype)shared;

/// 加载头像图：urlString 可为 data:image base64 或 http(s)。空/失败 → completion(nil)。completion 总在主线程回调。
- (void)loadImageURL:(nullable NSString *)urlString completion:(void (^)(UIImage *_Nullable image))completion;

@end

NS_ASSUME_NONNULL_END
