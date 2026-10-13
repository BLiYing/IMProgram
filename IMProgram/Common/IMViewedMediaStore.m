//  IMViewedMediaStore.m

#import "IMViewedMediaStore.h"
#import "IMDatabase.h"

NSNotificationName const IMViewedMediaDidChangeNotification = @"IMViewedMediaDidChangeNotification";

static const NSUInteger kIMViewedMediaMax = 500; // 与 Web `saveOptedIn` 的 slice(-500) 同口径

@implementation IMViewedMediaStore {
    NSUserDefaults *_defaults;
    NSMutableDictionary<NSString *, NSMutableOrderedSet<NSString *> *> *_cache; ///< uid → 有序集合（旧→新）
    dispatch_queue_t _queue;
}

+ (instancetype)shared {
    static IMViewedMediaStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[IMViewedMediaStore alloc] initWithDefaults:NSUserDefaults.standardUserDefaults]; });
    return s;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) {
        _defaults = defaults;
        _cache = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("im.viewedmedia", DISPATCH_QUEUE_SERIAL);
        _userIDProvider = ^NSString *{
            return IMDatabase.sharedDatabase.currentAccountContext.ownerUserID;
        };
    }
    return self;
}

static NSString *KeyForUser(NSString *uid) { return [@"im.viewedMedia." stringByAppendingString:uid]; }

- (nullable NSString *)currentUID {
    NSString *uid = self.userIDProvider ? self.userIDProvider() : nil;
    return uid.length > 0 ? uid : nil;
}

/// 取（并按需从磁盘载入）某账号的集合。调用方须在 _queue 内。
- (NSMutableOrderedSet<NSString *> *)setForUser:(NSString *)uid {
    NSMutableOrderedSet<NSString *> *s = _cache[uid];
    if (!s) {
        NSArray *stored = [_defaults arrayForKey:KeyForUser(uid)];
        s = [NSMutableOrderedSet orderedSet];
        for (id o in stored) { if ([o isKindOfClass:NSString.class]) { [s addObject:o]; } }
        _cache[uid] = s;
    }
    return s;
}

- (BOOL)isViewedURL:(NSString *)url {
    NSString *uid = [self currentUID];
    if (!uid || url.length == 0) { return NO; }
    __block BOOL hit = NO;
    dispatch_sync(_queue, ^{ hit = [[self setForUser:uid] containsObject:url]; });
    return hit;
}

- (void)markViewedURL:(NSString *)url {
    NSString *uid = [self currentUID];
    if (!uid || url.length == 0) { return; }
    __block BOOL added = NO;
    dispatch_sync(_queue, ^{
        NSMutableOrderedSet<NSString *> *s = [self setForUser:uid];
        if ([s containsObject:url]) { return; }
        [s addObject:url];
        while (s.count > kIMViewedMediaMax) { [s removeObjectAtIndex:0]; } // 丢最旧的
        [self->_defaults setObject:s.array forKey:KeyForUser(uid)];
        added = YES;
    });
    if (added) { [self postChangeWithURL:url]; }
}

- (void)clearCurrentUser {
    NSString *uid = [self currentUID];
    if (!uid) { return; }
    dispatch_sync(_queue, ^{
        [self->_cache removeObjectForKey:uid];
        [self->_defaults removeObjectForKey:KeyForUser(uid)];
    });
    [self postChangeWithURL:nil];
}

- (void)postChangeWithURL:(nullable NSString *)url {
    NSDictionary *info = url ? @{ @"url": url } : @{};
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:IMViewedMediaDidChangeNotification object:self userInfo:info];
    });
}

@end
