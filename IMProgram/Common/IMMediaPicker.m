//  IMMediaPicker.m

#import "IMMediaPicker.h"
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// 视频不按时长限制（用户拍板），仅保留与服务端一致的 100MB 体积上限。
const long long kIMMaxVideoBytes = 100LL * 1024 * 1024;

static const CGFloat kIMImageMaxSide = 2048;   // 压缩：长边上限
static const CGFloat kIMImageJPEGQuality = 0.8;

@implementation IMPickedMedia
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

#pragma mark - 惰性句柄

@interface IMPickedMediaHandle ()
- (instancetype)initWithProvider:(NSItemProvider *)ip isVideo:(BOOL)isVideo original:(BOOL)original;
@end

@implementation IMPickedMediaHandle {
    NSItemProvider  *_ip;
    BOOL             _original;
    dispatch_queue_t _work;        // 串行：loadThumbnail 与 loadData 互斥（共享视频临时文件）
    NSURL           *_videoTmpURL; // 视频已拷贝的临时文件（缩略图先拷则 loadData 复用，避免二次拷贝）
    NSString        *_videoExt;
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

- (void)loadThumbnail:(void (^)(UIImage *_Nullable))completion {
    dispatch_async(_work, ^{
        UIImage *thumb = nil;
        if (self.isVideo) {
            NSURL *url = [self ensureVideoTmpURL];
            if (url) {
                AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
                AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
                gen.appliesPreferredTrackTransform = YES;
                gen.maximumSize = CGSizeMake(600, 600);
                CGImageRef cg = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.1, 600) actualTime:NULL error:NULL];
                if (cg) { thumb = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
            }
        } else {
            thumb = IMPickerDownscale([self loadUIImage], 600);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(thumb); });
    });
}

- (void)loadData:(void (^)(IMPickedMedia *_Nullable))completion {
    dispatch_async(_work, ^{
        IMPickedMedia *item = self.isVideo ? [self buildVideoItem] : [self buildImageItem];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(item); });
    });
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
            return m;
        } // 拿不到原始文件 → 回落压缩路径
    }
    UIImage *image = [self loadUIImage];
    if (!image) { return nil; }
    NSData *jpeg = UIImageJPEGRepresentation(IMPickerDownscale(image, kIMImageMaxSide), kIMImageJPEGQuality);
    if (jpeg.length == 0) { return nil; }
    IMPickedMedia *m = [IMPickedMedia new];
    m.data = jpeg;
    m.fileName = @"photo.jpg";
    m.mimeType = @"image/jpeg";
    m.isVideo = NO;
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

/// 返回 nil = 加载失败或超 100MB。original=YES 直传原文件；否则转码 720p mp4（失败回落原文件）。
- (IMPickedMedia *)buildVideoItem {
    NSURL *tmpURL = [self ensureVideoTmpURL];
    if (!tmpURL) { return nil; }
    NSString *ext = _videoExt;
    NSData *raw = nil;
    if (_original) {
        raw = [NSData dataWithContentsOfURL:tmpURL];
    } else {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:tmpURL options:nil];
        NSURL *outURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                         [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"mp4"]]];
        AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:asset
                                                                        presetName:AVAssetExportPreset1280x720];
        export.outputURL = outURL;
        export.outputFileType = AVFileTypeMPEG4;
        export.shouldOptimizeForNetworkUse = YES;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [export exportAsynchronouslyWithCompletionHandler:^{ dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_SEC)));
        if (export.status == AVAssetExportSessionStatusCompleted) {
            raw = [NSData dataWithContentsOfURL:outURL];
            ext = @"mp4";
            [[NSFileManager defaultManager] removeItemAtURL:outURL error:NULL];
        } else {
            raw = [NSData dataWithContentsOfURL:tmpURL]; // 转码失败 → 回落原文件（服务端仍有 100MB 兜底）
        }
    }
    [[NSFileManager defaultManager] removeItemAtURL:tmpURL error:NULL];
    _videoTmpURL = nil;
    if (raw.length == 0) { return nil; }
    if ((long long)raw.length > kIMMaxVideoBytes) { return nil; } // 超 100MB：剔除（调用方标"失败"）

    IMPickedMedia *m = [IMPickedMedia new];
    m.data = raw;
    m.fileName = [@"video." stringByAppendingString:ext];
    m.mimeType = [ext isEqualToString:@"mov"] ? @"video/quicktime" : @"video/mp4";
    m.isVideo = YES;
    return m;
}

#pragma mark 文件加载辅助（同步封装，仅在 _work 队列上调用）

/// loadFileRepresentation 的同步封装：把 provider 的文件拷到临时目录（provider 的 URL 回调后即失效，必须拷贝）。
- (NSURL *)copyFileForType:(NSString *)typeID outExt:(NSString **)outExt {
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
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)));
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
    [self presentFromViewController:host limit:limit imagesOnly:NO skipSendPrompt:NO handlesCompletion:completion];
}

+ (void)presentImagePickerFromViewController:(UIViewController *)host
                                       limit:(NSInteger)limit
                           handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *))completion {
    [self presentFromViewController:host limit:limit imagesOnly:YES skipSendPrompt:YES handlesCompletion:completion];
}

+ (void)presentFromViewController:(UIViewController *)host
                            limit:(NSInteger)limit
                       imagesOnly:(BOOL)imagesOnly
                   skipSendPrompt:(BOOL)skipSendPrompt
                handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *))completion {
    IMMediaPicker *p = [IMMediaPicker new];
    p->_host = host;
    p->_completion = [completion copy];
    p->_imagesOnly = imagesOnly;
    p->_skipSendPrompt = skipSendPrompt;
    gActivePicker = p;

    PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init]; // 不带 photoLibrary：免相册权限（进程外选择器）
    cfg.selectionLimit = limit;
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
