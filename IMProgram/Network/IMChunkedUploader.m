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
/// 由 uploader 注入：恢复时重新驱动传输循环。
@property (nonatomic, copy, nullable) void (^onResume)(void);
@end

@interface IMChunkedUploader ()
- (void)removeTaskForKey:(NSString *)key;
@end

@implementation IMChunkedUploadTask

- (void)pause {
    if (self.cancelled) { return; }
    self.paused = YES;
    IMLogWarnWithTag(IMLogTagMedia, @"upload_paused key=%@ upload_id=%@", self.key, self.uploadID ?: @"-");
}

- (void)resume {
    if (self.cancelled || !self.paused) { return; }
    self.paused = NO;
    IMLogWithTag(IMLogTagMedia, @"upload_resumed key=%@ upload_id=%@", self.key, self.uploadID ?: @"-");
    if (self.onResume) { self.onResume(); }
}

- (void)cancel {
    self.cancelled = YES;
    self.paused = NO;
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
    void (^start)(NSString *) = ^(NSString *uploadID) {
        __strong IMChunkedUploadTask *t = weakTask;
        if (!t || t.cancelled) { return; }
        t.uploadID = uploadID;
        if (t.uploadIDHandler) { t.uploadIDHandler(uploadID); } // 调用方持久化 → 跨启动可续传
        // 恢复时不信任本地记录的 offset，一律以服务端 status 为准（可能上次最后一片其实写成功了）。
        t.onResume = ^{
            __strong IMChunkedUploadTask *t2 = weakTask;
            if (t2) { [self syncThenSendFrom:t2 fileURL:fileURL token:token]; }
        };
        [self syncThenSendFrom:t fileURL:fileURL token:token];
    };

    if (resumeID.length > 0) {
        start(resumeID);
    } else {
        [self initUploadWithName:fileName size:(int64_t)total token:token completion:^(NSString *uploadID, NSError *error) {
            __strong IMChunkedUploadTask *t = weakTask;
            if (!t) { return; }
            if (error || uploadID.length == 0) {
                [self finishTask:t url:nil contentType:nil error:(error ?: [self errorWithMessage:@"上传初始化失败"])];
                return;
            }
            start(uploadID);
        }];
    }
    return task;
}

#pragma mark - 传输循环

/// 先问服务端已收到多少（唯一权威），再从该 offset 继续发。
- (void)syncThenSendFrom:(IMChunkedUploadTask *)task fileURL:(NSURL *)fileURL token:(NSString *)token {
    if (task.cancelled || task.paused) { return; }
    [self statusForUploadID:task.uploadID token:token completion:^(int64_t offset, NSError *error) {
        if (error) { [self finishTask:task url:nil contentType:nil error:error]; return; }
        [self sendNextChunkFor:task fileURL:fileURL token:token offset:offset];
    }];
}

- (void)sendNextChunkFor:(IMChunkedUploadTask *)task fileURL:(NSURL *)fileURL token:(NSString *)token offset:(int64_t)offset {
    if (task.cancelled || task.paused) { return; } // 停在分片边界；已传字节留在服务端，resume 时再对齐
    task.sentBytes = offset;
    if (task.progressHandler) { task.progressHandler(offset, task.totalBytes); }

    if (offset >= task.totalBytes) {
        [self completeUploadID:task.uploadID token:token completion:^(NSString *url, NSString *contentType, NSError *error) {
            [self finishTask:task url:url contentType:contentType error:error];
        }];
        return;
    }
    // 读盘放到串行 IO 队列：HTTP 回调是在主线程来的，直接在那读 4MB 会卡住滚动。
    int64_t length = MIN((int64_t)kIMChunkSize, task.totalBytes - offset);
    dispatch_async(_io, ^{
        NSData *chunk = [self readChunkFromURL:fileURL offset:offset length:length];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.cancelled || task.paused) { return; }
            if (chunk.length == 0) {
                [self finishTask:task url:nil contentType:nil error:[self errorWithMessage:@"本地文件读取失败"]];
                return;
            }
            [self sendChunk:chunk uploadID:task.uploadID offset:offset token:token completion:^(int64_t newOffset, NSError *error) {
                if (error) { [self finishTask:task url:nil contentType:nil error:error]; return; }
                // 服务端返回的 offset 是权威值：乱序/重复发时它会回当前进度，据此自动对齐而不是失败。
                [self sendNextChunkFor:task fileURL:fileURL token:token offset:newOffset];
            }];
        });
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
- (void)finishTask:(IMChunkedUploadTask *)task url:(NSString *)url contentType:(NSString *)contentType error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (task.cancelled) { return; }
        void (^done)(NSString *, NSString *, NSError *) = task.completionHandler;
        [self removeTaskForKey:task.key];
        task.completionHandler = nil;
        task.progressHandler = nil;
        if (done) { done(url, contentType, error); }
    });
}

#pragma mark - 四个端点

- (void)initUploadWithName:(NSString *)name size:(int64_t)size token:(NSString *)token
                completion:(void (^)(NSString *uploadID, NSError *error))completion {
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{ @"name": name ?: @"file", @"size": @(size) } options:0 error:NULL];
    [IMHTTPService.sharedService performUploadAPI:@"/api/v1/upload/init" method:@"POST" body:body token:token
                                       completion:^(NSDictionary *data, NSError *error) {
        completion(data[@"upload_id"], error);
    }];
}

- (void)statusForUploadID:(NSString *)uploadID token:(NSString *)token
               completion:(void (^)(int64_t offset, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/upload/%@/status", uploadID ?: @""];
    [IMHTTPService.sharedService performUploadAPI:path method:@"GET" body:nil token:token
                                       completion:^(NSDictionary *data, NSError *error) {
        completion([data[@"offset"] longLongValue], error);
    }];
}

- (void)sendChunk:(NSData *)chunk uploadID:(NSString *)uploadID offset:(int64_t)offset token:(NSString *)token
       completion:(void (^)(int64_t newOffset, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/upload/%@/chunk?offset=%lld", uploadID ?: @"", offset];
    [IMHTTPService.sharedService performUploadAPI:path method:@"PUT" body:chunk token:token
                                       completion:^(NSDictionary *data, NSError *error) {
        completion([data[@"offset"] longLongValue], error);
    }];
}

- (void)completeUploadID:(NSString *)uploadID token:(NSString *)token
              completion:(void (^)(NSString *url, NSString *contentType, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/upload/%@/complete", uploadID ?: @""];
    [IMHTTPService.sharedService performUploadAPI:path method:@"POST" body:nil token:token
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
