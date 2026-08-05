//  IMRemoteLogSink.m

#import "IMRemoteLogSink.h"
#import "IMHTTPService.h"

/// 缓冲上限：超过则丢最旧的，防止服务器不可达时内存无限增长。
static const NSUInteger kIMLogSinkMaxBuffered = 1000;
/// flush 周期（秒）：攒批发送，避免每条日志一次请求。
static const NSTimeInterval kIMLogSinkFlushInterval = 2.0;
/// 单次上报最多带多少行（与服务端 1MB/批上限留足余量）。
static const NSUInteger kIMLogSinkMaxBatch = 200;

@interface IMRemoteLogSink ()
@property (nonatomic, strong) dispatch_queue_t sinkQueue;   // 串行化缓冲读写与 flush
@property (nonatomic, strong) dispatch_source_t flushTimer;
@property (nonatomic, strong) NSMutableArray<NSString *> *buffer; // 每元素为一行 NDJSON
@property (nonatomic, strong) NSURLSession *session;        // 裸 session，不走 IMHTTPService（避免自我循环）
@end

@implementation IMRemoteLogSink

- (instancetype)init {
    if (self = [super init]) {
        _sinkQueue = dispatch_queue_create("com.libeyond.imlog.sink", DISPATCH_QUEUE_SERIAL);
        _buffer = [NSMutableArray array];
        NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        cfg.timeoutIntervalForRequest = 5;
        cfg.HTTPShouldUsePipelining = YES;
        _session = [NSURLSession sessionWithConfiguration:cfg];
        [self startTimer];
    }
    return self;
}

- (void)startTimer {
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.sinkQueue);
    uint64_t ns = (uint64_t)(kIMLogSinkFlushInterval * NSEC_PER_SEC);
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, ns), ns, ns / 4);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(t, ^{ [weakSelf flushLocked]; });
    dispatch_resume(t);
    self.flushTimer = t;
}

#pragma mark - DDLogger

// DDLog 在其日志队列串行调用本方法。这里只做最小工作：格式化成一行 NDJSON，投到自己的队列缓冲。
// **切勿在此调用任何 DDLog/IMLog**，否则自我递归。
- (void)logMessage:(DDLogMessage *)logMessage {
    NSString *rendered = self.logFormatter
        ? [self.logFormatter formatLogMessage:logMessage]
        : logMessage.message;
    if (rendered.length == 0) { return; }

    NSDictionary *obj = @{
        @"ts": @((int64_t)(logMessage.timestamp.timeIntervalSince1970 * 1000)),
        @"level": IMLogFlagName(logMessage.flag),
        @"msg": rendered,
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL];
    if (!json) { return; }
    NSString *line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    if (line.length == 0) { return; }

    dispatch_async(self.sinkQueue, ^{
        [self.buffer addObject:line];
        // 有界：超限丢最旧的（保留最近 kIMLogSinkMaxBuffered 行）。
        if (self.buffer.count > kIMLogSinkMaxBuffered) {
            [self.buffer removeObjectsInRange:NSMakeRange(0, self.buffer.count - kIMLogSinkMaxBuffered)];
        }
    });
}

#pragma mark - flush（仅在 sinkQueue 调用）

- (void)flushLocked {
    if (self.buffer.count == 0) { return; }
    NSString *host = IMHTTPService.sharedService.host;
    if (host.length == 0) { return; } // 尚未登录/未知服务器：继续攒，别丢

    NSString *urlStr = [NSString stringWithFormat:@"http://%@/__devlog", host];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { [self.buffer removeAllObjects]; return; } // host 非法：清掉避免死攒

    NSUInteger n = MIN(self.buffer.count, kIMLogSinkMaxBatch);
    NSArray<NSString *> *batch = [self.buffer subarrayWithRange:NSMakeRange(0, n)];
    [self.buffer removeObjectsInRange:NSMakeRange(0, n)];

    NSData *body = [[batch componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/x-ndjson" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = body;
    // fire-and-forget：结果不关心、不重试、不记日志（记了又循环）。发送失败的这一批就丢了。
    [[self.session dataTaskWithRequest:req] resume];
}

/// DDLogFlag → 稳定的小写级别名（对齐后端 slog 与 LOGGING.md）。
static NSString *IMLogFlagName(DDLogFlag flag) {
    if (flag & DDLogFlagError)   { return @"error"; }
    if (flag & DDLogFlagWarning) { return @"warn"; }
    if (flag & DDLogFlagInfo)    { return @"info"; }
    if (flag & DDLogFlagDebug)   { return @"debug"; }
    return @"verbose";
}

@end
