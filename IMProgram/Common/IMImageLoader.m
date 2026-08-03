//  IMImageLoader.m

#import "IMImageLoader.h"
#import "IMLog.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>

/// 内存缓存按**解码后字节数**计量，而不是张数：200 张 4032×3024 的原图 ≈ 9.7 GB，
/// 只设 countLimit 等于没设上限，真机会直接内存告警甚至被 jetsam 干掉。
static const NSUInteger kIMImageMemoryCostLimit = 64 * 1024 * 1024; // 64MB 解码位图
static const unsigned long long kIMImageDiskCapacity = 256 * 1024 * 1024; // 磁盘缓存上限
/// 缩略图最长边（点）。气泡最大 240×320，3 倍屏即 960px；再大对显示没有任何收益，只会拖慢解码。
static const CGFloat kIMImageMaxPixelSize = 1024;

/// URL → 磁盘缓存文件名（SHA256，避免超长/非法字符）。
static NSString *IMImageDiskKey(NSString *urlString) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    NSData *raw = [urlString dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(raw.bytes, (CC_LONG)raw.length, digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) { [out appendFormat:@"%02x", digest[i]]; }
    return out;
}

/// 按目标尺寸**降采样解码**：ImageIO 直接吐小图，不会先把原图整张解成位图。
/// 同时 kCGImageSourceShouldCacheImmediately 让解码发生在**当前后台线程**，
/// 否则位图解码会推迟到主线程首次绘制时发生——这正是滚动掉帧的元凶。
static UIImage *IMImageDecodeDownsampled(NSData *data, CGFloat maxPixelSize) {
    if (data.length == 0) { return nil; }
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data,
        (__bridge CFDictionaryRef)@{ (id)kCGImageSourceShouldCache: @NO });
    if (!src) { return nil; }
    NSDictionary *opts = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,   // 尊重 EXIF 方向
        (id)kCGImageSourceShouldCacheImmediately: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize),
    };
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    if (!cg) { return nil; }
    UIImage *image = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return image;
}

/// 解码后位图字节数，作为 NSCache 的 cost。
static NSUInteger IMImageCost(UIImage *image) {
    CGImageRef cg = image.CGImage;
    if (!cg) { return 1; }
    return CGImageGetBytesPerRow(cg) * CGImageGetHeight(cg);
}

@implementation IMImageLoader {
    NSCache<NSString *, UIImage *> *_cache;
    NSURLSession *_session;
    NSString *_diskDir;
    dispatch_queue_t _diskQueue;   // 串行：磁盘读写与容量记账
    dispatch_queue_t _decodeQueue; // 并发：降采样解码（不占用串行队列）
    unsigned long long _diskBytes; // 磁盘缓存已用字节（仅 _diskQueue 访问），避免每次都全目录扫描
}

+ (instancetype)shared {
    static IMImageLoader *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMImageLoader new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSCache new];
        _cache.totalCostLimit = kIMImageMemoryCostLimit;
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 15;
        _session = [NSURLSession sessionWithConfiguration:cfg];

        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        _diskDir = [caches stringByAppendingPathComponent:@"im_image_cache"];
        [NSFileManager.defaultManager createDirectoryAtPath:_diskDir withIntermediateDirectories:YES attributes:nil error:NULL];
        _diskQueue = dispatch_queue_create("im.image.disk", DISPATCH_QUEUE_SERIAL);
        // 解码不占串行队列：磁盘命中若在 _diskQueue 上解码，多张图会被排成一队逐个解。
        _decodeQueue = dispatch_queue_create("im.image.decode", DISPATCH_QUEUE_CONCURRENT);
        // 启动时扫一次算出总量，之后只累加/递减；否则每下载一张图就要全目录 readdir+stat+排序。
        // 内存告警时 NSCache 自清，磁盘缓存留着——它正是为了冷启动不重下。
        dispatch_async(_diskQueue, ^{
            self->_diskBytes = [self measureDiskBytes];
            [self trimDiskCacheIfNeeded];
        });
    }
    return self;
}

- (void)cacheImage:(UIImage *)image forURL:(NSString *)urlString {
    if (image && urlString.length > 0) { [_cache setObject:image forKey:urlString cost:IMImageCost(image)]; }
}

- (UIImage *)cachedImageForURL:(NSString *)urlString {
    return urlString.length ? [_cache objectForKey:urlString] : nil;
}

- (void)loadImageURL:(NSString *)urlString completion:(void (^)(UIImage *_Nullable))completion {
    NSString *key = urlString.length ? urlString : @"";
    void (^finishAsync)(UIImage *_Nullable) = ^(UIImage *_Nullable img) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(img); });
    };
    if (key.length == 0) { finishAsync(nil); return; }

    // 命中内存缓存在主线程上**同步**回调：异步会让调用方先把 imageView 置空、一帧后才填图 → 每次滚动都闪。
    // 非主线程调用仍切回主线程，避免把 UIKit 操作带到后台线程。
    UIImage *cached = [_cache objectForKey:key];
    if (cached) {
        if (NSThread.isMainThread) { completion(cached); } else { finishAsync(cached); }
        return;
    }

    // data:image/...;base64,XXXX —— 本地解码，不走网络。
    if ([urlString hasPrefix:@"data:image/"]) {
        NSRange comma = [urlString rangeOfString:@","];
        if (comma.location == NSNotFound) { finishAsync(nil); return; }
        NSString *b64 = [urlString substringFromIndex:comma.location + 1];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSData *data = [[NSData alloc] initWithBase64EncodedString:b64
                                                              options:NSDataBase64DecodingIgnoreUnknownCharacters];
            UIImage *img = IMImageDecodeDownsampled(data, kIMImageMaxPixelSize);
            if (img) { [self->_cache setObject:img forKey:key cost:IMImageCost(img)]; }
            finishAsync(img);
        });
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || (![url.scheme isEqualToString:@"http"] && ![url.scheme isEqualToString:@"https"])) {
        finishAsync(nil);
        return;
    }

    __weak typeof(self) ws = self;
    dispatch_async(_diskQueue, ^{
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        // 二级磁盘缓存：杀进程后 NSCache 全空，没有磁盘缓存就得整屏重下（真机实测进会话长时间白屏）。
        NSData *diskData = [NSData dataWithContentsOfFile:[self diskPathForKey:key]];
        if (diskData.length > 0) {
            [self touchDiskFileForKey:key]; // LRU：记一次访问时间
            dispatch_async(self->_decodeQueue, ^{
                UIImage *img = IMImageDecodeDownsampled(diskData, kIMImageMaxPixelSize);
                if (img) {
                    [self->_cache setObject:img forKey:key cost:IMImageCost(img)];
                    finishAsync(img);
                } else {
                    dispatch_async(self->_diskQueue, ^{ [self downloadImageURL:url key:key finish:finishAsync]; });
                }
            });
            return;
        }
        [self downloadImageURL:url key:key finish:finishAsync];
    });
}

- (void)downloadImageURL:(NSURL *)url key:(NSString *)key finish:(void (^)(UIImage *))finish {
    __weak typeof(self) ws = self;
    NSURLSessionDataTask *task = [_session dataTaskWithURL:url
            completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable resp, NSError *_Nullable err) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (err || data.length == 0) {
            IMLogWarnWithTag(IMLogTagMedia, @"image_fetch_failed bytes=%lu error=%@",
                             (unsigned long)data.length, err.localizedDescription ?: @"-");
            finish(nil);
            return;
        }
        UIImage *img = IMImageDecodeDownsampled(data, kIMImageMaxPixelSize);
        if (!img) { finish(nil); return; }
        [self->_cache setObject:img forKey:key cost:IMImageCost(img)];
        // 原始字节落盘（不是降采样后的），换设备/换尺寸时仍可复用。
        dispatch_async(self->_diskQueue, ^{
            if ([data writeToFile:[self diskPathForKey:key] atomically:YES]) {
                self->_diskBytes += data.length;
            }
            [self trimDiskCacheIfNeeded];
        });
        finish(img);
    }];
    [task resume];
}

#pragma mark - 磁盘缓存

- (NSString *)diskPathForKey:(NSString *)key {
    return [_diskDir stringByAppendingPathComponent:IMImageDiskKey(key)];
}

- (void)touchDiskFileForKey:(NSString *)key {
    [NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate: NSDate.date }
                                   ofItemAtPath:[self diskPathForKey:key] error:NULL];
}

/// 目录总字节数（只在启动与裁剪后各算一次）。仅在 _diskQueue 调用。
- (unsigned long long)measureDiskBytes {
    unsigned long long total = 0;
    for (NSURL *f in [NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:_diskDir]
                                                 includingPropertiesForKeys:@[NSURLFileSizeKey]
                                                                    options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL]) {
        NSNumber *size = nil;
        [f getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        total += size.unsignedLongLongValue;
    }
    return total;
}

/// LRU 裁剪：仅当**记账值**超过上限才真正扫盘，按最后修改时间从旧到新删到上限的 80%
/// （避免反复贴着上限抖动）。之前每下载一张图都全目录扫描 + 排序，一屏图片就是几十次。
/// 仅在 _diskQueue 调用。
- (void)trimDiskCacheIfNeeded {
    if (_diskBytes <= kIMImageDiskCapacity) { return; }
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSURL *> *files = [fm contentsOfDirectoryAtURL:[NSURL fileURLWithPath:_diskDir]
                               includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLFileSizeKey]
                                                  options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    unsigned long long total = 0;
    NSMutableArray<NSURL *> *sorted = [files mutableCopy];
    for (NSURL *f in files) {
        NSNumber *size = nil;
        [f getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        total += size.unsignedLongLongValue;
    }
    [sorted sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *da = nil, *db = nil;
        [a getResourceValue:&da forKey:NSURLContentModificationDateKey error:NULL];
        [b getResourceValue:&db forKey:NSURLContentModificationDateKey error:NULL];
        return [(da ?: NSDate.distantPast) compare:(db ?: NSDate.distantPast)];
    }];
    unsigned long long target = kIMImageDiskCapacity * 4 / 5;
    for (NSURL *f in sorted) {
        if (total <= target) { break; }
        NSNumber *size = nil;
        [f getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        if ([fm removeItemAtURL:f error:NULL]) { total -= size.unsignedLongLongValue; }
    }
    _diskBytes = total; // 与真实占用对齐（记账值会因外部清理/写失败漂移）
    IMLogDebugWithTag(IMLogTagMedia, @"image_disk_cache_trimmed bytes_after=%llu", total);
}

@end
