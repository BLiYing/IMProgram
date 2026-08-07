//  IMMediaPlaceholder.m
#import "IMMediaPlaceholder.h"
#import <CoreImage/CoreImage.h>
#import "IMImageLoader.h"          // 图片本地缓存判定 + 取图
#import "IMVideoThumbnailLoader.h" // 视频本地文件抽帧
#import "IMOriginalVideoCache.h"   // 视频是否已本地下载

/// 代理放大最长边：thumb 仅 ~20px，直接在原尺寸做高斯会糊成一团；先等比放大到中等尺寸再模糊，
/// 收端 imageView 再放大到气泡尺寸时观感是平滑"磨砂"而非"低清块"。
static const CGFloat kIMFrostedProxyMaxSide = 48.0;
static const CGFloat kIMFrostedBlurSigma = 4.0;

@implementation IMMediaPlaceholder

+ (NSCache<NSString *, UIImage *> *)cache {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 120; });
    return cache;
}

/// CIContext 创建昂贵且线程安全，全局复用一枚。
+ (CIContext *)ciContext {
    static CIContext *ctx;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ctx = [CIContext contextWithOptions:nil]; });
    return ctx;
}

/// 解码 + 模糊放后台，避免在 cellForRow / 主线程抖动。
+ (dispatch_queue_t)renderQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("im.media.frosted", DISPATCH_QUEUE_CONCURRENT); });
    return queue;
}

+ (nullable UIImage *)cachedFrostedForThumb:(NSString *)thumbDataURI {
    if (thumbDataURI.length == 0) { return nil; }
    return [[self cache] objectForKey:thumbDataURI];
}

+ (void)previewForURL:(NSString *)url isVideo:(BOOL)isVideo thumb:(NSString *)thumbDataURI
           completion:(void (^)(UIImage *_Nullable))completion {
    // 门控一致（M4-7）：已下载才用真帧；否则内嵌 thumb 磨砂；都没有 → nil。绝不为预览联网拉原件/抽远端帧。
    if (isVideo) {
        if ([IMOriginalVideoCache hasCacheForFullURL:url]) {
            NSString *local = [IMOriginalVideoCache cacheURLForFullURL:url].absoluteString; // 本地文件抽帧，无网络
            [[IMVideoThumbnailLoader shared] loadPosterForVideoURL:local completion:completion];
            return;
        }
    } else if ([[IMImageLoader shared] hasCachedImageForURL:url]) {
        [[IMImageLoader shared] loadImageURL:url completion:completion]; // 命中缓存，无网络
        return;
    }
    if (thumbDataURI.length > 0) { [self frostedForThumb:thumbDataURI completion:completion]; return; }
    completion(nil);
}

+ (void)frostedForThumb:(NSString *)thumbDataURI completion:(void (^)(UIImage *_Nullable))completion {
    if (thumbDataURI.length == 0) { completion(nil); return; }
    UIImage *hit = [[self cache] objectForKey:thumbDataURI];
    if (hit) { completion(hit); return; } // 命中：同步回调（cellForRow 常见路径，免一跳）
    dispatch_async([self renderQueue], ^{
        UIImage *blurred = [self renderFrosted:thumbDataURI];
        if (blurred) { [[self cache] setObject:blurred forKey:thumbDataURI]; }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(blurred); });
    });
}

/// 解码 dataURI → 等比放大到代理尺寸 → 高斯模糊 → UIImage。任一步失败尽量降级返回（不 crash、宁可略糊）。
+ (nullable UIImage *)renderFrosted:(NSString *)thumbDataURI {
    // data:image/...;base64,XXXX —— 与 IMImageLoader 同一套本地 base64 解码。
    // 切勿用 NSURL+dataWithContentsOfURL：实测对 data: URI 返回 nil（磨砂恒失败→退灰底，等于功能报废）。
    NSRange comma = [thumbDataURI rangeOfString:@","];
    if (comma.location == NSNotFound) { return nil; }
    NSData *data = [[NSData alloc] initWithBase64EncodedString:[thumbDataURI substringFromIndex:comma.location + 1]
                                                      options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (data.length == 0) { return nil; }
    UIImage *small = [UIImage imageWithData:data];
    if (!small || small.size.width <= 0 || small.size.height <= 0) { return nil; }

    CGFloat w = small.size.width, h = small.size.height;
    CGFloat k = (w >= h) ? kIMFrostedProxyMaxSide / w : kIMFrostedProxyMaxSide / h;
    CGSize proxy = CGSizeMake(MAX(1, round(w * k)), MAX(1, round(h * k)));
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = 1; fmt.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:proxy format:fmt];
    UIImage *scaled = [renderer imageWithActions:^(UIGraphicsImageRendererContext *_Nonnull rc) {
        [small drawInRect:CGRectMake(0, 0, proxy.width, proxy.height)];
    }];

    CIImage *ci = [CIImage imageWithCGImage:scaled.CGImage];
    if (!ci) { return scaled; }
    CIImage *clamped = [ci imageByClampingToExtent];                                // 边缘外延，避免模糊后四周发暗/透明
    CIImage *blurred = [clamped imageByApplyingGaussianBlurWithSigma:kIMFrostedBlurSigma];
    CGImageRef cg = [[self ciContext] createCGImage:blurred fromRect:ci.extent];    // 裁回原 extent（clamp 后 extent 为无限）
    if (!cg) { return scaled; }
    UIImage *out = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return out;
}

+ (UIImage *)expiredGlyphImage {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
    UIImage *sym = [UIImage systemImageNamed:@"xmark.octagon.fill" withConfiguration:cfg];
    return [sym imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (UIView *)expiredOverlayWithCaption:(NSString *)caption {
    UIView *v = [UIView new];
    v.userInteractionEnabled = NO; // 终态不重试：点击穿透到底层
    v.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];

    UIImageView *icon = [UIImageView new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [self expiredGlyphImage]; // 与宫格/相册徽章共用同一枚 ⊘
    icon.contentMode = UIViewContentModeCenter;
    [v addSubview:icon];

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = caption.length > 0 ? caption : @"已失效";
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.8;
    [v addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:v.centerYAnchor constant:-8],
        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:4],
        [label.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:v.leadingAnchor constant:6],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:v.trailingAnchor constant:-6],
    ]];
    return v;
}

@end
