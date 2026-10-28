//  IMExportDownloader.m

#import "IMExportDownloader.h"
#import "IMLog.h"

NSErrorDomain const IMExportDownloadErrorDomain = @"IMExportDownloadErrorDomain";

static NSTimeInterval const kProgressMinInterval = 0.1;
static NSArray<Class> *sTestProtocolClasses;

BOOL IMExportDownloadShouldEmitProgress(NSTimeInterval lastEmit, NSTimeInterval now,
                                        int64_t lastBytes, int64_t bytes, int64_t expected) {
    if (lastEmit < 0) { return YES; }
    if (expected > 0 && bytes >= expected) { return YES; }
    if (now - lastEmit >= kProgressMinInterval) { return YES; }
    return expected > 0 && (bytes - lastBytes) * 100 >= expected;
}

#pragma mark - 单次下载的会话代理

/// 每次下载一个独立 session + 代理（session 强持代理，finish 后 invalidate 解环）。
@interface IMExportDownloadJob : NSObject <NSURLSessionDownloadDelegate>
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy, nullable) IMExportDownloadProgress progress;
@property (nonatomic, copy) void (^completion)(NSURL *_Nullable, NSError *_Nullable);
@property (nonatomic, assign) BOOL finished;                  // 仅主线程读写
@property (nonatomic, assign) NSTimeInterval lastEmit;        // 仅代理队列
@property (nonatomic, assign) int64_t lastBytes;
@property (nonatomic, strong, nullable) NSURL *resultFile;    // 仅代理队列
@property (nonatomic, strong, nullable) NSError *resultError;
@end

@implementation IMExportDownloadJob

- (instancetype)init {
    if ((self = [super init])) { _lastEmit = -1; }
    return self;
}

static NSError *ExportError(NSInteger code, NSError *underlying) {
    NSDictionary *info = underlying ? @{ NSUnderlyingErrorKey: underlying } : nil;
    return [NSError errorWithDomain:IMExportDownloadErrorDomain code:code userInfo:info];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task
      didWriteData:(int64_t)n totalBytesWritten:(int64_t)written totalBytesExpectedToWrite:(int64_t)expected {
    IMExportDownloadProgress cb = self.progress;
    if (!cb) { return; }
    if (expected <= 0) { expected = -1; }
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (!IMExportDownloadShouldEmitProgress(self.lastEmit, now, self.lastBytes, written, expected)) { return; }
    self.lastEmit = now; self.lastBytes = written;
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self.finished) { cb(written, expected); } });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)tmp {
    NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)task.response statusCode] : 0;
    if (status != 200 && status != 206) {
        IMLogErrorWithTag(IMLogTagHTTP, @"export_download http_status=%ld", (long)status);
        self.resultError = ExportError(status > 0 ? status : -1, nil);
        return;
    }
    // 临时文件在本回调返回后即被系统删除，必须在这里同步搬走。
    NSURL *dest = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:self.fileName]];
    NSError *moveErr = nil;
    [NSFileManager.defaultManager removeItemAtURL:dest error:NULL];
    if (![NSFileManager.defaultManager moveItemAtURL:tmp toURL:dest error:&moveErr]) {
        IMLogErrorWithTag(IMLogTagHTTP, @"export_download move failed code=%ld", (long)moveErr.code);
        self.resultError = ExportError(-2, moveErr);
        return;
    }
    self.resultFile = dest;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSURL *file = self.resultFile;
    NSError *err = self.resultError;
    if (error) {
        IMLogErrorWithTag(IMLogTagHTTP, @"export_download failed domain=%@ code=%ld", error.domain, (long)error.code);
        BOOL cancelled = [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled;
        err = cancelled ? error : ExportError(-1, error);
        file = nil;
    } else if (!file && !err) {
        err = ExportError(-1, nil);
    }
    if (file) { IMLogWithTag(IMLogTagHTTP, @"export_download ok"); }
    [session finishTasksAndInvalidate];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.finished = YES;
        self.progress = nil;
        self.completion(file, err);
    });
}

@end

#pragma mark - 入口

@implementation IMExportDownloader

+ (void)setProtocolClassesForTesting:(NSArray<Class> *)classes { sTestProtocolClasses = [classes copy]; }

+ (NSURLSessionDownloadTask *)downloadFromURL:(NSURL *)url fileName:(NSString *)fileName
                                   completion:(void (^)(NSURL *, NSError *))completion {
    return [self downloadFromURL:url fileName:fileName progress:nil completion:completion];
}

+ (NSURLSessionDownloadTask *)downloadFromURL:(NSURL *)url fileName:(NSString *)fileName
                                     progress:(IMExportDownloadProgress)progress
                                   completion:(void (^)(NSURL *, NSError *))completion {
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.defaultSessionConfiguration;
    cfg.timeoutIntervalForRequest = 30;        // 空闲超时：30s 没有字节才算断
    cfg.timeoutIntervalForResource = 60 * 60;  // 整单上限 1h（弱网大文件）
    if (sTestProtocolClasses) { cfg.protocolClasses = sTestProtocolClasses; }
    IMExportDownloadJob *job = [IMExportDownloadJob new];
    job.fileName = fileName; job.progress = progress; job.completion = completion;
    NSOperationQueue *q = [NSOperationQueue new];
    q.maxConcurrentOperationCount = 1;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:job delegateQueue:q];
    NSURLSessionDownloadTask *task = [session downloadTaskWithURL:url];
    [task resume];
    return task;
}

@end
