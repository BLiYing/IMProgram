//  IMMediaExpiryRegistry.m
#import "IMMediaExpiryRegistry.h"

NSString * const IMMediaExpiryDidChangeNotification = @"IMMediaExpiryDidChangeNotification";

@implementation IMMediaExpiryRegistry {
    NSMutableSet<NSString *> *_expired;
    NSMutableSet<NSString *> *_verifying; // 在途复验去重：同址不并发多次 ranged-GET
    dispatch_queue_t _q; // 串行保护 _expired / _verifying
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
    // 在途去重：同一 URL 已有复验在飞 → 本次不再发第二次 ranged-GET（避免滚动/多面并发把 404 探测打成小风暴，
    // code-review #4）。落地由那次在飞复验统一广播 IMMediaExpiryDidChangeNotification，各面下次渲染即命中 isExpiredURL。
    __block BOOL alreadyVerifying = NO;
    dispatch_sync(_q, ^{
        if ([self->_verifying containsObject:url]) { alreadyVerifying = YES; }
        else { [self->_verifying addObject:url]; }
    });
    if (alreadyVerifying) { done(NO); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    [req setValue:@"bytes=0-0" forHTTPHeaderField:@"Range"]; // 只探状态码，不拉整段
    req.timeoutInterval = 12;
    __weak typeof(self) ws = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req
                                                              completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
        __strong typeof(ws) sq = ws;
        if (sq) { dispatch_sync(sq->_q, ^{ [sq->_verifying removeObject:url]; }); } // 复验结束，解锁在途
        NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        if (code == 404 || code == 410) {
            [ws markExpiredURL:url];
            done(YES);
        } else {
            done(NO); // 网络错/瞬时/可达：不标失效（保留可重载）
        }
    }];
    [task resume];
}

- (void)clear {
    dispatch_sync(_q, ^{ [self->_expired removeAllObjects]; });
}

@end
