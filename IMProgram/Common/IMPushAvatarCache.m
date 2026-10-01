//  IMPushAvatarCache.m

#import "IMPushAvatarCache.h"
#import "IMPushSender.h"

static const NSTimeInterval kIMAvatarMaxAge = 30 * 24 * 3600;
static const unsigned long long kIMAvatarMaxBytes = 20ull * 1024 * 1024;
static const NSTimeInterval kIMEvictInterval = 24 * 3600;
static NSString *const kIMLastKnownKey = @"im_push_avatar_last_known"; // owner → 文件名
static NSString *const kIMLastEvictKey = @"im_push_avatar_last_evict";

@implementation IMPushAvatarCacheEntry
+ (instancetype)entryWithName:(NSString *)name bytes:(unsigned long long)bytes lastUsed:(NSDate *)lastUsed {
    IMPushAvatarCacheEntry *e = [IMPushAvatarCacheEntry new];
    e->_name = [name copy];
    e->_bytes = bytes;
    e->_lastUsed = lastUsed;
    return e;
}
@end

NSString *IMPushAvatarCacheFileName(NSString *avatarPath) {
    if (![avatarPath hasPrefix:@"/avatars/"] || [avatarPath containsString:@".."]) { return nil; }
    NSString *name = [avatarPath substringFromIndex:@"/avatars/".length];
    if (name.length == 0 || [name containsString:@"/"]) { return nil; }
    return name;
}

NSArray<NSString *> *IMPushAvatarCachePlanEviction(NSArray<IMPushAvatarCacheEntry *> *entries, NSDate *now,
                                                   NSTimeInterval maxAge, unsigned long long maxBytes) {
    NSMutableArray<NSString *> *evict = [NSMutableArray array];
    NSMutableArray<IMPushAvatarCacheEntry *> *kept = [NSMutableArray array];
    unsigned long long total = 0;
    for (IMPushAvatarCacheEntry *e in entries) {
        if ([now timeIntervalSinceDate:e.lastUsed] > maxAge) {
            [evict addObject:e.name];
        } else {
            [kept addObject:e];
            total += e.bytes;
        }
    }
    [kept sortUsingComparator:^NSComparisonResult(IMPushAvatarCacheEntry *a, IMPushAvatarCacheEntry *b) {
        return [a.lastUsed compare:b.lastUsed];
    }];
    for (IMPushAvatarCacheEntry *e in kept) {
        if (total <= maxBytes) { break; }
        [evict addObject:e.name];
        total -= e.bytes;
    }
    return evict;
}

@implementation IMPushAvatarCache {
    NSURL *_dir;
    NSUserDefaults *_shared;
}

+ (instancetype)shared {
    static IMPushAvatarCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [IMPushAvatarCache new]; });
    return cache;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURL *container = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:IMAppGroupID];
        if (container != nil) {
            _dir = [container URLByAppendingPathComponent:@"Library/Caches/push-avatars" isDirectory:YES];
            [NSFileManager.defaultManager createDirectoryAtURL:_dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        _shared = [[NSUserDefaults alloc] initWithSuiteName:IMAppGroupID];
    }
    return self;
}

- (NSData *)dataForFileName:(NSString *)name {
    if (_dir == nil || name.length == 0) { return nil; }
    NSURL *url = [_dir URLByAppendingPathComponent:name];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data != nil) { // 记「最后使用时间」，清理按它算
        [NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate: NSDate.date } ofItemAtPath:url.path error:nil];
    }
    return data;
}

- (NSData *)dataForAvatarPath:(NSString *)avatarPath {
    return [self dataForFileName:IMPushAvatarCacheFileName(avatarPath)];
}

- (void)storeData:(NSData *)data forAvatarPath:(NSString *)avatarPath owner:(NSString *)owner {
    NSString *name = IMPushAvatarCacheFileName(avatarPath);
    if (_dir == nil || name == nil || data.length == 0) { return; }
    [data writeToURL:[_dir URLByAppendingPathComponent:name] atomically:YES];
    @synchronized (self) {
        NSMutableDictionary *last = [[_shared dictionaryForKey:kIMLastKnownKey] mutableCopy] ?: [NSMutableDictionary dictionary];
        last[owner] = name;
        [_shared setObject:last forKey:kIMLastKnownKey];
    }
}

- (NSData *)lastKnownDataForOwner:(NSString *)owner {
    NSString *name = nil;
    @synchronized (self) {
        name = [_shared dictionaryForKey:kIMLastKnownKey][owner];
    }
    return [name isKindOfClass:NSString.class] ? [self dataForFileName:name] : nil;
}

- (void)evictIfNeeded {
    if (_dir == nil) { return; }
    NSDate *now = NSDate.date;
    NSDate *lastRun = [_shared objectForKey:kIMLastEvictKey];
    if ([lastRun isKindOfClass:NSDate.class] && [now timeIntervalSinceDate:lastRun] < kIMEvictInterval) { return; }
    [_shared setObject:now forKey:kIMLastEvictKey];

    NSArray<NSURLResourceKey> *keys = @[ NSURLFileSizeKey, NSURLContentModificationDateKey ];
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:_dir includingPropertiesForKeys:keys
                                                                              options:0 error:nil];
    NSMutableArray<IMPushAvatarCacheEntry *> *entries = [NSMutableArray array];
    for (NSURL *f in files) {
        NSDictionary *v = [f resourceValuesForKeys:keys error:nil];
        [entries addObject:[IMPushAvatarCacheEntry entryWithName:f.lastPathComponent
                                                           bytes:[v[NSURLFileSizeKey] unsignedLongLongValue]
                                                        lastUsed:v[NSURLContentModificationDateKey] ?: now]];
    }
    NSArray<NSString *> *evict = IMPushAvatarCachePlanEviction(entries, now, kIMAvatarMaxAge, kIMAvatarMaxBytes);
    for (NSString *name in evict) {
        [NSFileManager.defaultManager removeItemAtURL:[_dir URLByAppendingPathComponent:name] error:nil];
    }
    if (evict.count == 0) { return; }
    @synchronized (self) { // 被删掉的文件不再当「最近一次的头像」
        NSMutableDictionary *last = [[_shared dictionaryForKey:kIMLastKnownKey] mutableCopy];
        if (last == nil) { return; }
        NSSet<NSString *> *gone = [NSSet setWithArray:evict];
        for (NSString *owner in last.allKeys) {
            if ([gone containsObject:last[owner]]) { [last removeObjectForKey:owner]; }
        }
        [_shared setObject:last forKey:kIMLastKnownKey];
    }
}

@end
