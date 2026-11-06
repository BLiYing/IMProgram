//  IMPendingLogoutQueue.m

#import "IMPendingLogoutQueue.h"

#import <Security/Security.h>
#import <UIKit/UIKit.h>

#import "IMHTTPService.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import "IMNetworkMonitor.h"

static NSString * const kIMPendingLogoutKeychainService = @"im.pendingLogout";
static NSString * const kIMPendingLogoutKeychainAccount = @"queue";
static NSString * const kIMEntryTokenKey = @"token";
static NSString * const kIMEntryURLKey = @"url";
static NSString * const kIMEntryAtKey = @"at";

/// 服务端续期凭据的绝对寿命是 180 天，会话届时已失效，这之后再存就只是白白留着一枚凭据。
static const NSTimeInterval kIMPendingLogoutMaxAge = 180 * 24 * 3600;
/// 正常情况下最多一两条。设上限是防止反复退出又长期连不上时无限累积，超出丢最旧的。
static const NSUInteger kIMPendingLogoutMaxEntries = 16;
static const NSTimeInterval kIMPendingLogoutDefaultRetryInterval = 60;
static const NSInteger kIMCodeRateLimited = 100002;
static const NSInteger kIMCodeInternal = 100003;

BOOL IMPendingLogoutShouldRetry(NSError *error) {
    if (!error) { return NO; }
    if (![IMHTTPService isBusinessError:error]) { return YES; } // 网络失败、非 JSON 响应（网关 502 / 老服务端 404）
    return error.code == kIMCodeRateLimited || error.code == kIMCodeInternal;
}

#pragma mark - Keychain

@implementation IMPendingLogoutKeychainStorage {
    NSString *_service;
}

- (instancetype)initWithService:(NSString *)service {
    if ((self = [super init])) { _service = [service copy]; }
    return self;
}

- (NSDictionary *)baseQuery {
    return @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: _service,
              (__bridge id)kSecAttrAccount: kIMPendingLogoutKeychainAccount };
}

- (BOOL)readData:(NSData **)data {
    NSMutableDictionary *query = [[self baseQuery] mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound) {
        *data = nil;
        return YES;
    }
    if (status != errSecSuccess) {
        IMLogWarnWithTag(IMLogTagHTTP, @"pending_logout_keychain_read_failed status=%d", (int)status);
        return NO;
    }
    *data = (__bridge_transfer NSData *)result;
    return YES;
}

- (BOOL)writeData:(NSData *)data {
    NSDictionary *query = [self baseQuery];
    if (!data) {
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status != errSecSuccess && status != errSecItemNotFound) {
            IMLogWarnWithTag(IMLogTagHTTP, @"pending_logout_keychain_delete_failed status=%d", (int)status);
            return NO;
        }
        return YES;
    }
    // AfterFirstUnlock：重试可能发生在后台被唤起时。ThisDeviceOnly：不进备份、不上 iCloud 钥匙串。
    NSDictionary *attributes = @{ (__bridge id)kSecValueData: data,
                                  (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly };
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *add = [query mutableCopy];
        [add addEntriesFromDictionary:attributes];
        status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
    if (status != errSecSuccess) {
        IMLogWarnWithTag(IMLogTagHTTP, @"pending_logout_keychain_write_failed status=%d", (int)status);
        return NO;
    }
    return YES;
}

@end

#pragma mark - Queue

@implementation IMPendingLogoutQueue {
    id<IMPendingLogoutStorage> _storage;
    IMPendingLogoutSender _sender;
    NSMutableArray<NSDictionary *> *_entries;
    BOOL _loaded;
    BOOL _started;
    BOOL _flushing;
    BOOL _flushAgain;
    BOOL _retryScheduled;
    NSSet<NSString *> *_passTokens; ///< 当前这一轮发的是哪些，用来判断中途有没有新入队的
}

+ (instancetype)shared {
    static IMPendingLogoutQueue *queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id<IMPendingLogoutStorage> storage = [[IMPendingLogoutKeychainStorage alloc] initWithService:kIMPendingLogoutKeychainService];
        queue = [[IMPendingLogoutQueue alloc] initWithStorage:storage sender:^(NSString *refreshToken, NSURL *url, void (^completion)(NSError *)) {
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
            req.HTTPMethod = @"POST";
            [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"refresh_token": refreshToken } options:0 error:NULL];
            req.timeoutInterval = 10;
            [IMHTTPService.sharedService runOKRequest:req fallback:IMLocalized(@"net.fallback.logout_failed") completion:completion];
        }];
    });
    return queue;
}

- (instancetype)initWithStorage:(id<IMPendingLogoutStorage>)storage sender:(IMPendingLogoutSender)sender {
    if ((self = [super init])) {
        _storage = storage;
        _sender = [sender copy];
        _entries = [NSMutableArray array];
        _retryInterval = kIMPendingLogoutDefaultRetryInterval;
        _now = [^{ return [NSDate date]; } copy];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSUInteger)pendingCount {
    [self loadIfNeeded];
    return _entries.count;
}

- (void)start {
    if (_started) { return; }
    _started = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(flush) name:IMNetworkDidBecomeReachableNotification object:nil];
    [center addObserver:self selector:@selector(flush) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self flush];
}

- (void)enqueueRefreshToken:(NSString *)refreshToken url:(NSURL *)url {
    if (refreshToken.length == 0 || url.absoluteString.length == 0) { return; }
    [self loadIfNeeded];
    [self removeEntriesWithToken:refreshToken];
    [_entries addObject:@{ kIMEntryTokenKey: refreshToken,
                           kIMEntryURLKey: url.absoluteString,
                           kIMEntryAtKey: @(self.now().timeIntervalSince1970) }];
    while (_entries.count > kIMPendingLogoutMaxEntries) { [_entries removeObjectAtIndex:0]; }
    [self persist];
    [self flush];
}

- (void)flush {
    [self loadIfNeeded];
    [self pruneExpired];
    if (_flushing) {
        _flushAgain = YES;
        return;
    }
    if (_entries.count == 0) {
        // Keychain 读失败（如设备尚未首次解锁）时这里也是空的，但盘上可能有待吊销的凭据：别当成没事，稍后再读。
        if (!_loaded) { [self scheduleRetry]; }
        return;
    }
    _flushing = YES;
    _passTokens = [NSSet setWithArray:[_entries valueForKey:kIMEntryTokenKey]];
    [self sendEntries:[_entries copy] index:0 anyRetry:NO];
}

/// 逐条发送。一条失败不中断后面的：不同条目可能属于不同服务器，这台连不上不代表那台也连不上。
- (void)sendEntries:(NSArray<NSDictionary *> *)entries index:(NSUInteger)index anyRetry:(BOOL)anyRetry {
    if (index >= entries.count) {
        [self finishPassWithRetry:anyRetry];
        return;
    }
    NSDictionary *entry = entries[index];
    NSString *token = entry[kIMEntryTokenKey];
    NSURL *url = [NSURL URLWithString:entry[kIMEntryURLKey]];
    if (!url) { // 存入时已校验，这里只防存储内容损坏；这条永远发不出去，留着没有意义
        [self removeEntriesWithToken:token];
        [self persist];
        [self sendEntries:entries index:index + 1 anyRetry:anyRetry];
        return;
    }
    __weak typeof(self) weakSelf = self;
    _sender(token, url, ^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        BOOL retry = IMPendingLogoutShouldRetry(error);
        if (retry) {
            IMLogWarnWithTag(IMLogTagHTTP, @"pending_logout_retry_later code=%ld", (long)error.code);
        } else {
            if (error) { IMLogWarnWithTag(IMLogTagHTTP, @"pending_logout_rejected code=%ld", (long)error.code); }
            [self removeEntriesWithToken:token];
            [self persist];
        }
        [self sendEntries:entries index:index + 1 anyRetry:anyRetry || retry];
    });
}

- (void)finishPassWithRetry:(BOOL)anyRetry {
    _flushing = NO;
    BOOL again = _flushAgain;
    _flushAgain = NO;
    // 只有中途新入队了没发过的才立刻再跑一轮。回前台和网络恢复的通知常常一起到，不加这个判断，
    // 刚失败的条目会被连环重发到一个连不上的服务器。
    if (again) {
        NSArray *tokens = [_entries valueForKey:kIMEntryTokenKey];
        for (NSString *token in tokens) {
            if (![_passTokens containsObject:token]) {
                [self flush];
                return;
            }
        }
    }
    if (anyRetry) { [self scheduleRetry]; }
}

/// 兜底：一直停在登录页时既没有回前台也没有网络跃迁（服务端临时故障就是这样），靠定时重试。
- (void)scheduleRetry {
    if (_retryScheduled) { return; }
    _retryScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.retryInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        self->_retryScheduled = NO;
        [self flush];
    });
}

#pragma mark - 持久化

/// 读失败就保持 _loaded=NO，下次再读。内存里已有的条目与读到的合并，不会丢。
- (void)loadIfNeeded {
    if (_loaded) { return; }
    NSData *data = nil;
    if (![_storage readData:&data]) { return; }
    _loaded = YES;
    NSArray *stored = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![stored isKindOfClass:NSArray.class]) { stored = @[]; }
    NSMutableArray<NSDictionary *> *merged = [NSMutableArray array];
    for (id item in stored) {
        if ([self isValidEntry:item]) { [merged addObject:item]; }
    }
    for (NSDictionary *entry in _entries) {
        BOOL duplicate = [[merged valueForKey:kIMEntryTokenKey] containsObject:entry[kIMEntryTokenKey]];
        if (!duplicate) { [merged addObject:entry]; }
    }
    BOOL hadInMemory = _entries.count > 0;
    _entries = merged;
    if (hadInMemory) { [self persist]; }
}

- (BOOL)isValidEntry:(id)item {
    if (![item isKindOfClass:NSDictionary.class]) { return NO; }
    NSDictionary *entry = item;
    return [entry[kIMEntryTokenKey] isKindOfClass:NSString.class] && [entry[kIMEntryTokenKey] length] > 0
        && [entry[kIMEntryURLKey] isKindOfClass:NSString.class]
        && [entry[kIMEntryAtKey] isKindOfClass:NSNumber.class];
}

- (void)removeEntriesWithToken:(NSString *)token {
    NSIndexSet *matches = [_entries indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
        return [entry[kIMEntryTokenKey] isEqualToString:token];
    }];
    [_entries removeObjectsAtIndexes:matches];
}

- (void)pruneExpired {
    NSTimeInterval cutoff = self.now().timeIntervalSince1970 - kIMPendingLogoutMaxAge;
    NSIndexSet *expired = [_entries indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
        return [entry[kIMEntryAtKey] doubleValue] < cutoff;
    }];
    if (expired.count == 0) { return; }
    [_entries removeObjectsAtIndexes:expired];
    [self persist];
}

- (void)persist {
    if (!_loaded) { return; } // 没读到已存内容前不能写，否则覆盖掉；loadIfNeeded 成功后会合并并补写
    NSData *data = _entries.count > 0 ? [NSJSONSerialization dataWithJSONObject:_entries options:0 error:NULL] : nil;
    [_storage writeData:data]; // 写失败已由 storage 记日志；条目还在内存里，进程活着就继续重试
}

@end
