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

- (void)loadPosterForVideoURL:(NSString *)urlString completion:(void (^)(UIImage *_Nullable))completion {
    if (!completion) { return; }
    if (urlString.length == 0) { completion(nil); return; }

    UIImage *cached = [_cache objectForKey:urlString];
    if (cached) { completion(cached); return; }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) { completion(nil); return; }

    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        gen.appliesPreferredTrackTransform = YES;   // 尊重拍摄方向，避免首帧旋转
        gen.maximumSize = CGSizeMake(720, 720);      // 封面无需原分辨率，控内存
        CMTime at = CMTimeMakeWithSeconds(0.1, 600); // 取第 0.1s，避开纯黑首帧
        NSError *err = nil;
        CGImageRef cg = [gen copyCGImageAtTime:at actualTime:NULL error:&err];
        UIImage *poster = cg ? [UIImage imageWithCGImage:cg] : nil;
        if (cg) { CGImageRelease(cg); }
        __strong typeof(ws) self = ws;
        if (self && poster) { [self->_cache setObject:poster forKey:urlString]; }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(poster); });
    });
}

@end
