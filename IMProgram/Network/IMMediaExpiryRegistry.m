//  IMMediaExpiryRegistry.m
#import "IMMediaExpiryRegistry.h"

NSString * const IMMediaExpiryDidChangeNotification = @"IMMediaExpiryDidChangeNotification";

@implementation IMMediaExpiryRegistry {
    NSMutableSet<NSString *> *_expired;
    NSMutableSet<NSString *> *_verifying; // 在途复验去重：同址不并发多次 ranged-GET
    NSMutableSet<NSString *> *_probed;    // 主动探测过且可达的地址（probeExpiredForURL: 每址只探一次）
    NSMutableDictionary<NSString *, NSMutableArray<void (^)(BOOL)> *> *_waiters; // 在途期间到来的复验回调（已含主线程派发）
    dispatch_queue_t _q; // 串行保护 _expired / _verifying / _probed / _waiters
}

+ (instancetype)shared {
    static IMMediaExpiryRegistry *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMMediaExpiryRegistry new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _expired = [NSMutableSet set];
        _verifying = [NSMutableSet set];
        _probed = [NSMutableSet set];
        _waiters = [NSMutableDictionary dictionary];
        _q = dispatch_queue_create("im.media.expiry", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)isExpiredURL:(NSString *)url {
    if (url.length == 0) { return NO; }
    __block BOOL v = NO;
    dispatch_sync(_q, ^{ v = [self->_expired containsObject:url]; });
    return v;
}

- (void)markExpiredURL:(NSString *)url {
    if (url.length == 0) { return; }
    __block BOOL added = NO;
    dispatch_sync(_q, ^{
        if (![self->_expired containsObject:url]) { [self->_expired addObject:url]; added = YES; }
    });
    if (!added) { return; } // 已在表内，不重复广播
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:IMMediaExpiryDidChangeNotification
                                                          object:nil
                                                        userInfo:@{ @"url": url }];
    });
}

- (void)verifyExpiredForURL:(NSString *)url completion:(void (^)(BOOL))completion {
    void (^done)(BOOL) = ^(BOOL e) {
        if (!completion) { return; }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(e); });
    };
    if (url.length == 0) { done(NO); return; }
    if ([self isExpiredURL:url]) { done(YES); return; }
    NSURL *u = [NSURL URLWithString:url];
    if (!u || !([u.scheme isEqualToString:@"http"] || [u.scheme isEqualToString:@"https"])) { done(NO); return; }
    // 在途去重：同一 URL 已有探测/复验在飞 → 不再发第二次 ranged-GET（避免滚动/多面并发把 404 探测打成小风暴，
    // code-review #4）；本次回调挂到在飞请求上、等它的真实结果（含 probeExpiredForURL: 发起的那次），
    // 不再直接答 NO——否则查看器恰在气泡探测在飞时打开，会把「已失效」误判成「无法播放」。
    __block BOOL alreadyInFlight = NO;
    dispatch_sync(_q, ^{
        alreadyInFlight = [self->_verifying containsObject:url];
        if (!alreadyInFlight) { [self->_verifying addObject:url]; }
        NSMutableArray *ws = self->_waiters[url];
        if (!ws) { ws = [NSMutableArray array]; self->_waiters[url] = ws; }
        [ws addObject:[done copy]]; // 发起者与后到者同走等待者表，由那一次请求统一回调
    });
    if (alreadyInFlight) { return; }
    [self sendRangedProbeForURL:u key:url];
}

- (void)probeExpiredForURL:(NSString *)url {
    if (url.length == 0) { return; }
    NSURL *u = [NSURL URLWithString:url];
    if (!u || !([u.scheme isEqualToString:@"http"] || [u.scheme isEqualToString:@"https"])) { return; }
    __block BOOL skip = NO;
    dispatch_sync(_q, ^{
        if ([self->_expired containsObject:url] || [self->_probed containsObject:url] || [self->_verifying containsObject:url]) { skip = YES; return; }
        [self->_probed addObject:url];
        [self->_verifying addObject:url];
    });
    if (skip) { return; }
    [self sendRangedProbeForURL:u key:url];
}

/// 复验 / 主动探测共用的 ranged-GET（`bytes=0-0`，只探状态码）。调用方须已把 key 放进 `_verifying`。
/// 完成：解锁在途 → 404/410 登记并广播 → 通知挂在这次请求上的等待者（verify 在飞期间到来的复验）。
- (void)sendRangedProbeForURL:(NSURL *)u key:(NSString *)url {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    [req setValue:@"bytes=0-0" forHTTPHeaderField:@"Range"];
    req.timeoutInterval = 12;
    __weak typeof(self) ws = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
        __strong typeof(ws) sq = ws;
        if (!sq) { return; }
        NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        BOOL expired = (code == 404 || code == 410);
        __block NSArray<void (^)(BOOL)> *waiters = nil;
        dispatch_sync(sq->_q, ^{
            [sq->_verifying removeObject:url];
            waiters = [sq->_waiters[url] copy];
            [sq->_waiters removeObjectForKey:url];
            // 主动探测遇网络错/5xx：不算探过，但冷却 30s 再放行——否则离线时每次 configure 都重发、滚动即风暴。
            if ((code == 0 || code >= 500) && [sq->_probed containsObject:url]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), sq->_q, ^{
                    [sq->_probed removeObject:url];
                });
            }
        });
        if (expired) { [sq markExpiredURL:url]; }
        for (void (^w)(BOOL) in waiters) { w(expired); } // 网络错/瞬时/可达：NO（不标失效，保留可重载）
    }] resume];
}

- (void)clear {
    dispatch_sync(_q, ^{ [self->_expired removeAllObjects]; [self->_probed removeAllObjects]; });
}

@end
