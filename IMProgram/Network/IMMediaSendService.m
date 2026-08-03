//  IMMediaSendService.m

#import "IMMediaSendService.h"
#import "IMMediaPicker.h"
#import "IMPendingMediaStore.h"
#import "IMChunkedUploader.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMMediaAttributes.h"
#import "IMUploadProgress.h"
#import "IMMessageModel.h"
#import "IMDatabase.h"
#import "IMImageLoader.h"
#import "IMVideoThumbnailLoader.h"
#import "IMMediaUtil.h"
#import "IMOriginalVideoCache.h"
#import "IMLog.h"

NSNotificationName const IMMediaSendProgressDidChangeNotification = @"IMMediaSendProgressDidChange";
NSNotificationName const IMMediaSendMetaDidChangeNotification = @"IMMediaSendMetaDidChange";
NSNotificationName const IMMediaSendDidDispatchNotification = @"IMMediaSendDidDispatch";
NSNotificationName const IMMediaSendDidFailNotification = @"IMMediaSendDidFail";
NSNotificationName const IMMediaSendDidCancelNotification = @"IMMediaSendDidCancel";
NSNotificationName const IMMediaSendAckNotification = @"IMMediaSendAck";

NSString * const kIMMediaSendConvIDKey = @"conv_id";
NSString * const kIMMediaSendClientMsgIDKey = @"client_msg_id";
NSString * const kIMMediaSendOldClientMsgIDKey = @"old_client_msg_id";
NSString * const kIMMediaSendSuccessKey = @"success";
NSString * const kIMMediaSendConvSeqKey = @"conv_seq";
NSString * const kIMMediaSendMessageKey = @"message";

#pragma mark - 作业

/// 一条发送作业（服务内部）：从乐观消息到 socket 发出的全部上下文。
@interface IMMediaSendJob : NSObject
@property (nonatomic, strong) IMMessageModel *message;
@property (nonatomic, strong, nullable) IMPickedMediaHandle *handle; ///< 媒体作业转码前持有；落盘后置空
@property (nonatomic, copy) NSString *toUser;                        ///< 群聊传 @""
@property (nonatomic, strong, nullable) IMDatabaseAccountContext *dbContext;
@property (nonatomic, assign) BOOL cancelled; ///< 用户取消：各阶段边界检查后丢弃，不再推进
@end
@implementation IMMediaSendJob
@end

#pragma mark - 服务

@interface IMMediaSendService ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *previews;
@property (nonatomic, strong) NSMutableDictionary<NSString *, IMUploadProgress *> *progressMap;
@end

@implementation IMMediaSendService {
    NSMutableDictionary<NSString *, IMMediaSendJob *> *_jobs; ///< key=clientMsgID（临时键）
    NSMutableArray<NSString *> *_mediaQueue; ///< 待处理的媒体作业键（串行：避免并发转码/挤占带宽）
    BOOL _mediaProcessing;
    NSString *_currentMediaKey; ///< 正在跑的媒体作业键：文件作业/重试完成时不得误推进串行队列
    dispatch_queue_t _io; ///< 磁盘搬运（storeData / move）绝不能在主线程：74MB 写盘足以卡掉一次滚动
    NSCountedSet<NSString *> *_failedConvs; ///< 本次运行中失败未重试的发送件按会话计数（列表红感叹号）
}

+ (instancetype)shared {
    static IMMediaSendService *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMMediaSendService new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _jobs = [NSMutableDictionary dictionary];
        _mediaQueue = [NSMutableArray array];
        _previews = [NSMutableDictionary dictionary];
        _progressMap = [NSMutableDictionary dictionary];
        _io = dispatch_queue_create("im.mediasend.io", DISPATCH_QUEUE_SERIAL);
        _failedConvs = [NSCountedSet set];
    }
    return self;
}

#pragma mark 查询

- (NSArray<IMMessageModel *> *)inFlightMessagesInConv:(NSString *)convID {
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray array];
    for (NSString *key in _jobs) {
        IMMediaSendJob *job = _jobs[key];
        if ([job.message.convID isEqualToString:convID]) { [out addObject:job.message]; }
    }
    [out sortUsingComparator:^NSComparisonResult(IMMessageModel *a, IMMessageModel *b) {
        return a.timestamp < b.timestamp ? NSOrderedAscending : NSOrderedDescending;
    }];
    return out;
}

- (BOOL)hasActiveJobForClientMsgID:(NSString *)clientMsgID {
    return clientMsgID.length > 0 && _jobs[clientMsgID] != nil;
}

- (BOOL)hasFailedOutboxInConv:(NSString *)convID {
    return convID.length > 0 && [_failedConvs countForObject:convID] > 0;
}

#pragma mark 入列（媒体）

- (void)enqueueMediaHandles:(NSArray<IMPickedMediaHandle *> *)handles
                   messages:(NSArray<IMMessageModel *> *)messages
                     toUser:(NSString *)toUser
                  dbContext:(IMDatabaseAccountContext *)dbContext {
    NSParameterAssert(handles.count == messages.count);
    for (NSUInteger i = 0; i < handles.count && i < messages.count; i++) {
        IMMessageModel *m = messages[i];
        NSString *key = m.clientMsgID ?: @"";
        if (key.length == 0 || _jobs[key]) { continue; }
        IMMediaSendJob *job = [IMMediaSendJob new];
        job.message = m;
        job.handle = handles[i];
        job.toUser = toUser ?: @"";
        job.dbContext = dbContext;
        _jobs[key] = job;
        [_mediaQueue addObject:key];
        self.progressMap[key] = [IMUploadProgress queued];
        // 缩略图由服务加载（页面销毁不中断），拿到即通知界面补图。
        __weak typeof(self) ws = self;
        [handles[i] loadThumbnail:^(UIImage *thumb) {
            __strong typeof(ws) self = ws;
            if (!self || !thumb) { return; }
            self.previews[m.clientMsgID ?: key] = thumb; // 键可能已迁移到真实 ID，读属性即取最新
            [self postNotification:IMMediaSendMetaDidChangeNotification forMessage:m oldKey:nil];
        }];
    }
    [self processNextMediaJob];
}

/// 串行推进媒体队列：转码/上传一次只跑一条（单项失败不阻塞后续）。
- (void)processNextMediaJob {
    if (_mediaProcessing || _mediaQueue.count == 0) { return; }
    NSString *key = _mediaQueue.firstObject;
    [_mediaQueue removeObjectAtIndex:0];
    IMMediaSendJob *job = _jobs[key];
    if (!job) { [self processNextMediaJob]; return; }
    _mediaProcessing = YES;
    _currentMediaKey = [key copy];

    IMMessageModel *m = job.message;
    __weak typeof(self) ws = self;
    [job.handle loadData:^(IMPickedMedia *item) { // 压缩/转码在句柄内部串行队列，回调主线程
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (job.cancelled) { // 转码期被取消：产物直接丢弃（转码本身无法中途打断）
            if (item.fileURL) { [[NSFileManager defaultManager] removeItemAtURL:item.fileURL error:NULL]; }
            [self advanceMediaQueueAfter:(m.clientMsgID ?: @"")];
            return;
        }
        NSString *token = IMHTTPService.sharedService.currentToken;
        if ((item.byteCount <= 0) || token.length == 0) {
            [self failJob:job];
            return;
        }
        // 发送端量出的媒体元数据：先落到消息模型（本地气泡立刻按原比例排版），随后随 send_msg 上行。
        m.mediaW = (NSInteger)item.pixelSize.width;
        m.mediaH = (NSInteger)item.pixelSize.height;
        m.duration = item.durationMillis;
        m.fileSize = item.byteCount;
        job.handle = nil; // 句柄使命完成；字节在 item（data 或 fileURL）
        [self storeAndUploadItem:item forJob:job];
    } progress:^(double fraction) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self.progressMap[m.clientMsgID ?: @""] = [IMUploadProgress transcodingWithFraction:fraction];
        [self postNotification:IMMediaSendProgressDidChangeNotification forMessage:m oldKey:nil];
    }];
}

/// 字节落盘（后台 IO 队列）→ 消息落库 → 起上传。
- (void)storeAndUploadItem:(IMPickedMedia *)item forJob:(IMMediaSendJob *)job {
    IMMessageModel *m = job.message;
    NSString *clientMsgID = m.clientMsgID ?: @"";
    NSString *ext = item.fileName.pathExtension;
    __weak typeof(self) ws = self;
    dispatch_async(_io, ^{
        // 视频产物已在磁盘 → move（免 2GB 级拷贝）；图片字节在内存 → 写盘。
        NSString *localRef = item.fileURL
            ? [[IMPendingMediaStore shared] storeByMovingFileAtURL:item.fileURL forClientMsgID:clientMsgID extension:ext]
            : [[IMPendingMediaStore shared] storeData:item.data forClientMsgID:clientMsgID extension:ext];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) self = ws;
            if (!self) { return; }
            if (job.cancelled) { // 落盘窗口内被取消：清掉刚写的副本
                [[IMPendingMediaStore shared] removeLocalRef:localRef];
                [self advanceMediaQueueAfter:clientMsgID];
                return;
            }
            if (localRef) {
                // 落库先行：从这一刻起，无论转码后杀进程还是退出会话，这条消息都能回来并可重试。
                m.content = localRef;
                [self saveMessage:m context:job.dbContext];
            }
            [self postNotification:IMMediaSendMetaDidChangeNotification forMessage:m oldKey:nil]; // 比例已知，重排气泡
            [self uploadStoredJob:job byteCount:item.byteCount inMemoryData:item.data mimeType:item.mimeType fileName:item.fileName];
        });
    });
}

/// 起上传：≥分片阈值走分片（可断点续传），否则一次性 multipart。data 为 nil 时从落盘副本读（仅小文件）。
- (void)uploadStoredJob:(IMMediaSendJob *)job
              byteCount:(long long)byteCount
           inMemoryData:(NSData *)data
               mimeType:(NSString *)mimeType
               fileName:(NSString *)fileName {
    IMMessageModel *m = job.message;
    NSString *key = m.clientMsgID ?: @"";
    NSString *token = IMHTTPService.sharedService.currentToken;
    NSString *path = [[IMPendingMediaStore shared] filePathForLocalRef:m.content];
    if (token.length == 0 || (!path && data.length == 0)) { [self failJob:job]; return; }

    if (path && byteCount >= (long long)IMChunkedUploader.chunkedThresholdBytes) {
        [self startChunkedUploadForJob:job path:path fileName:(fileName ?: path.lastPathComponent) token:token];
        return;
    }

    __weak typeof(self) ws = self;
    void (^start)(NSData *) = ^(NSData *bytes) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (bytes.length == 0) { [self failJob:job]; return; }
        [IMHTTPService.sharedService uploadData:bytes fileName:(fileName ?: @"media.bin")
                                       mimeType:(mimeType ?: @"application/octet-stream") token:token
            progress:^(double fraction) {
                __strong typeof(ws) self2 = ws;
                if (!self2) { return; }
                // 分母用**媒体本体字节数**而非 multipart 整包（后者含 boundary/头，会比文件属性大一截）。
                self2.progressMap[key] = [IMUploadProgress uploadingWithFraction:fraction
                                                                      totalBytes:byteCount
                                                                        previous:self2.progressMap[key]];
                [self2 postNotification:IMMediaSendProgressDidChangeNotification forMessage:m oldKey:nil];
            }
            completion:^(NSString *url, NSString *contentType, NSError *error) {
                __strong typeof(ws) self2 = ws;
                if (!self2) { return; }
                if (job.cancelled) { [self2 advanceMediaQueueAfter:key]; return; } // 一次性上传无法中断，结果丢弃
                if (error || url.length == 0) { [self2 failJob:job]; return; }
                [self2 finishUploadedJob:job serverURL:url
                             contentType:(contentType ?: m.contentType ?: @"image")];
            }];
    };
    if (data) { start(data); return; }
    dispatch_async(_io, ^{ // 落盘副本读回（<8MB，量级安全），仍不占主线程
        NSData *bytes = [NSData dataWithContentsOfFile:path];
        dispatch_async(dispatch_get_main_queue(), ^{ start(bytes); });
    });
}

/// 分片上传（媒体与文件共用）：任务活在 IMChunkedUploader 单例，回调锚在本服务。
- (void)startChunkedUploadForJob:(IMMediaSendJob *)job path:(NSString *)path fileName:(NSString *)fileName token:(NSString *)token {
    IMMessageModel *m = job.message;
    NSString *key = m.clientMsgID ?: @"";
    NSString *pendingRef = m.content;
    IMChunkedUploadTask *task = [[IMChunkedUploader shared]
        uploadFileAtURL:[NSURL fileURLWithPath:path]
               fileName:fileName
                  token:token
                    key:key
               resumeID:[[IMPendingMediaStore shared] uploadIDForLocalRef:pendingRef]];
    // 分片作业可暂停：立即标记（中心按钮显 ⏸），不等第一片回调。
    int64_t pendingBytes = [[IMPendingMediaStore shared] byteSizeForLocalRef:pendingRef];
    IMUploadProgress *initial = [IMUploadProgress uploadingWithFraction:
        (task.totalBytes > 0 ? (double)task.sentBytes / (double)task.totalBytes : 0)
                                                             totalBytes:(task.totalBytes > 0 ? task.totalBytes : pendingBytes)
                                                               previous:self.progressMap[key]];
    initial.pausable = YES;
    initial.pausedByUser = task.paused;
    self.progressMap[key] = initial;
    [self postNotification:IMMediaSendProgressDidChangeNotification forMessage:m oldKey:nil];
    __weak typeof(self) ws = self;
    task.uploadIDHandler = ^(NSString *uploadID) {
        [[IMPendingMediaStore shared] setUploadID:uploadID forLocalRef:pendingRef]; // 跨启动续传的锚点
    };
    task.progressHandler = ^(int64_t sent, int64_t total) {
        __strong typeof(ws) self = ws;
        if (!self || job.cancelled) { return; }
        double fraction = total > 0 ? (double)sent / (double)total : 0;
        IMUploadProgress *p = [IMUploadProgress uploadingWithFraction:fraction totalBytes:total
                                                             previous:self.progressMap[key]];
        p.pausable = YES;
        p.pausedByUser = self.progressMap[key].pausedByUser;
        self.progressMap[key] = p;
        [self postNotification:IMMediaSendProgressDidChangeNotification forMessage:m oldKey:nil];
    };
    task.completionHandler = ^(NSString *url, NSString *contentType, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || job.cancelled) { return; }
        if (error || url.length == 0) { [self failJob:job]; return; }
        [self finishUploadedJob:job serverURL:url
                    contentType:([m.contentType isEqualToString:@"file"] ? @"file"
                                                                         : (contentType ?: m.contentType ?: @"image"))];
    };
}

#pragma mark 入列（文件）

- (void)enqueueFileMessage:(IMMessageModel *)m
                    toUser:(NSString *)toUser
                 dbContext:(IMDatabaseAccountContext *)dbContext {
    NSString *key = m.clientMsgID ?: @"";
    NSString *path = [[IMPendingMediaStore shared] filePathForLocalRef:m.content];
    if (key.length == 0 || !path) { return; }
    if ([[IMChunkedUploader shared] taskForKey:key] && _jobs[key]) { return; } // 已在跑：幂等
    IMMediaSendJob *job = [IMMediaSendJob new];
    job.message = m;
    job.toUser = toUser ?: @"";
    job.dbContext = dbContext;
    _jobs[key] = job;
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self failJob:job]; return; }
    [self startChunkedUploadForJob:job path:path fileName:(m.fileName ?: path.lastPathComponent) token:token];
}

#pragma mark 重试

- (BOOL)retryMessage:(IMMessageModel *)m
              toUser:(NSString *)toUser
           dbContext:(IMDatabaseAccountContext *)dbContext {
    NSString *key = m.clientMsgID ?: @"";
    NSString *path = [[IMPendingMediaStore shared] filePathForLocalRef:m.content];
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (key.length == 0 || !path || token.length == 0) { return NO; }
    if (_jobs[key]) { return YES; } // 已在跑（如后台仍在上传），不重复入列

    long long byteCount = [[IMPendingMediaStore shared] byteSizeForLocalRef:m.content];
    if (byteCount <= 0) { return NO; }
    IMMediaSendJob *job = [IMMediaSendJob new];
    job.message = m;
    job.toUser = toUser ?: @"";
    job.dbContext = dbContext;
    _jobs[key] = job;
    [_failedConvs removeObject:m.convID ?: @""]; // 重新入列即摘掉列表的失败标
    m.status = IMMessageStatusSending;
    [self saveMessage:m context:dbContext];
    self.progressMap[key] = [IMUploadProgress uploadingWithFraction:0 totalBytes:byteCount previous:nil];
    IMLogWithTag(IMLogTagMedia, @"media_retry conv_id=%@ client_msg_id=%@ content_type=%@ bytes=%lld",
                 m.convID, key, m.contentType ?: @"", byteCount);
    BOOL isVideo = [m.contentType isEqualToString:@"video"];
    NSString *fileName = m.fileName ?: path.lastPathComponent;
    NSString *mime = [m.contentType isEqualToString:@"file"] ? @"application/octet-stream"
                   : (isVideo ? @"video/mp4" : @"image/jpeg");
    [self uploadStoredJob:job byteCount:byteCount inMemoryData:nil mimeType:mime fileName:fileName];
    [self postNotification:IMMediaSendProgressDidChangeNotification forMessage:m oldKey:nil];
    return YES;
}

#pragma mark 暂停 / 取消

- (BOOL)togglePauseForMessage:(IMMessageModel *)m {
    NSString *key = m.clientMsgID ?: @"";
    IMChunkedUploadTask *task = [[IMChunkedUploader shared] taskForKey:key];
    if (!task) { return NO; } // 一次性小上传/转码期：无可暂停的任务
    if (task.paused) {
        [task resume]; // 恢复先问服务端 status 拿 offset，服务端才是"传到哪了"的唯一权威
        self.progressMap[key].pausedByUser = NO;
    } else {
        [task pause];  // 停在分片边界，已传字节保留在服务端
        self.progressMap[key].pausedByUser = YES;
    }
    [self postNotification:IMMediaSendProgressDidChangeNotification forMessage:m oldKey:nil];
    return YES;
}

- (void)cancelMessage:(IMMessageModel *)m dbContext:(IMDatabaseAccountContext *)dbContext {
    NSString *key = m.clientMsgID ?: @"";
    IMMediaSendJob *job = _jobs[key];
    job.cancelled = YES;
    if (m.status == IMMessageStatusFailed) { [_failedConvs removeObject:m.convID ?: @""]; }
    [[[IMChunkedUploader shared] taskForKey:key] cancel]; // 分片任务立即停；一次性上传由完成回调按 cancelled 丢弃
    [_mediaQueue removeObject:key];
    [self.progressMap removeObjectForKey:key];
    [self.previews removeObjectForKey:key];
    [[IMPendingMediaStore shared] removeLocalRef:m.content]; // content 非 pending 引用时是 no-op
    [self performDB:(job.dbContext ?: dbContext) block:^(IMDatabase *db) { [db deleteMessage:m]; }];
    [_jobs removeObjectForKey:key];
    IMLogWithTag(IMLogTagMedia, @"media_send_cancelled conv_id=%@ client_msg_id=%@ content_type=%@",
                 m.convID, key, m.contentType ?: @"");
    [[NSNotificationCenter defaultCenter] postNotificationName:IMMediaSendDidCancelNotification object:self userInfo:@{
        kIMMediaSendConvIDKey: m.convID ?: @"",
        kIMMediaSendClientMsgIDKey: key,
        kIMMediaSendMessageKey: m,
    }];
    // 推进队列：advance 内部按 _currentMediaKey 守卫——不是当前作业则 no-op；
    // 转码/一次性上传仍悬着的回调稍后再 advance 一次也会因守卫已清而无害。
    [self advanceMediaQueueAfter:key];
}

#pragma mark 完成 / 失败

/// 上传完成 → （视频）补传封面 → socket 正式发送。
- (void)finishUploadedJob:(IMMediaSendJob *)job serverURL:(NSString *)url contentType:(NSString *)ct {
    IMMessageModel *m = job.message;
    NSString *oldKey = m.clientMsgID ?: @"";
    UIImage *preview = self.previews[oldKey];
    NSString *token = IMHTTPService.sharedService.currentToken;
    // 视频封面：把首帧预览 JPEG 上传作 poster（收端——尤其解不了 HEVC 的 Web——直显封面免解码）。
    if ([ct isEqualToString:@"video"] && preview && token.length > 0) {
        __weak typeof(self) ws = self;
        dispatch_async(_io, ^{ // JPEG 编码不占主线程
            NSData *posterJPEG = UIImageJPEGRepresentation(preview, 0.8);
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(ws) self = ws;
                if (!self) { return; }
                if (posterJPEG.length == 0) { [self dispatchJob:job serverURL:url contentType:ct poster:@""]; return; }
                [IMHTTPService.sharedService uploadData:posterJPEG fileName:@"poster.jpg" mimeType:@"image/jpeg" token:token
                    completion:^(NSString *posterURL, NSString *pct, NSError *perr) {
                        __strong typeof(ws) self2 = ws;
                        if (!self2) { return; }
                        [self2 dispatchJob:job serverURL:url contentType:ct
                                    poster:(perr ? @"" : (posterURL ?: @""))]; // 封面失败不阻塞发送
                    }];
            });
        });
        return;
    }
    [self dispatchJob:job serverURL:url contentType:ct poster:@""];
}

/// socket 正式发送 + 落库换真实 ID + 清理本地副本。
- (void)dispatchJob:(IMMediaSendJob *)job serverURL:(NSString *)url contentType:(NSString *)ct poster:(NSString *)poster {
    IMMessageModel *m = job.message;
    NSString *oldKey = m.clientMsgID ?: @"";
    NSString *pendingRef = m.content;
    NSString *host = IMHTTPService.sharedService.host;
    UIImage *preview = self.previews[oldKey];
    // 预览种进加载器缓存：气泡切到服务器 URL 时直接命中，不闪图。
    if (preview) {
        NSString *full = IMMediaFullURL(url, host);
        if ([ct isEqualToString:@"video"]) { [[IMVideoThumbnailLoader shared] cachePoster:preview forURL:full]; }
        else if ([ct isEqualToString:@"image"]) { [[IMImageLoader shared] cacheImage:preview forURL:full]; }
    }

    IMDatabaseAccountContext *ctx = job.dbContext;
    __weak typeof(self) ws = self;
    IMSendCompletion ackCompletion = ^(BOOL success, NSError *error, int64_t convSeq) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        m.status = success ? IMMessageStatusSent : IMMessageStatusFailed;
        // 被拒收 → 服务端友好文案挂 note（被拉黑 200102 / 禁言 300004 / 非群成员 300203 / 全员禁言 300206）。
        m.note = (!success && (error.code == 200102 || error.code == 300004 ||
                               error.code == 300203 || error.code == 300206)) ? error.localizedDescription : nil;
        m.convSeq = convSeq;
        [self saveMessage:m context:ctx];
        [[NSNotificationCenter defaultCenter] postNotificationName:IMMediaSendAckNotification object:self userInfo:@{
            kIMMediaSendConvIDKey: m.convID ?: @"",
            kIMMediaSendClientMsgIDKey: m.clientMsgID ?: @"",
            kIMMediaSendSuccessKey: @(success),
            kIMMediaSendConvSeqKey: @(convSeq),
            kIMMediaSendMessageKey: m,
        }];
    };

    NSString *realID = nil;
    if ([ct isEqualToString:@"file"]) {
        realID = [IMSocketManager.sharedManager sendFile:url fileName:(m.fileName ?: @"file")
                                                fileSize:m.fileSize toConv:m.convID toUser:job.toUser
                                              completion:ackCompletion];
    } else {
        IMMediaAttributes *attrs = [IMMediaAttributes attributesWithGroupID:m.groupID poster:poster];
        attrs.pixelWidth = m.mediaW;
        attrs.pixelHeight = m.mediaH;
        attrs.durationMillis = m.duration;
        attrs.fileSize = m.fileSize;
        realID = [IMSocketManager.sharedManager sendMedia:url contentType:ct
                                                   toConv:m.convID toUser:job.toUser
                                               attributes:attrs completion:ackCompletion];
    }

    // 消息行按 client_msg_id 认：先把库里的临时键改成真实 ID，否则随后的 save 会插出重复行。
    NSString *convID = m.convID;
    [self performDB:job.dbContext block:^(IMDatabase *db) {
        [db replaceClientMsgID:oldKey withClientMsgID:realID inConv:convID];
    }];
    m.clientMsgID = realID;
    m.content = url;
    m.contentType = ct;
    m.poster = poster.length > 0 ? poster : nil;
    [self saveMessage:m context:job.dbContext];
    if ([ct isEqualToString:@"file"] && realID.length > 0) {
        [self performDB:job.dbContext block:^(IMDatabase *db) {
            [db cacheSentFiles:@[@{ @"server_msg_id": realID ?: @"", @"url": url ?: @"",
                                    @"name": m.fileName ?: @"", @"size": @(m.fileSize),
                                    @"timestamp": @(m.timestamp) }]];
        }];
    }
    if (preview && realID.length > 0) { self.previews[realID] = preview; }
    [self.previews removeObjectForKey:oldKey];
    [self.progressMap removeObjectForKey:oldKey];
    // 视频副本不删，收编为"原视频"缓存（字节与服务器完全相同）：自己发的视频重开查看器
    // 立即本地播放、不显「查看原视频」chip、不重新拉流。图片本就有缩略图缓存，副本照删。
    NSString *pendingPath = [[IMPendingMediaStore shared] filePathForLocalRef:pendingRef];
    if ([ct isEqualToString:@"video"] && pendingPath) {
        [IMOriginalVideoCache adoptFileAtPath:pendingPath forFullURL:IMMediaFullURL(url, host)];
    }
    [[IMPendingMediaStore shared] removeLocalRef:pendingRef]; // 已成功发出（文件已被收编时只清旁挂记录）
    [_jobs removeObjectForKey:oldKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:IMMediaSendDidDispatchNotification object:self userInfo:@{
        kIMMediaSendConvIDKey: convID ?: @"",
        kIMMediaSendOldClientMsgIDKey: oldKey,
        kIMMediaSendClientMsgIDKey: realID ?: @"",
        kIMMediaSendMessageKey: m,
    }];
    [self advanceMediaQueueAfter:oldKey];
}

- (void)failJob:(IMMediaSendJob *)job {
    IMMessageModel *m = job.message;
    NSString *key = m.clientMsgID ?: @"";
    m.status = IMMessageStatusFailed;
    [self saveMessage:m context:job.dbContext]; // 失败也要落库（content 为空的行会被拒，见 saveMessage）
    IMLogWarnWithTag(IMLogTagMedia, @"media_send_failed conv_id=%@ client_msg_id=%@ content_type=%@ media_w=%ld media_h=%ld bytes=%lld",
                     m.convID, key, m.contentType ?: @"", (long)m.mediaW, (long)m.mediaH, m.fileSize);
    self.progressMap[key] = [IMUploadProgress failedProgress];
    [_failedConvs addObject:m.convID ?: @""];
    [_jobs removeObjectForKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:IMMediaSendDidFailNotification object:self userInfo:@{
        kIMMediaSendConvIDKey: m.convID ?: @"",
        kIMMediaSendClientMsgIDKey: key,
        kIMMediaSendMessageKey: m,
    }];
    [self advanceMediaQueueAfter:key];
}

/// 当前媒体作业结束（成功/失败都算）→ 推进队列。文件作业/重试作业不在媒体队列里，key 对不上就不动。
- (void)advanceMediaQueueAfter:(NSString *)key {
    if (!_mediaProcessing || ![key isEqualToString:_currentMediaKey]) { return; }
    _mediaProcessing = NO;
    _currentMediaKey = nil;
    [self processNextMediaJob];
}

#pragma mark 基础设施

- (void)postNotification:(NSNotificationName)name forMessage:(IMMessageModel *)m oldKey:(NSString *)oldKey {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
        kIMMediaSendConvIDKey: m.convID ?: @"",
        kIMMediaSendClientMsgIDKey: m.clientMsgID ?: @"",
        kIMMediaSendMessageKey: m,
    }];
    if (oldKey) { info[kIMMediaSendOldClientMsgIDKey] = oldKey; }
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self userInfo:info];
}

/// 落库统一收口：content 为空的行不落（重进会话显示不出内容也无法重试，只会留下永久空气泡）。
- (void)saveMessage:(IMMessageModel *)m context:(IMDatabaseAccountContext *)ctx {
    if (m.content.length == 0) { return; }
    [self performDB:ctx block:^(IMDatabase *db) { [db saveMessage:m]; }];
}

- (void)performDB:(IMDatabaseAccountContext *)ctx block:(void (^)(IMDatabase *db))block {
    if (!ctx) { return; }
    [IMDatabase.sharedDatabase performWithAccountContext:ctx block:block];
}

@end
