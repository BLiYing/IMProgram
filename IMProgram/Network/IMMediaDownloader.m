//  IMMediaDownloader.m

#import "IMMediaDownloader.h"
#import "IMLog.h"
#import <objc/runtime.h>

/// 会话数据任务 → 我方任务 的反查：用关联对象（原子、无锁），避免 registry 跨队列竞态。
static const void *kIMDownloadTaskAssocKey = &kIMDownloadTaskAssocKey;
/// 每条请求**各自**的写句柄挂在自己的 dataTask 上：暂停/续传换请求时互不干涉（不会关掉别人的句柄）。
static const void *kIMDownloadHandleAssocKey = &kIMDownloadHandleAssocKey;

@interface IMMediaDownloadTask ()
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) int64_t receivedBytes;
@property (nonatomic, assign) int64_t totalBytes;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL finished;

@property (nonatomic, strong) NSURL *remoteURL;
@property (nonatomic, strong) NSURL *destURL;
@property (nonatomic, strong) NSURL *partURL;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *inFlight;
@property (nonatomic, strong, nullable) NSError *pendingError;       ///< 4xx/写盘失败等永久错误：didComplete 据此不重试
@property (nonatomic, assign) NSInteger netRetryCount;
@property (nonatomic, assign) NSTimeInterval startedAt;   ///< 首次发起时刻（终态算 duration_ms 用）
@property (nonatomic, copy, nullable) void (^onResume)(void);
@end

@interface IMMediaDownloader () <NSURLSessionDataDelegate>
- (void)removeTaskForKey:(NSString *)key;
@end

@implementation IMMediaDownloadTask

// pause/resume/cancel 均在主线程调用（来自 cell 交互）。
- (void)pause {
    if (self.cancelled || self.finished || self.paused) { return; }
    self.paused = YES;
    [self.inFlight cancel]; // 触发 didComplete（cancelled 错误）；那里 paused=YES 会保留 .part、关句柄
    self.inFlight = nil;
    IMLogWarnWithTag(IMLogTagMedia, @"download_paused key=%@ received=%lld", self.key, self.receivedBytes);
}

- (void)resume {
    if (self.cancelled || self.finished || !self.paused) { return; }
    self.paused = NO;
    IMLogWithTag(IMLogTagMedia, @"download_resumed key=%@ received=%lld", self.key, self.receivedBytes);
    if (self.onResume) { self.onResume(); }
}

- (void)cancel {
    self.cancelled = YES;
    self.paused = NO;
    [self.inFlight cancel];
    self.inFlight = nil;
    [NSFileManager.defaultManager removeItemAtURL:self.partURL error:NULL]; // 取消即弃已下字节
    self.progressHandler = nil;
    self.completionHandler = nil;
    IMLogWarnWithTag(IMLogTagMedia, @"download_cancelled key=%@", self.key);
    [[IMMediaDownloader shared] removeTaskForKey:self.key];
}

@end

@implementation IMMediaDownloader {
    NSMutableDictionary<NSString *, IMMediaDownloadTask *> *_tasks; // 仅主线程访问
    NSURLSession *_session;
}

+ (instancetype)shared {
    static IMMediaDownloader *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMMediaDownloader new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tasks = [NSMutableDictionary dictionary];
        NSOperationQueue *delegateQueue = [NSOperationQueue new];
        delegateQueue.maxConcurrentOperationCount = 1; // delegate 全部回调串行：三方法互不并发，写盘/收尾无锁即安全
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 30;
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:delegateQueue];
    }
    return self;
}

+ (nullable NSURL *)cachedFileURLForContent:(NSString *)content {
    NSString *base = content.lastPathComponent;
    if (base.length == 0) { return nil; }
    NSURL *caches = [NSFileManager.defaultManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:NULL];
    return [[caches URLByAppendingPathComponent:@"IMDownloads" isDirectory:YES] URLByAppendingPathComponent:base];
}

+ (BOOL)isContentCached:(NSString *)content {
    NSURL *url = [self cachedFileURLForContent:content];
    return url && [NSFileManager.defaultManager fileExistsAtPath:url.path];
}

- (IMMediaDownloadTask *)taskForKey:(NSString *)key {
    return key.length > 0 ? _tasks[key] : nil;
}

- (void)removeTaskForKey:(NSString *)key {
    if (key.length > 0) { [_tasks removeObjectForKey:key]; }
}

- (IMMediaDownloadTask *)downloadURL:(NSURL *)remoteURL toDestination:(NSURL *)destinationURL key:(NSString *)key {
    IMMediaDownloadTask *existing = [self taskForKey:key];
    if (existing) { return existing; }

    IMMediaDownloadTask *task = [IMMediaDownloadTask new];
    task.key = key;
    task.remoteURL = remoteURL;
    task.destURL = destinationURL;
    task.partURL = [destinationURL URLByAppendingPathExtension:@"part"];
    task.startedAt = NSDate.timeIntervalSinceReferenceDate;
    if (key.length > 0) { _tasks[key] = task; }

    __weak IMMediaDownloadTask *weakTask = task;
    task.onResume = ^{
        __strong IMMediaDownloadTask *t = weakTask;
        if (!t || t.cancelled || t.finished || t.paused) { return; }
        [self startRequestForTask:t];
    };
    task.onResume();
    return task;
}

/// 发一条从 `.part` 当前大小续起的 Range 请求（主线程）。
- (void)startRequestForTask:(IMMediaDownloadTask *)task {
    int64_t offset = [self partSizeForTask:task];
    task.receivedBytes = offset;
    if (task.progressHandler) { task.progressHandler(offset, task.totalBytes); }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:task.remoteURL];
    req.timeoutInterval = 30;
    if (offset > 0) {
        [req setValue:[NSString stringWithFormat:@"bytes=%lld-", offset] forHTTPHeaderField:@"Range"];
    }
    // offset 是断点续传唯一的真相来源（= .part 当前大小）：接不上时先看这一行。
    IMLogDebugWithTag(IMLogTagMedia, @"download_request key=%@ offset=%lld total=%lld",
                      task.key, offset, task.totalBytes);
    NSURLSessionDataTask *dataTask = [_session dataTaskWithRequest:req];
    objc_setAssociatedObject(dataTask, kIMDownloadTaskAssocKey, task, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    task.inFlight = dataTask;
    task.pendingError = nil;
    [dataTask resume];
}

- (int64_t)partSizeForTask:(IMMediaDownloadTask *)task {
    NSNumber *size = [NSFileManager.defaultManager attributesOfItemAtPath:task.partURL.path error:NULL][NSFileSize];
    return size ? size.longLongValue : 0;
}

#pragma mark - NSURLSessionDataDelegate（全部在串行 delegateQueue）

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    IMMediaDownloadTask *task = objc_getAssociatedObject(dataTask, kIMDownloadTaskAssocKey);
    // dataTask != inFlight：该请求已被暂停/续传替换（stale）→ 不接收，避免两条链抢写同一 .part。
    if (!task || task.cancelled || task.finished || dataTask != task.inFlight) {
        completionHandler(NSURLSessionResponseCancel);
        return;
    }

    NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
    NSInteger status = http ? http.statusCode : 200;
    if (status >= 400) { // 404/416/5xx：永久失败，交 didComplete（不重试）
        // status 是「文件已失效(404/410)」与「网络错」分因的依据，必须留痕。
        IMLogWarnWithTag(IMLogTagMedia, @"download_http_error key=%@ status=%ld", task.key, (long)status);
        task.pendingError = [self errorWithMessage:@"下载失败" code:status];
        completionHandler(NSURLSessionResponseCancel);
        return;
    }
    // 服务端忽略 Range 回 200（整文件）→ 已下的 .part 作废、从 0 重来，避免拼接错位。
    BOOL fullBody = (status == 200);
    if (fullBody && task.receivedBytes > 0) {
        // 用户视角是「进度条倒退回 0」，不留痕会被当成客户端 bug。
        IMLogWarnWithTag(IMLogTagMedia, @"download_range_ignored_restart key=%@ discarded_bytes=%lld",
                         task.key, task.receivedBytes);
        [NSFileManager.defaultManager removeItemAtURL:task.partURL error:NULL];
        task.receivedBytes = 0;
    }
    int64_t total = [self totalBytesFromResponse:http offset:task.receivedBytes
                                        expected:response.expectedContentLength fullBody:fullBody];
    if (total > 0) { task.totalBytes = total; }

    NSFileHandle *fh = [self openWriteHandleForTask:task truncate:fullBody];
    if (!fh) {
        task.pendingError = [self errorWithMessage:@"本地文件写入失败" code:-1];
        completionHandler(NSURLSessionResponseCancel);
        return;
    }
    objc_setAssociatedObject(dataTask, kIMDownloadHandleAssocKey, fh, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    IMMediaDownloadTask *task = objc_getAssociatedObject(dataTask, kIMDownloadTaskAssocKey);
    NSFileHandle *fh = objc_getAssociatedObject(dataTask, kIMDownloadHandleAssocKey);
    if (!task || task.cancelled || task.finished || task.paused || !fh || dataTask != task.inFlight) { return; }
    if (![fh writeData:data error:NULL]) {
        task.pendingError = [self errorWithMessage:@"本地文件写入失败" code:-1];
        [task.inFlight cancel]; // → didComplete 据 pendingError 永久失败
        return;
    }
    task.receivedBytes += (int64_t)data.length;
    task.netRetryCount = 0; // 有字节落地：只有**连续**网络失败才升级为整体失败
    int64_t received = task.receivedBytes, total = task.totalBytes;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (task.cancelled || task.finished || task.paused) { return; }
        if (task.progressHandler) { task.progressHandler(received, total); }
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)sessionTask didCompleteWithError:(NSError *)error {
    IMMediaDownloadTask *task = objc_getAssociatedObject(sessionTask, kIMDownloadTaskAssocKey);
    NSFileHandle *fh = objc_getAssociatedObject(sessionTask, kIMDownloadHandleAssocKey);
    objc_setAssociatedObject(sessionTask, kIMDownloadTaskAssocKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(sessionTask, kIMDownloadHandleAssocKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [fh closeAndReturnError:NULL]; // 关**本请求自己**的句柄（成功要 rename；暂停要 flush）——不会误关新请求的
    if (!task || task.cancelled || task.finished) { return; }
    // 该完成属于已被替换的旧请求（暂停后 inFlight 置 nil，或续传已开新链）→ 只清理、不重试/不落地。
    if (sessionTask != task.inFlight) { return; }

    if (task.pendingError) { [self finishTask:task localURL:nil error:task.pendingError]; return; } // 永久失败：不重试
    if (error) { [self retryOrFailTask:task error:error]; return; }                                  // 网络失败：退避重试

    // 无错：.part → 目标文件（原子替换）。
    NSError *mvErr = nil;
    [NSFileManager.defaultManager removeItemAtURL:task.destURL error:NULL];
    BOOL ok = [NSFileManager.defaultManager moveItemAtURL:task.partURL toURL:task.destURL error:&mvErr];
    [self finishTask:task localURL:(ok ? task.destURL : nil) error:(ok ? nil : (mvErr ?: [self errorWithMessage:@"落地失败" code:-1]))];
}

#pragma mark - 完成 / 重试

/// 网络失败：短退避自动续 2 次；连续失败才交用户手动重试（对齐上传）。delegateQueue 调用。
- (void)retryOrFailTask:(IMMediaDownloadTask *)task error:(NSError *)error {
    if (task.netRetryCount >= 2) { [self finishTask:task localURL:nil error:error]; return; }
    task.netRetryCount += 1;
    IMLogWarnWithTag(IMLogTagMedia, @"download_net_retry key=%@ attempt=%ld error=%@",
                     task.key, (long)task.netRetryCount, error.localizedDescription ?: @"-");
    __weak IMMediaDownloadTask *weakTask = task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong IMMediaDownloadTask *t = weakTask;
        if (t.onResume) { t.onResume(); } // onResume 自查 cancelled/finished/paused
    });
}

/// 终态：主线程回调一次并注销任务。finished 双保险：迟到回调不再二次回调。
- (void)finishTask:(IMMediaDownloadTask *)task localURL:(NSURL *)localURL error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (task.cancelled || task.finished) { return; }
        task.finished = YES;
        // 全下载路径的**唯一终态点**：成功/失败各且仅记一条（业务分类由 Coordinator 另记，两者互不重复）。
        long durationMs = (long)((NSDate.timeIntervalSinceReferenceDate - task.startedAt) * 1000);
        if (error) {
            IMLogWarnWithTag(IMLogTagMedia, @"download_failed key=%@ bytes=%lld total=%lld duration_ms=%ld retries=%ld error=%@",
                             task.key, task.receivedBytes, task.totalBytes, durationMs,
                             (long)task.netRetryCount, error.localizedDescription ?: @"-");
        } else {
            IMLogWithTag(IMLogTagMedia, @"download_completed key=%@ bytes=%lld duration_ms=%ld retries=%ld",
                         task.key, task.receivedBytes, durationMs, (long)task.netRetryCount);
        }
        void (^done)(NSURL *, NSError *) = task.completionHandler;
        [self removeTaskForKey:task.key];
        task.completionHandler = nil;
        task.progressHandler = nil;
        if (done) { done(localURL, error); }
    });
}

#pragma mark - 工具

/// 打开写句柄：truncate=YES（200 整文件）从头写；否则续写（seek 到末尾）。仅 delegateQueue 调用。
- (nullable NSFileHandle *)openWriteHandleForTask:(IMMediaDownloadTask *)task truncate:(BOOL)truncate {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtURL:task.partURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    if (truncate || ![fm fileExistsAtPath:task.partURL.path]) {
        [fm removeItemAtURL:task.partURL error:NULL];
        [fm createFileAtPath:task.partURL.path contents:nil attributes:nil];
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingToURL:task.partURL error:NULL];
    [fh seekToEndOfFile];
    return fh;
}

- (int64_t)totalBytesFromResponse:(NSHTTPURLResponse *)http offset:(int64_t)offset
                          expected:(int64_t)expected fullBody:(BOOL)fullBody {
    NSString *contentRange = http.allHeaderFields[@"Content-Range"]; // e.g. "bytes 100-999/1000"
    if ([contentRange isKindOfClass:[NSString class]]) {
        NSRange slash = [contentRange rangeOfString:@"/" options:NSBackwardsSearch];
        if (slash.location != NSNotFound) {
            long long total = [[contentRange substringFromIndex:slash.location + 1] longLongValue];
            if (total > 0) { return total; }
        }
    }
    if (expected > 0) { return fullBody ? expected : (offset + expected); } // 206 时 expected=剩余字节
    return 0;
}

- (NSError *)errorWithMessage:(NSString *)message code:(NSInteger)code {
    return [NSError errorWithDomain:@"IMMediaDownloaderErrorDomain" code:code
                           userInfo:@{ NSLocalizedDescriptionKey: message ?: @"下载失败" }];
}

@end
