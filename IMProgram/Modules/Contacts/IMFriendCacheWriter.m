//  IMFriendCacheWriter.m

#import "IMFriendCacheWriter.h"
#import "IMDatabase.h"
#import "IMDatabase+RosterCache.h"
#import "IMUserCard.h"
#import "IMLog.h"

/// 指纹所属的账号上下文（同一激活代次是同一个对象）；换号 / 重新激活后旧指纹作废。
static IMDatabaseAccountContext *sFingerprintContext;
/// 库里**已写成**的那份好友快照的内容指纹；nil = 还不知道库里是什么（下次必写）。
static NSDictionary<NSString *, NSArray *> *sFingerprint;
/// 已入队、还没写完的最后一份名单的指纹（及其账号上下文）。写队列串行，排空后库里就是它，
/// 所以比较时它优先于 sFingerprint——否则两页先后拿到同一份新名单，在第一笔写成之前第二页
/// 仍会和旧指纹比出「变了」，再整表写一遍。写成 / 写失败后清掉（失败即回退到 sFingerprint）。
static IMDatabaseAccountContext *sPendingContext;
static NSDictionary<NSString *, NSArray *> *sPendingFingerprint;
/// 测试替身：非 nil 时代替真实落库（返回是否写成）。只在单测里设。
static BOOL (^sWriteOverride)(NSArray<IMUserCard *> *friends, IMDatabaseAccountContext *context);

/// 好友快照整表重写的串行队列：按发起顺序落库，后拉到的名单不会被先拉到的那份覆盖。
static dispatch_queue_t IMFriendCacheWriteQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("im.contacts.cache", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static void IMFriendCacheRecordFingerprint(NSDictionary<NSString *, NSArray *> *fingerprint,
                                           IMDatabaseAccountContext *context) {
    sFingerprintContext = context;
    sFingerprint = fingerprint;
}

/// 库里（或写队列排空后库里）对 context 而言会是哪份名单；nil = 不知道。
static NSDictionary<NSString *, NSArray *> *IMFriendCacheExpectedFingerprint(IMDatabaseAccountContext *context) {
    if (!context) { return nil; }
    if (sPendingFingerprint && sPendingContext == context) { return sPendingFingerprint; }
    return sFingerprintContext == context ? sFingerprint : nil;
}

/// 一笔写入结束（主线程）：写成则记为已知指纹；无论成败，若它仍是「最后入队」的那笔就清掉待写标记。
/// 写失败时库里仍是上一份，清掉待写后比较回到 sFingerprint，下次同一名单会重试写入。
static void IMFriendCacheFinishWrite(NSDictionary<NSString *, NSArray *> *fingerprint,
                                     IMDatabaseAccountContext *context, BOOL written) {
    if (written) { IMFriendCacheRecordFingerprint(fingerprint, context); }
    if (sPendingFingerprint == fingerprint) {
        sPendingFingerprint = nil;
        sPendingContext = nil;
    }
}

@implementation IMFriendCacheWriter

+ (NSArray<IMUserCard *> *)cachedFriendsWithContext:(IMDatabaseAccountContext *)context {
    __block NSArray<IMUserCard *> *cached = nil;
    BOOL read = [IMDatabase.sharedDatabase performWithAccountContext:context block:^(IMDatabase *database) {
        cached = database.cachedFriends;
    }];
    if (!read) { return @[]; }
    // 之后拉回来的名单跟它一样就不必整表重写（冷启动后的第一次刷新通常就是这种情况）。
    IMFriendCacheRecordFingerprint(IMCachedFriendsFingerprint(cached ?: @[]), context);
    return cached ?: @[];
}

/// 2000 人删了重插在 Mac 上约 16ms，而切 Tab 拉回来的名单几乎总是没变——变了才写，并挪到后台串行队列：
/// FMDatabaseQueue 线程安全；卡片解析后不再被改写；performWithAccountContext 会丢弃账号已切走的写入。
/// 锁序与主线程一致（IMDatabase 锁 → FMDB 队列），不会反向等待。
/// 比较基准 = 最后入队的待写指纹（有的话）> 已写成指纹；入队即记待写，写成才升为已写成，失败回退。
+ (void)persistFriendsIfChanged:(NSArray<IMUserCard *> *)accepted context:(IMDatabaseAccountContext *)context {
    NSDictionary<NSString *, NSArray *> *fingerprint = IMCachedFriendsFingerprint(accepted);
    NSDictionary<NSString *, NSArray *> *expected = IMFriendCacheExpectedFingerprint(context);
    BOOL changed = !expected || ![fingerprint isEqualToDictionary:expected];
    IMLogUI(@"contacts_cache_persist changed=%d friends=%lu", changed, (unsigned long)accepted.count);
    if (!changed) { return; }
    sPendingFingerprint = fingerprint;
    sPendingContext = context;
    NSArray<IMUserCard *> *snapshot = [accepted copy];
    BOOL (^writeOverride)(NSArray<IMUserCard *> *, IMDatabaseAccountContext *) = sWriteOverride;
    dispatch_async(IMFriendCacheWriteQueue(), ^{
        __block BOOL written = NO;
        if (writeOverride) {
            written = writeOverride(snapshot, context);
        } else {
            [IMDatabase.sharedDatabase performWithAccountContext:context block:^(IMDatabase *database) {
                written = [database replaceCachedFriends:snapshot];
            }];
        }
        if (!written) { IMLogDatabase(@"contacts_cache_persist write_failed friends=%lu", (unsigned long)snapshot.count); }
        dispatch_async(dispatch_get_main_queue(), ^{ IMFriendCacheFinishWrite(fingerprint, context, written); });
    });
}

/// 单测用（头文件不声明，测试里用 category 声明后调用）：替换落库实现并清空指纹状态；传 nil 恢复真实落库。
+ (void)im_setWriteOverrideForTesting:(BOOL (^)(NSArray<IMUserCard *> *, IMDatabaseAccountContext *))writeOverride {
    sWriteOverride = [writeOverride copy];
    sFingerprint = nil;
    sFingerprintContext = nil;
    sPendingFingerprint = nil;
    sPendingContext = nil;
}

@end
