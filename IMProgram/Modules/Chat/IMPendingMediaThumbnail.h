//  IMPendingMediaThumbnail.h
//  本地待发媒体的缩略图生成（后台队列调用）：视频抽首帧、图片降采样，绝不整图解码。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 视频抽首帧作缩略图（最大边 600pt）。失败返回 nil。
FOUNDATION_EXPORT UIImage *_Nullable IMPendingVideoThumbnail(NSString *path);

/// 图片按目标尺寸降采样缩略图（最大边 1024px），绝不整图解码。失败返回 nil。
FOUNDATION_EXPORT UIImage *_Nullable IMPendingImageThumbnail(NSString *path);

NS_ASSUME_NONNULL_END
