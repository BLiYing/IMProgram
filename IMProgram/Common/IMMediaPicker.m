//  IMMediaPicker.m

#import "IMMediaPicker.h"
#import "IMLog.h"
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// 视频不按时长限制（用户拍板），仅保留与服务端一致的 2GB 体积上限。
const long long kIMMaxVideoBytes = 2048LL * 1024 * 1024;

// 相机**现录**的例外：60s。理由见头文件（120s 转码超时 + tmp 体积）；相册选片仍不限时长。
const NSTimeInterval kIMCameraVideoMaxSeconds = 60;

static const CGFloat kIMImageMaxSide = 2048;   // 压缩：长边上限
static const CGFloat kIMImageJPEGQuality = 0.8;

@implementation IMPickedMedia
// data 路径不必逐处赋值：未显式设置时取 data.length（fileURL 路径由构造点写入文件大小）。
- (long long)byteCount { return _byteCount > 0 ? _byteCount : (long long)self.data.length; }
@end

/// 等比降采样（aspect fit，scale=1），控内存；nil/尺寸已小直接原样返回。
static UIImage *IMPickerDownscale(UIImage *src, CGFloat maxSide) {
    if (!src) { return nil; }
    CGFloat w = src.size.width, h = src.size.height;
    CGFloat longSide = MAX(w, h);
    if (longSide <= maxSide || longSide <= 0) { return src; }
    CGFloat k = maxSide / longSide;
    CGSize target = CGSizeMake(round(w * k), round(h * k));
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:target format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [src drawInRect:CGRectMake(0, 0, target.width, target.height)];
    }];
}

/// UIImage 的像素尺寸（size 是点，乘 scale 得像素）。
static CGSize IMPickerPixelSizeOfImage(UIImage *image) {
    if (!image) { return CGSizeZero; }
    CGFloat s = image.scale > 0 ? image.scale : 1;
    return CGSizeMake(round(image.size.width * s), round(image.size.height * s));
}

/// 从图片字节读像素尺寸：只解文件头，不整图解码（原图直传路径没有 UIImage 可用）。
/// EXIF 方向 ≥5 表示旋转 90°，需交换宽高才是**显示尺寸**——否则收端会把竖图当横图排版。
static CGSize IMPickerPixelSizeOfImageData(NSData *data) {
    if (data.length == 0) { return CGSizeZero; }
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) { return CGSizeZero; }
    NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL));
    CFRelease(src);
    CGFloat w = [props[(NSString *)kCGImagePropertyPixelWidth] doubleValue];
    CGFloat h = [props[(NSString *)kCGImagePropertyPixelHeight] doubleValue];
    if (w <= 0 || h <= 0) { return CGSizeZero; }
    NSInteger orientation = [props[(NSString *)kCGImagePropertyOrientation] integerValue];
    return orientation >= 5 ? CGSizeMake(h, w) : CGSizeMake(w, h);
}

/// 读视频轨的显示像素尺寸（含 preferredTransform 旋转）与时长毫秒；读不到则保持零值。
static void IMPickerReadVideoMeta(NSURL *url, CGSize *outSize, int64_t *outMillis) {
    if (!url) { return; }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    Float64 seconds = CMTimeGetSeconds(asset.duration);
    if (outMillis && isfinite(seconds) && seconds > 0) { *outMillis = (int64_t)llround(seconds * 1000); }
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!track || !outSize) { return; }
    CGSize natural = track.naturalSize;
    CGSize shown = CGRectApplyAffineTransform(CGRectMake(0, 0, natural.width, natural.height), track.preferredTransform).size;
    if (shown.width > 0 && shown.height > 0) { *outSize = CGSizeMake(round(fabs(shown.width)), round(fabs(shown.height))); }
}

/// 读视频轨编码的四字符码（avc1=H.264 / hvc1·hev1=HEVC）。空=读不到/无视频轨。
/// **不能靠扩展名判断**：.mov 里可能是 H.264，.mp4 里也可能是 HEVC。
static NSString *IMPickerVideoCodec(NSURL *url) {
    if (!url) { return nil; }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;
    if (!desc) { return nil; }
    FourCharCode code = CMFormatDescriptionGetMediaSubType(desc);
    char chars[5] = { (char)((code >> 24) & 0xFF), (char)((code >> 16) & 0xFF),
                      (char)((code >> 8) & 0xFF), (char)(code & 0xFF), 0 };
    return [NSString stringWithUTF8String:chars];
}

/// HEVC 的两种四字符码。Chrome/Firefox 解不了 → 视频消息必须转成 H.264 才发得出去。
static BOOL IMPickerIsHEVCCodec(NSString *codec) {
    return [codec isEqualToString:@"hvc1"] || [codec isEqualToString:@"hev1"];
}

/// 量不到尺寸/时长 → 收端只能按未知渲染（无时长角标、比例回退）。这是排版问题的源头，必须留痕。
/// 只记元数据（是否视频、字节数、量到的值），不记文件路径与内容。
static void IMPickerLogMediaMeta(BOOL isVideo, NSUInteger bytes, CGSize size, int64_t durationMillis) {
    BOOL sizeKnown = size.width > 0 && size.height > 0;
    BOOL durationKnown = !isVideo || durationMillis > 0;
    if (sizeKnown && durationKnown) {
        IMLogDebugWithTag(IMLogTagMedia, @"media_probe_ok is_video=%d bytes=%lu media_w=%.0f media_h=%.0f duration_ms=%lld",
                          isVideo, (unsigned long)bytes, size.width, size.height, durationMillis);
        return;
    }
    IMLogWarnWithTag(IMLogTagMedia, @"media_probe_incomplete is_video=%d bytes=%lu media_w=%.0f media_h=%.0f duration_ms=%lld",
                     isVideo, (unsigned long)bytes, size.width, size.height, durationMillis);
}

#pragma mark - 惰性句柄

@interface IMPickedMediaHandle ()
- (instancetype)initWithProvider:(NSItemProvider *)ip isVideo:(BOOL)isVideo original:(BOOL)original;
- (instancetype)initWithLocalVideoURL:(NSURL *)url;
@end

@implementation IMPickedMediaHandle {
    NSItemProvider  *_ip;          // 相册句柄的来源；**本地文件句柄（相机录制）为 nil**
    BOOL             _original;
    dispatch_queue_t _work;        // 串行：loadThumbnail 与 loadData 互斥（共享视频临时文件）
    NSURL           *_videoTmpURL; // 视频已拷贝的临时文件（缩略图先拷则 loadData 复用，避免二次拷贝）
    NSString        *_videoExt;
    BOOL             _ownsSourceFile; // 本地文件句柄：文件所有权在本对象，未消费就释放要负责删
}

- (instancetype)initWithProvider:(NSItemProvider *)ip isVideo:(BOOL)isVideo original:(BOOL)original {
    self = [super init];
    if (self) {
        _ip = ip;
        _isVideo = isVideo;
        _original = original;
        _work = dispatch_queue_create("im.media.handle", DISPATCH_QUEUE_SERIAL);
        _videoExt = @"mp4";
    }
    return self;
}

/// 相机录制产物：文件已经在我们自己的 tmp 里，直接坐进 _videoTmpURL——ensureVideoTmpURL 是
/// 「已设则直接返回」，于是 buildVideoItemWithProgress 一行不改就能跑，还省掉一次整文件拷贝
/// （60s 1080p ≈130MB，那一次拷贝是实打实的磁盘与秒数）。
/// _ip 为 nil 是这条路径的**唯一**分叉点，凡是碰 _ip 的方法都必须有回落（见下方三处）。
- (instancetype)initWithLocalVideoURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _ip = nil;
        _isVideo = YES;
        _original = NO; // 一律转 720p H.264：相机在「高效」格式下录的是 HEVC，收端 Web 播不了
        _work = dispatch_queue_create("im.media.handle", DISPATCH_QUEUE_SERIAL);
        _videoTmpURL = url;
        _videoExt = url.pathExtension.lowercaseString.length ? url.pathExtension.lowercaseString : @"mov";
        _ownsSourceFile = YES;
    }
    return self;
}

/// 句柄没走到 loadData 就被释放（用户在转码前就取消了那条乐观气泡）时，录制原件会永久留在 tmp。
/// buildVideoItemWithProgress 移交所有权后会把 _videoTmpURL 置 nil，故这里不会误删已消费的文件。
- (void)dealloc {
    if (_ownsSourceFile && _videoTmpURL) {
        [[NSFileManager defaultManager] removeItemAtURL:_videoTmpURL error:NULL];
    }
}

- (void)loadThumbnail:(void (^)(UIImage *_Nullable))completion {
    // 本地文件句柄没有 _ip：给 nil 发 loadPreviewImageWithOptions: 是直接返回，**completion 永远不会被调用**，
    // 气泡缩略图就会永久空白。本地文件抽帧本来也很快（不用等相册导出），直接走慢路径。
    if (self.isVideo && !_ip) { [self loadThumbnailByExtractingFrame:completion]; return; }
    if (self.isVideo) {
        // 快路径：系统预览图**毫秒级**返回，不需要先把整个视频从相册拷出来。
        // 走 _work 队列的抽帧路径要等 ensureVideoTmpURL 拷完 70MB（真机实测 ~28s），
        // 用户在这段时间只能看着空白方块——正是"选完视频缩略图空白+后续跳动"的根因。
        CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
        [_ip loadPreviewImageWithOptions:@{} completionHandler:^(__kindof id<NSSecureCoding> item, NSError *error) {
            UIImage *preview = [item isKindOfClass:UIImage.class] ? (UIImage *)item
                             : ([item isKindOfClass:NSData.class] ? [UIImage imageWithData:(NSData *)item] : nil);
            double ms = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000;
            if (preview) {
                IMLogDebugWithTag(IMLogTagMedia, @"video_thumb_preview_ok ms=%.0f size=%.0fx%.0f",
                                  ms, preview.size.width, preview.size.height);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(IMPickerDownscale(preview, 600)); });
            } else {
                // 慢路径 = 要等整个视频从相册拷出再抽帧，期间气泡只能显示占位——这条 WARN 就是"空白几秒"的实锤。
                IMLogWarnWithTag(IMLogTagMedia, @"video_thumb_preview_miss ms=%.0f item=%@ error=%@ fallback=frame_extract",
                                 ms, item ? NSStringFromClass([item class]) : @"nil", error.localizedDescription ?: @"-");
                [self loadThumbnailByExtractingFrame:completion];
            }
        }];
        return;
    }
    dispatch_async(_work, ^{
        UIImage *thumb = IMPickerDownscale([self loadUIImage], 600);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(thumb); });
    });
}

/// 慢路径兜底：等视频临时文件就绪后抽首帧（与 loadData 共享 _work 串行队列与 tmp 文件）。
- (void)loadThumbnailByExtractingFrame:(void (^)(UIImage *_Nullable))completion {
    CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
    dispatch_async(_work, ^{
        UIImage *thumb = nil;
        NSURL *url = [self ensureVideoTmpURL];
        IMLogWithTag(IMLogTagMedia, @"video_thumb_frame_extract copy_wait_ms=%.0f has_file=%d",
                     (CFAbsoluteTimeGetCurrent() - startedAt) * 1000, url != nil);
        if (url) {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
            AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
            gen.appliesPreferredTrackTransform = YES;
            gen.maximumSize = CGSizeMake(600, 600);
            CGImageRef cg = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.1, 600) actualTime:NULL error:NULL];
            if (cg) { thumb = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(thumb); });
    });
}

- (void)loadData:(void (^)(IMPickedMedia *_Nullable))completion {
    [self loadData:completion progress:nil];
}

- (void)loadData:(void (^)(IMPickedMedia *_Nullable))completion progress:(void (^)(double))progress {
    dispatch_async(_work, ^{
        IMPickedMedia *item = self.isVideo ? [self buildVideoItemWithProgress:progress] : [self buildImageItem];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(item); });
    });
}

/// 文件面板路径的原始资源类型（视频=Movie / 图片=Image 的首个可用 identifier）；nil=拿不到。
- (NSString *)fileTypeIdentifier {
    for (NSString *candidate in _ip.registeredTypeIdentifiers) {
        UTType *type = [UTType typeWithIdentifier:candidate];
        if ((self.isVideo && [type conformsToType:UTTypeMovie]) ||
            (!self.isVideo && [type conformsToType:UTTypeImage])) {
            return candidate;
        }
    }
    return nil;
}

- (NSString *)suggestedFileName {
    // 本地文件句柄：没有 _ip 可问，名字按暂存文件的扩展名来（最终产物名仍由 buildVideoItem 定）。
    if (!_ip) {
        NSString *ext = _videoExt.length ? _videoExt : (self.isVideo ? @"mov" : @"jpg");
        return [@"video" stringByAppendingPathExtension:ext] ?: @"video.mov";
    }
    NSString *typeID = [self fileTypeIdentifier];
    UTType *type = typeID.length > 0 ? [UTType typeWithIdentifier:typeID] : nil;
    NSString *ext = type.preferredFilenameExtension ?: (self.isVideo ? @"mov" : @"jpg");
    NSString *name = _ip.suggestedName;
    if (name.length == 0) { name = self.isVideo ? @"video" : @"photo"; }
    if (name.pathExtension.length == 0) { name = [name stringByAppendingPathExtension:ext] ?: name; }
    return name;
}

- (void)loadFileURL:(void (^)(IMPickedMedia *_Nullable))completion {
    if (!completion) { return; }
    dispatch_async(_work, ^{
        // 本地文件句柄（相机录制）：文件已在手上，直接移交，不必走相册导出。
        // 相机路径当前不用这个方法（走 loadData 转码），但留空洞会在将来"相机录像当文件发"时静默返回 nil。
        if (!self->_ip) {
            IMPickedMedia *local = [self buildLocalFileItem];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(local); });
            return;
        }
        IMPickedMedia *item = nil;
        NSString *typeID = [self fileTypeIdentifier];
        if (typeID.length > 0) {
            NSString *ext = nil;
            // 2GB 级原件从相册导出（iCloud 资产还要先下载）远超默认 60s，放宽到 10 分钟；超时按失败处理可重试。
            NSURL *url = [self copyFileForType:typeID outExt:&ext timeoutSeconds:600];
            int64_t size = url ? (int64_t)[[[NSFileManager defaultManager] attributesOfItemAtPath:url.path
                                                                                            error:NULL][NSFileSize] unsignedLongLongValue] : 0;
            if (url && size > 0) {
                UTType *type = [UTType typeWithIdentifier:typeID];
                NSString *name = [self suggestedFileName];
                // 扩展名以导出产物为准：suggestedName 的扩展可能与实际资源不符（如 HEIC/MOV 变体）。
                if (ext.length > 0 && ![name.pathExtension.lowercaseString isEqualToString:ext]) {
                    name = [[name stringByDeletingPathExtension] stringByAppendingPathExtension:ext] ?: name;
                }
                item = [IMPickedMedia new];
                item.fileURL = url;
                item.byteCount = size;
                item.fileName = name;
                item.mimeType = type.preferredMIMEType ?: @"application/octet-stream";
                item.isVideo = self.isVideo;
            } else if (url) {
                [[NSFileManager defaultManager] removeItemAtURL:url error:NULL]; // 空文件视为失败，清掉残件
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(item); });
    });
}

/// 本地文件句柄的「原件直发」产物（在 _work 串行队列上执行）：不转码不压缩，
/// 文件所有权随 fileURL 移交调用方（置空 _videoTmpURL，dealloc 不再兜底删）。
- (IMPickedMedia *)buildLocalFileItem {
    NSURL *url = _videoTmpURL;
    if (!url) { return nil; }
    int64_t size = (int64_t)[[[NSFileManager defaultManager] attributesOfItemAtPath:url.path
                                                                             error:NULL][NSFileSize] unsignedLongLongValue];
    if (size <= 0 || size > kIMMaxVideoBytes) { return nil; }
    CGSize pixelSize = CGSizeZero;
    int64_t durationMillis = 0;
    IMPickerReadVideoMeta(url, &pixelSize, &durationMillis);
    IMPickedMedia *m = [IMPickedMedia new];
    m.fileURL = url;
    m.byteCount = size;
    m.fileName = [self suggestedFileName];
    m.mimeType = [_videoExt isEqualToString:@"mov"] ? @"video/quicktime" : @"video/mp4";
    m.isVideo = YES;
    m.pixelSize = pixelSize;
    m.durationMillis = durationMillis;
    m.videoCodec = IMPickerVideoCodec(url);
    _videoTmpURL = nil;
    _ownsSourceFile = NO;
    return m;
}

#pragma mark 图片（在 _work 串行队列上执行）

- (IMPickedMedia *)buildImageItem {
    if (_original) {
        // 原图：拿原始文件字节（保留 HEIC/PNG 原格式与元数据）。
        NSData *raw = [self loadFileDataForType:UTTypeImage.identifier outExt:NULL];
        if (raw) {
            NSString *ext = @"jpg";
            if ([_ip hasItemConformingToTypeIdentifier:UTTypePNG.identifier]) { ext = @"png"; }
            else if ([_ip hasItemConformingToTypeIdentifier:UTTypeHEIC.identifier]) { ext = @"heic"; }
            IMPickedMedia *m = [IMPickedMedia new];
            m.data = raw;
            m.fileName = [@"photo." stringByAppendingString:ext];
            m.mimeType = [ext isEqualToString:@"png"] ? @"image/png"
                       : [ext isEqualToString:@"heic"] ? @"image/heic" : @"image/jpeg";
            m.isVideo = NO;
            m.pixelSize = IMPickerPixelSizeOfImageData(raw); // 原图直传：从文件头取尺寸，不整图解码
            IMPickerLogMediaMeta(NO, raw.length, m.pixelSize, 0);
            return m;
        } // 拿不到原始文件 → 回落压缩路径
    }
    UIImage *image = [self loadUIImage];
    if (!image) { return nil; }
    UIImage *scaled = IMPickerDownscale(image, kIMImageMaxSide);
    NSData *jpeg = UIImageJPEGRepresentation(scaled, kIMImageJPEGQuality);
    if (jpeg.length == 0) { return nil; }
    IMPickedMedia *m = [IMPickedMedia new];
    m.data = jpeg;
    m.fileName = @"photo.jpg";
    m.mimeType = @"image/jpeg";
    m.isVideo = NO;
    m.pixelSize = IMPickerPixelSizeOfImage(scaled); // 上报**压缩后**尺寸（收端拿到的就是这张）
    IMPickerLogMediaMeta(NO, jpeg.length, m.pixelSize, 0);
    return m;
}

- (UIImage *)loadUIImage {
    if (![_ip canLoadObjectOfClass:UIImage.class]) { return nil; }
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block UIImage *out = nil;
    [_ip loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        if ([object isKindOfClass:UIImage.class]) { out = (UIImage *)object; }
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)));
    return out;
}

#pragma mark 视频（在 _work 串行队列上执行）

/// 视频临时文件只拷一次（缩略图/转码共用）；nil=拷贝失败。
- (NSURL *)ensureVideoTmpURL {
    if (_videoTmpURL) { return _videoTmpURL; }
    NSString *ext = @"mp4";
    _videoTmpURL = [self copyFileForType:UTTypeMovie.identifier outExt:&ext];
    _videoExt = ext ?: @"mp4";
    return _videoTmpURL;
}

/// 返回 nil = 加载失败或超 2GB。
///
/// **视频消息一律保证可播**（IM 通行做法，静默转码，不问用户）：
///   - 「发送」：转 720p H.264 MP4（同时压体积）。
///   - 「发送原视频」：源已是 H.264 → 直传不动；源是 HEVC → 转 H.264 MP4 但**保持原分辨率**
///     （HighestQuality），只换编码不降画质——否则 Chrome/Firefox 收到只能看封面、点开播不了。
///   - 需要原封不动的原始文件时走**文件消息**（那条路径本就不转码）。
///
/// 转码失败回落原文件（宁可发出去也不失败），但会留痕；产物编码也会打日志核对。
- (IMPickedMedia *)buildVideoItemWithProgress:(void (^)(double))progress {
    NSURL *tmpURL = [self ensureVideoTmpURL];
    if (!tmpURL) { return nil; }
    NSString *sourceCodec = IMPickerVideoCodec(tmpURL);
    NSString *preset = _original ? AVAssetExportPresetHighestQuality : AVAssetExportPreset1280x720;
    BOOL needsTranscode = !_original || IMPickerIsHEVCCodec(sourceCodec);

    NSString *ext = _videoExt;
    NSURL *finalURL = tmpURL;
    if (needsTranscode) {
        NSURL *outURL = [self exportVideoAtURL:tmpURL preset:preset progress:progress];
        if (outURL) {
            ext = @"mp4";
            finalURL = outURL;
        }
        // 导出失败：finalURL 保持 tmpURL，回落原文件（服务端仍有 2GB 兜底）。
    } else {
        IMLogDebugWithTag(IMLogTagMedia, @"video_transcode_skipped codec=%@ reason=already_h264", sourceCodec);
    }

    CGSize pixelSize = CGSizeZero;
    int64_t durationMillis = 0;
    IMPickerReadVideoMeta(finalURL, &pixelSize, &durationMillis); // 量**最终产物**（收端拿到的就是这份）
    NSString *outCodec = IMPickerVideoCodec(finalURL);
    // 产物留在磁盘、所有权移交给 IMPickedMedia（fileURL）——上限 2GB 后绝不能读进 NSData。
    // 只清理不再需要的那份：转码成功时删原件；产物本身由取用方（发送服务落盘后）删除。
    if (![finalURL isEqual:tmpURL]) { [[NSFileManager defaultManager] removeItemAtURL:tmpURL error:NULL]; }
    _videoTmpURL = nil;
    long long byteCount = (long long)[[[NSFileManager defaultManager]
        attributesOfItemAtPath:finalURL.path error:NULL][NSFileSize] unsignedLongLongValue];
    if (byteCount <= 0 || byteCount > kIMMaxVideoBytes) {
        [[NSFileManager defaultManager] removeItemAtURL:finalURL error:NULL];
        return nil; // 读不到/超 2GB：剔除（调用方标"失败"）
    }

    // 产物编码不信文档只信实测：仍是 HEVC 说明预设选错，收端照样播不了，必须能一眼看出来。
    if (IMPickerIsHEVCCodec(outCodec)) {
        IMLogWarnWithTag(IMLogTagMedia, @"video_still_hevc_after_transcode source_codec=%@ out_codec=%@ preset=%@ bytes=%lld",
                         sourceCodec, outCodec, preset, byteCount);
    } else {
        IMLogDebugWithTag(IMLogTagMedia, @"video_ready source_codec=%@ out_codec=%@ transcoded=%d bytes=%lld",
                          sourceCodec, outCodec, needsTranscode, byteCount);
    }

    IMPickedMedia *m = [IMPickedMedia new];
    m.fileURL = finalURL;
    m.byteCount = byteCount;
    m.fileName = [@"video." stringByAppendingString:ext];
    m.mimeType = [ext isEqualToString:@"mov"] ? @"video/quicktime" : @"video/mp4";
    m.isVideo = YES;
    m.pixelSize = pixelSize;
    m.durationMillis = durationMillis;
    m.videoCodec = outCodec;
    IMPickerLogMediaMeta(YES, (NSUInteger)byteCount, pixelSize, durationMillis);
    return m;
}

/// 同步导出（本方法只在 _work 串行队列调用）：轮询 export.progress 把转码进度回给调用方。
/// 返回 nil = 导出失败/超时，调用方回落原文件。
- (NSURL *)exportVideoAtURL:(NSURL *)sourceURL preset:(NSString *)preset progress:(void (^)(double))progress {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    NSURL *outURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                     [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"mp4"]]];
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!export) {
        IMLogWarnWithTag(IMLogTagMedia, @"video_transcode_failed reason=export_session_unavailable preset=%@", preset);
        return nil;
    }
    export.outputURL = outURL;
    export.outputFileType = AVFileTypeMPEG4;
    export.shouldOptimizeForNetworkUse = YES;

    // AVAssetExportSession.progress 不支持 KVO，轮询是标准做法；0.25s 足够顺滑又不空转。
    dispatch_source_t ticker = nil;
    if (progress) {
        ticker = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(ticker, dispatch_time(DISPATCH_TIME_NOW, 0), 250 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(ticker, ^{ progress(MIN(1.0, MAX(0.0, (double)export.progress))); });
        dispatch_resume(ticker);
    }
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [export exportAsynchronouslyWithCompletionHandler:^{ dispatch_semaphore_signal(sem); }];
    long timedOut = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_SEC)));
    if (ticker) { dispatch_source_cancel(ticker); }

    if (timedOut != 0) {
        IMLogWarnWithTag(IMLogTagMedia, @"video_transcode_failed reason=timeout preset=%@ timeout_s=120", preset);
        [export cancelExport];
        // 取消是异步的，等一小会儿再删，否则可能删在导出线程仍在写的文件上；不删则会在 tmp 里
        // 留下几十 MB 的半成品（status 失败分支是删了的，这里漏删属实现不一致）。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [[NSFileManager defaultManager] removeItemAtURL:outURL error:NULL];
        });
        return nil;
    }
    if (export.status != AVAssetExportSessionStatusCompleted) {
        // 回落=发出去的仍是原编码（可能 HEVC），收端可能播不了 → 用户无感，只能靠这条日志定位。
        IMLogWarnWithTag(IMLogTagMedia, @"video_transcode_failed reason=status status=%ld preset=%@ error=%@",
                         (long)export.status, preset, export.error.localizedDescription ?: @"(nil)");
        [[NSFileManager defaultManager] removeItemAtURL:outURL error:NULL];
        return nil;
    }
    if (progress) { dispatch_async(dispatch_get_main_queue(), ^{ progress(1.0); }); }
    return outURL;
}

#pragma mark 文件加载辅助（同步封装，仅在 _work 队列上调用）

/// loadFileRepresentation 的同步封装：把 provider 的文件拷到临时目录（provider 的 URL 回调后即失效，必须拷贝）。
- (NSURL *)copyFileForType:(NSString *)typeID outExt:(NSString **)outExt {
    return [self copyFileForType:typeID outExt:outExt timeoutSeconds:60];
}

- (NSURL *)copyFileForType:(NSString *)typeID outExt:(NSString **)outExt timeoutSeconds:(int64_t)timeoutSeconds {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSURL *copied = nil;
    __block NSString *ext = nil;
    [_ip loadFileRepresentationForTypeIdentifier:typeID completionHandler:^(NSURL *url, NSError *error) {
        if (url) {
            ext = url.pathExtension.lowercaseString;
            NSString *dst = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [[NSUUID UUID].UUIDString stringByAppendingPathExtension:(ext.length ? ext : @"bin")]];
            if ([[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:dst] error:NULL]) {
                copied = [NSURL fileURLWithPath:dst];
            }
        }
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC)));
    if (outExt && ext.length) { *outExt = ext; }
    return copied;
}

- (NSData *)loadFileDataForType:(NSString *)typeID outExt:(NSString **)outExt {
    NSURL *url = [self copyFileForType:typeID outExt:outExt];
    if (!url) { return nil; }
    NSData *d = [NSData dataWithContentsOfURL:url];
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    return d;
}

@end

#pragma mark - 选择器（present + 原图选择 + 立即回调句柄）

@interface IMMediaPicker () <PHPickerViewControllerDelegate>
@end

@implementation IMMediaPicker {
    __weak UIViewController *_host;
    void (^_completion)(NSArray<IMPickedMediaHandle *> *);
    NSArray<PHPickerResult *> *_results;
    BOOL _imagesOnly;       // 仅图片（头像场景）
    BOOL _skipSendPrompt;   // 选完不弹「发送 / 原图」，直接压缩回调
}

static IMMediaPicker *gActivePicker; // 会话期间自持有（PHPicker delegate 是弱引用）

+ (void)presentFromViewController:(UIViewController *)host
                            limit:(NSInteger)limit
                handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *))completion {
    [self presentFromViewController:host limit:limit imagesOnly:NO skipSendPrompt:NO preferCurrentRepresentation:NO handlesCompletion:completion];
}

+ (void)presentImagePickerFromViewController:(UIViewController *)host
                                       limit:(NSInteger)limit
                           handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *))completion {
    [self presentFromViewController:host limit:limit imagesOnly:YES skipSendPrompt:YES preferCurrentRepresentation:NO handlesCompletion:completion];
}

+ (void)presentFilePickerFromViewController:(UIViewController *)host
                                      limit:(NSInteger)limit
                          handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *))completion {
    [self presentFromViewController:host limit:limit imagesOnly:NO skipSendPrompt:YES preferCurrentRepresentation:YES handlesCompletion:completion];
}

+ (void)presentFromViewController:(UIViewController *)host
                            limit:(NSInteger)limit
                       imagesOnly:(BOOL)imagesOnly
                   skipSendPrompt:(BOOL)skipSendPrompt
      preferCurrentRepresentation:(BOOL)preferCurrentRepresentation
                handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *))completion {
    IMMediaPicker *p = [IMMediaPicker new];
    p->_host = host;
    p->_completion = [completion copy];
    p->_imagesOnly = imagesOnly;
    p->_skipSendPrompt = skipSendPrompt;
    gActivePicker = p;

    PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init]; // 不带 photoLibrary：免相册权限（进程外选择器）
    cfg.selectionLimit = limit;
    if (preferCurrentRepresentation) {
        cfg.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    }
    cfg.filter = imagesOnly
        ? PHPickerFilter.imagesFilter // 头像：仅图片，视频不可见
        : [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter,
                                                        PHPickerFilter.livePhotosFilter,
                                                        PHPickerFilter.videosFilter]];
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    picker.delegate = p;
    [host presentViewController:picker animated:YES completion:nil];
}

- (void)finishWithHandles:(NSArray<IMPickedMediaHandle *> *)handles {
    void (^cb)(NSArray<IMPickedMediaHandle *> *) = _completion;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (cb) { cb(handles ?: @[]); }
        gActivePicker = nil; // 会话结束，释放自持有
    });
}

#pragma mark PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) { [self finishWithHandles:@[]]; return; }
    _results = results;

    // 头像等单图场景：不弹「发送 / 原图」，直接压缩回调（选一张即完成设置）。
    if (_skipSendPrompt) { [self buildHandlesOriginal:NO]; return; }

    // 微信式「原图」选择：PHPicker 无内置勾选，选完后弹一次（对全部所选生效）。
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
        message:[NSString stringWithFormat:@"已选 %lu 项", (unsigned long)results.count]
        preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) ws = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [ws buildHandlesOriginal:NO];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"发送原图/原视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [ws buildHandlesOriginal:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        [ws finishWithHandles:@[]];
    }]];
    UIViewController *host = _host;
    sheet.popoverPresentationController.sourceView = host.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds), CGRectGetMaxY(host.view.bounds) - 60, 1, 1);
    [host presentViewController:sheet animated:YES completion:nil];
}

#pragma mark 相机

+ (void)configureCameraPicker:(nullable UIImagePickerController *)picker {
    if (!picker) { return; }
    picker.mediaTypes = @[UTTypeImage.identifier, UTTypeMovie.identifier]; // 系统相机底部自带「照片/视频」切换
    picker.videoMaximumDuration = kIMCameraVideoMaxSeconds;                 // 到点自动停止并进预览页
    picker.videoQuality = UIImagePickerControllerQualityTypeHigh;           // 取设备默认；理由见头文件
}

+ (nullable IMPickedMediaHandle *)handleForRecordedVideoAtURL:(nullable NSURL *)url {
    if (![url isKindOfClass:NSURL.class] || url.path.length == 0) { return nil; }
    NSNumber *size = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:NULL][NSFileSize];
    if (size.longLongValue <= 0) {
        IMLogWarnWithTag(IMLogTagMedia, @"camera_video_missing path_ext=%@", url.pathExtension ?: @"-");
        return nil; // 文件不存在/空件：调用方提示失败，不要造一条永远发不出去的空气泡
    }
    IMLogDebugWithTag(IMLogTagMedia, @"camera_video_captured bytes=%lld ext=%@",
                      size.longLongValue, url.pathExtension ?: @"-");
    return [[IMPickedMediaHandle alloc] initWithLocalVideoURL:url];
}

/// 秒回调：只包一层惰性句柄，不做任何解码/压缩/转码（那些在句柄 loadData 时逐项进行）。
- (void)buildHandlesOriginal:(BOOL)original {
    NSMutableArray<IMPickedMediaHandle *> *handles = [NSMutableArray arrayWithCapacity:_results.count];
    for (PHPickerResult *r in _results) {
        NSItemProvider *ip = r.itemProvider;
        BOOL isVideo = [ip hasItemConformingToTypeIdentifier:UTTypeMovie.identifier];
        [handles addObject:[[IMPickedMediaHandle alloc] initWithProvider:ip isVideo:isVideo original:original]];
    }
    [self finishWithHandles:handles];
}

@end
