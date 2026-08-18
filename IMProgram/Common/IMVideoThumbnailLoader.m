//  IMVideoThumbnailLoader.m

#import "IMVideoThumbnailLoader.h"
#import <AVFoundation/AVFoundation.h>

@implementation IMVideoThumbnailLoader {
    NSCache<NSString *, UIImage *> *_cache;
}

+ (instancetype)shared {
    static IMVideoThumbnailLoader *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [IMVideoThumbnailLoader new]; });
    return inst;
}

- (instancetype)init {
    if ((self = [super init])) {
        _cache = [NSCache new];
        _cache.countLimit = 50;
    }
    return self;
}

- (void)cachePoster:(UIImage *)poster forURL:(NSString *)urlString {
    if (poster && urlString.length > 0) { [_cache setObject:poster forKey:urlString]; }
}

- (UIImage *)cachedPosterForURL:(NSString *)urlString {
    return urlString.length > 0 ? [_cache objectForKey:urlString] : nil;
}

- (void)loadPosterForVideoURL:(NSString *)urlString completion:(void (^)(UIImage *_Nullable))completion {
    if (!completion) { return; }
    if (urlString.length == 0) { completion(nil); return; }

    UIImage *cached = [_cache objectForKey:urlString];
    if (cached) { completion(cached); return; }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) { completion(nil); return; }

    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIImage *poster = [IMVideoThumbnailLoader extractPosterFromAssetURL:url maxSize:720]; // 封面无需原分辨率，控内存
        __strong typeof(ws) self = ws;
        if (self && poster) { [self->_cache setObject:poster forKey:urlString]; }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(poster); });
    });
}

+ (UIImage *)extractPosterFromAssetURL:(NSURL *)assetURL maxSize:(CGFloat)maxSize {
    if (!assetURL) { return nil; }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:assetURL options:nil];
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;   // 尊重拍摄方向，避免首帧旋转
    gen.maximumSize = CGSizeMake(maxSize, maxSize);
    CMTime at = CMTimeMakeWithSeconds(0.1, 600); // 取第 0.1s，避开纯黑首帧
    CGImageRef cg = [gen copyCGImageAtTime:at actualTime:NULL error:NULL];
    if (!cg) { return nil; }
    UIImage *poster = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return poster;
}

@end
