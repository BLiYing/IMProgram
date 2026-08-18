//  IMPendingMediaThumbnail.m

#import "IMPendingMediaThumbnail.h"
#import "IMVideoThumbnailLoader.h"
#import "IMImageLoader.h"

// 发件箱本地待发媒体的缩略尺寸（气泡够用即可，控内存）。抽帧/降采样口径与 cell/查看器共用的
// IMVideoThumbnailLoader / IMImageLoader 同一实现，这里只是给本地文件路径套上这两个尺寸。
static const CGFloat kIMPendingVideoThumbMaxSize = 600;
static const CGFloat kIMPendingImageThumbMaxSize = 1024;

UIImage *IMPendingVideoThumbnail(NSString *path) {
    if (path.length == 0) { return nil; }
    return [IMVideoThumbnailLoader extractPosterFromAssetURL:[NSURL fileURLWithPath:path]
                                                     maxSize:kIMPendingVideoThumbMaxSize];
}

UIImage *IMPendingImageThumbnail(NSString *path) {
    if (path.length == 0) { return nil; }
    return [IMImageLoader downsampledImageAtFileURL:[NSURL fileURLWithPath:path]
                                       maxPixelSize:kIMPendingImageThumbMaxSize];
}
