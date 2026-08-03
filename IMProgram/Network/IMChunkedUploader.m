//  IMChunkedUploader.m

#import "IMChunkedUploader.h"
#import "IMHTTPService.h"
#import "IMLog.h"

/// 单片大小。8MB=服务端 init 响应建议值（chunk_size）与其单片上限：局域网实测 4MB 片速率仅 ~1MB/s，
/// 每片一次往返的固定开销占比过高；片加倍可少一半往返。失败重传的代价上限也是 8MB，可接受。
static const NSUInteger kIMChunkSize = 8 * 1024 * 1024;
/// 小于该值走一次性 multipart：分片要多 3 次往返（init/complete/status），小文件反而更慢。
static const NSUInteger kIMChunkedThreshold = 8 * 1024 * 1024;

@interface IMChunkedUploadTask ()
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy, nullable) NSString *uploadID;
@property (nonatomic, assign) int64_t sentBytes;
@property (nonatomic, assign) int64_t totalBytes;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL finished;   ///< 已回调终态：其余悬空回调一律作废
/// 传输链代际号：**任一时刻只允许一条链在跑**。resume/重启都会 +1 开新链，旧链的每个异步
/// 续步都携带自己的代际号、发现不匹配立即退出。没有它，暂停期间在飞分片完成后会继续旧链、
/// resume 又开新链——每暂停/恢复一轮泄漏一条并行链，挤爆带宽后被 60s 超时误判整体失败（真机实录）。
@property (nonatomic, assign) NSInteger generation;
@property (nonatomic, assign) NSInteger restartCount;  ///< 服务端会话丢失后从头重传的次数（防无限循环）
@property (nonatomic, assign) NSInteger netRetryCount; ///< 连续网络失败自动重试次数（分片成功即清零）
/// 当前链在飞的 HTTP 请求。暂停/换链/取消时必须 **cancel 它**：代际号只能让回调作废，
/// 8MB 请求体仍会继续上传到完——快速连点暂停/恢复曾累积 30 个并发 PUT 挤爆带宽（真机实录）。
@property (nonatomic, strong, nullable) NSURLSessionTask *inFlightRequest;
/// 由 uploader 注入：恢复时重新驱动传输循环。
@property (nonatomic, copy, nullable) void (^onResume)(void);
@end

@interface IMChunkedUploader ()
- (void)removeTaskForKey:(NSString *)key;
@end

@implementation IMChunkedUploadTask

- (void)pause {
    if (self.cancelled || self.finished || self.paused) { return; }
    self.paused = YES;
    [self.inFlightRequest cancel]; // 真正掐断在飞请求；其回调经代际/暂停检查后被丢弃
    self.inFlightRequest = nil;
    IMLogWarnWithTag(IMLogTagMedia, @"upload_paused key=%@ upload_id=%@", self.key, self.uploadID ?: @"-");
}

- (void)resume {
    if (self.cancelled || self.finished || !self.paused) { return; }
    self.paused = NO;
    IMLogWithTag(IMLogTagMedia, @"upload_resumed key=%@ upload_id=%@", self.key, self.uploadID ?: @"-");
    if (self.onResume) { self.onResume(); }
}

- (void)cancel {
    self.cancelled = YES;
    self.paused = NO;
    [self.inFlightRequest cancel];
    self.inFlightRequest = nil;
    self.progressHandler = nil;
    self.completionHandler = nil;
    IMLogWarnWithTag(IMLogTagMedia, @"upload_cancelled key=%@ upload_id=%@", self.key, self.uploadID ?: @"-");
    [[IMChunkedUploader shared] removeTaskForKey:self.key];
}

@end

@implementation IMChunkedUploader {
    NSMutableDictionary<NSString *, IMChunkedUploadTask *> *_tasks; // 仅主线程访问
    dispatch_queue_t _io; // 串行：分片读盘。绝不能在主线程读 4MB（每片一次，100MB 文件 25 次）
}

+ (instancetype)shared {
    static IMChunkedUploader *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMChunkedUploader new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tasks = [NSMutableDictionary dictionary];
        _io = dispatch_queue_create("im.upload.chunk.io", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (NSUInteger)chunkedThresholdBytes { return kIMChunkedThreshold; }

- (IMChunkedUploadTask *)taskForKey:(NSString *)key {
    return key.length > 0 ? _tasks[key] : nil;
}

- (void)removeTaskForKey:(NSString *)key {
    if (key.length > 0) { [_tasks removeObjectForKey:key]; }
}

- (IMChunkedUploadTask *)uploadFileAtURL:(NSURL *)fileURL
                                fileName:(NSString *)fileName
                                   token:(NSString *)token
                                     key:(NSString *)key
                                resumeID:(NSString *)resumeID {
    IMChunkedUploadTask *existing = [self taskForKey:key];
    if (existing) { return existing; } // 同一条消息不重复开传

    IMChunkedUploadTask *task = [IMChunkedUploadTask new];
    task.key = key;
    unsigned long long total = [[NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:NULL][NSFileSize] unsignedLongLongValue];
    task.totalBytes = (int64_t)total;
    if (key.length > 0) { _tasks[key] = task; }
    if (total == 0) {
        [self finishTask:task url:nil contentType:nil error:[self errorWithMessage:@"文件为空或不可读"]];
        return task;
    }

    __weak IMChunkedUploadTask *weakTask = task;
    // 开启一条**新代际**的传输链：有 uploadID → 先问服务端 offset（唯一权威）再续传；
    // 无 uploadID（首传/服务端会话丢失后重来）→ init 换新会话从 0 传。
    void (^beginChain)(void) = ^{
        __strong IMChunkedUploadTask *t = weakTask;
        if (!t || t.cancelled || t.finished || t.paused) { return; }
        [t.inFlightRequest cancel]; // 旧链在飞请求立刻掐断（回调经代际检查丢弃），不再空耗带宽
        t.inFlightRequest = nil;
        NSInteger gen = ++t.generation; // 旧链的所有悬空续步就此作废
        if (t.uploadID.length > 0) {
            [self syncThenSendFrom:t fileURL:fileURL fileName:fileName token:token gen:gen];
            return;
        }
        t.inFlightRequest = [self requestUploadInitWithName:fileName size:t.totalBytes token:token completion:^(NSString *uploadID, NSError *error) {
            __strong IMChunkedUploadTask *t2 = weakTask;
            if (!t2 || t2.cancelled || t2.finished || gen != t2.generation) { return; }
            if (error || uploadID.length == 0) {
                [self finishTask:t2 url:nil contentType:nil error:(error ?: [self errorWithMessage:@"上传初始化失败"])];
                return;
            }
            t2.uploadID = uploadID;
            if (t2.uploadIDHandler) { t2.uploadIDHandler(uploadID); } // 调用方持久化 → 跨启动可续传
            [self sendNextChunkFor:t2 fileURL:fileURL fileName:fileName token:token offset:0 gen:gen];
        }];
    };
    task.uploadID = resumeID.length > 0 ? resumeID : nil;
    task.onResume = beginChain;
    beginChain();
    return task;
}

#pragma mark - 传输循环

/// 链上每个异步续步的通行检查：任务已终态/被取消/暂停/换代 → 本链退出。
static BOOL IMChainAlive(IMChunkedUploadTask *task, NSInteger gen) {
    return task && !task.cancelled && !task.finished && !task.paused && gen == task.generation;
}

/// 先问服务端已收到多少（唯一权威），再从该 offset 继续发。
- (void)syncThenSendFrom:(IMChunkedUploadTask *)task fileURL:(NSURL *)fileURL fileName:(NSString *)fileName
                   token:(NSString *)token gen:(NSInteger)gen {
    if (!IMChainAlive(task, gen)) { return; }
    task.inFlightRequest = [self statusForUploadID:task.uploadID token:token completion:^(int64_t offset, NSError *error) {
        if (!IMChainAlive(task, gen)) { return; }
        if (error) {
            [self handleChainError:error task:task fileURL:fileURL fileName:fileName token:token];
            return;
        }
        [self sendNextChunkFor:task fileURL:fileURL fileName:fileName token:token offset:offset gen:gen];
    }];
}

- (void)sendNextChunkFor:(IMChunkedUploadTask *)task fileURL:(NSURL *)fileURL fileName:(NSString *)fileName
                   token:(NSString *)token offset:(int64_t)offset gen:(NSInteger)gen {
    if (!IMChainAlive(task, gen)) { return; } // 停在分片边界；已传字节留在服务端，resume 时再对齐
    task.sentBytes = offset;
    if (task.progressHandler) { task.progressHandler(offset, task.totalBytes); }

    if (offset >= task.totalBytes) {
        task.inFlightRequest = [self completeUploadID:task.uploadID token:token completion:^(NSString *url, NSString *contentType, NSError *error) {
            if (task.cancelled || task.finished || gen != task.generation) { return; } // complete 不看 paused：都传完了
            if (error) {
                [self handleChainError:error task:task fileURL:fileURL fileName:fileName token:token];
                return;
            }
            [self finishTask:task url:url contentType:contentType error:nil];
        }];
        return;
    }
    // 读盘放到串行 IO 队列：HTTP 回调是在主线程来的，直接在那读 8MB 会卡住滚动。
    int64_t length = MIN((int64_t)kIMChunkSize, task.totalBytes - offset);
    dispatch_async(_io, ^{
        NSData *chunk = [self readChunkFromURL:fileURL offset:offset length:length];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!IMChainAlive(task, gen)) { return; }
            if (chunk.length == 0) {
                [self finishTask:task url:nil contentType:nil error:[self errorWithMessage:@"本地文件读取失败"]];
                return;
            }
            task.inFlightRequest = [self sendChunk:chunk uploadID:task.uploadID offset:offset token:token completion:^(int64_t newOffset, NSError *error) {
                if (!IMChainAlive(task, gen)) { return; }
                if (error) {
                    [self handleChainError:error task:task fileURL:fileURL fileName:fileName token:token];
                    return;
                }
                task.netRetryCount = 0; // 有分片落地就重置：只有**连续**网络失败才升级为整体失败
                // 服务端返回的 offset 是权威值：乱序/重复发时它会回当前进度，据此自动对齐而不是失败。
                [self sendNextChunkFor:task fileURL:fileURL fileName:fileName token:token offset:newOffset gen:gen];
            }];
        });
    });
}

/// 链上错误分流：
///   - 服务端**业务拒绝**（典型：24h TTL 到期 / 已被 complete 清理 →「上传会话不存在或已过期」）——
///     重试同一会话必然再失败（真机实录：重试→status 400→标失败→死循环），唯一出路是**换新会话从头传**；
///   - 网络失败（超时/断网）——offset 还在服务端，保留会话直接判失败，用户重试时从 offset 续。
- (void)handleChainError:(NSError *)error task:(IMChunkedUploadTask *)task
                 fileURL:(NSURL *)fileURL fileName:(NSString *)fileName token:(NSString *)token {
    if ([IMHTTPService isBusinessError:error]) {
        if (task.restartCount >= 2) { [self finishTask:task url:nil contentType:nil error:error]; return; }
        task.restartCount += 1;
        IMLogWarnWithTag(IMLogTagMedia, @"upload_session_lost_restarting key=%@ old_upload_id=%@ attempt=%ld error=%@",
                         task.key, task.uploadID ?: @"-", (long)task.restartCount, error.localizedDescription ?: @"-");
        task.uploadID = nil; // 作废死会话；onResume 走 init 换新会话（新 upload_id 会经 uploadIDHandler 重新落盘）
        if (task.uploadIDHandler) { task.uploadIDHandler(@""); } // 清掉旁挂文件里的死 ID，杀进程重启不再撞 400
        if (task.onResume) { task.onResume(); }
        return;
    }
    // 网络失败（超时/断网）：offset 都留在服务端，短退避自动续 2 次；连续失败才交给用户手动重试。
    if (task.netRetryCount >= 2) {
        [self finishTask:task url:nil contentType:nil error:error];
        return;
    }
    task.netRetryCount += 1;
    IMLogWarnWithTag(IMLogTagMedia, @"upload_net_retry key=%@ attempt=%ld error=%@",
                     task.key, (long)task.netRetryCount, error.localizedDescription ?: @"-");
    __weak IMChunkedUploadTask *weakTask = task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong IMChunkedUploadTask *t = weakTask;
        if (t.onResume) { t.onResume(); } // beginChain 自查 cancelled/finished/paused，安全
    });
}

/// 只把需要的那一片读进内存（4MB），文件多大都与内存占用无关。仅在 _io 队列调用。
- (NSData *)readChunkFromURL:(NSURL *)fileURL offset:(int64_t)offset length:(int64_t)length {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingFromURL:fileURL error:NULL];
    if (!fh) { return nil; }
    NSData *data = nil;
    if ([fh seekToOffset:(unsigned long long)offset error:NULL]) {
        data = [fh readDataUpToLength:(NSUInteger)length error:NULL];
    }
    [fh closeAndReturnError:NULL];
    return data;
}

/// 终态：回调一次并注销任务（成功或失败都不再保留，避免界面重建后接管到一条已结束的任务）。
/// finished + 换代双保险：终态之后任何悬空续步/迟到回调都不可能再推进或二次回调。
- (void)finishTask:(IMChunkedUploadTask *)task url:(NSString *)url contentType:(NSString *)contentType error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (task.cancelled || task.finished) { return; }
        task.finished = YES;
        task.generation += 1;
        void (^done)(NSString *, NSString *, NSError *) = task.completionHandler;
        [self removeTaskForKey:task.key];
        task.completionHandler = nil;
        task.progressHandler = nil;
        if (done) { done(url, contentType, error); }
    });
}

#pragma mark - 四个端点

- (NSURLSessionTask *)requestUploadInitWithName:(NSString *)name size:(int64_t)size token:(NSString *)token
                              completion:(void (^)(NSString *uploadID, NSError *error))completion {
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{ @"name": name ?: @"file", @"size": @(size) } options:0 error:NULL];
    return [IMHTTPService.sharedService performUploadAPI:@"/api/v1/upload/init" method:@"POST" body:body token:token
                                              completion:^(NSDictionary *data, NSError *error) {
        completion(data[@"upload_id"], error);
    }];
}

- (NSURLSessionTask *)statusForUploadID:(NSString *)uploadID token:(NSString *)token
                             completion:(void (^)(int64_t offset, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/upload/%@/status", uploadID ?: @""];
    return [IMHTTPService.sharedService performUploadAPI:path method:@"GET" body:nil token:token
                                              completion:^(NSDictionary *data, NSError *error) {
        completion([data[@"offset"] longLongValue], error);
    }];
}

- (NSURLSessionTask *)sendChunk:(NSData *)chunk uploadID:(NSString *)uploadID offset:(int64_t)offset token:(NSString *)token
                     completion:(void (^)(int64_t newOffset, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/upload/%@/chunk?offset=%lld", uploadID ?: @"", offset];
    return [IMHTTPService.sharedService performUploadAPI:path method:@"PUT" body:chunk token:token
                                              completion:^(NSDictionary *data, NSError *error) {
        completion([data[@"offset"] longLongValue], error);
    }];
}

- (NSURLSessionTask *)completeUploadID:(NSString *)uploadID token:(NSString *)token
                            completion:(void (^)(NSString *url, NSString *contentType, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/upload/%@/complete", uploadID ?: @""];
    return [IMHTTPService.sharedService performUploadAPI:path method:@"POST" body:nil token:token
                                              completion:^(NSDictionary *data, NSError *error) {
        completion(data[@"url"], data[@"content_type"], error);
    }];
}

#pragma mark -

- (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:@"IMChunkedUploaderErrorDomain" code:-1
                           userInfo:@{ NSLocalizedDescriptionKey: message ?: @"上传失败" }];
}

@end
