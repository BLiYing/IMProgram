//  IMFriendStateStore.m

#import "IMFriendStateStore.h"

#import "IMDatabase.h"
#import "IMLog.h"
#import "IMUserCard.h"

@implementation IMFriendStateStore {
    NSMutableSet<NSString *> *_friends; // accepted 的 uid 集合
    BOOL _resolved;                     // 是否已被喂过至少一次全集（否则"不在表里"≠"不是好友"）
    NSString *_ownerUserID;             // 记账用：换号即整表清空
}

+ (instancetype)sharedStore {
    static IMFriendStateStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [IMFriendStateStore new]; });
    return store;
}

- (instancetype)init {
    if ((self = [super init])) {
        _friends = [NSMutableSet set];
        _ownerUserID = @"";
    }
    return self;
}

#pragma mark - 读

- (nullable NSNumber *)friendStateForUser:(NSString *)userID {
    if (userID.length == 0) { return nil; }
    NSString *owner = [self currentOwner];
    @synchronized (self) {
        [self syncOwnerLocked:owner];
        if ([_friends containsObject:userID]) { return @YES; }
        return _resolved ? @NO : nil; // 没喂过全集时"不在表里"什么都不能说明
    }
}

#pragma mark - 写

- (void)ingestFriends:(NSArray<IMUserCard *> *)cards authoritative:(BOOL)authoritative {
    if (cards == nil) { return; }
    NSString *owner = [self currentOwner];
    @synchronized (self) {
        [self syncOwnerLocked:owner];
        NSMutableSet<NSString *> *accepted = [NSMutableSet setWithCapacity:cards.count];
        for (IMUserCard *c in cards) {
            if (c.userID.length == 0) { continue; }
            if (c.status == IMFriendStatusAccepted) { [accepted addObject:c.userID]; }
        }
        if (authoritative) {
            // 全集：整表替换。**必须替换而不是合并**——删好友后那个 uid 只会"不出现"，
            // 合并的话它会永远留在表里，资料页照旧显示好友界面。
            [_friends setSet:accepted];
            _resolved = YES;
            return;
        }
        // 子集：只按卡片逐个更新，不清扫、也不改变「已知」标志。
        for (IMUserCard *c in cards) {
            if (c.userID.length == 0) { continue; }
            if (c.status == IMFriendStatusAccepted) { [_friends addObject:c.userID]; }
            else { [_friends removeObject:c.userID]; }
        }
    }
}

- (void)seedFromLocalSnapshot:(NSArray<IMUserCard *> *)cards {
    if (cards.count == 0) { return; } // 空快照可能只是"从没同步过"，不能据此判所有人非好友
    NSString *owner = [self currentOwner];
    @synchronized (self) {
        [self syncOwnerLocked:owner];
        if (_resolved) { return; } // 网络全集比本地快照新，已有就别覆盖
        for (IMUserCard *c in cards) {
            if (c.userID.length > 0 && c.status == IMFriendStatusAccepted) { [_friends addObject:c.userID]; }
        }
        _resolved = YES;
    }
}

#pragma mark - 内部

/// 当前账号 owner。**必须在取本类锁之前调用**：与 IMRemarkStore 同一条锁序约定——
/// 本类锁是叶子锁，锁内不得回头调用 IMDatabase 的任何方法（否则与 DB 锁形成反向锁序而可能死锁）。
- (NSString *)currentOwner {
    return IMDatabase.sharedDatabase.currentAccountContext.ownerUserID ?: @"";
}

/// 账号自愈：与传入的当前 owner 不一致即整表清空（并退回「不知道」）。
- (void)syncOwnerLocked:(NSString *)owner {
    if ([owner isEqualToString:_ownerUserID]) { return; }
    if (_friends.count > 0 || _resolved) {
        IMLogUI(@"账号切换，清空好友关系缓存 old_uid=%@ new_uid=%@ count=%lu",
                _ownerUserID.length ? _ownerUserID : @"(none)", owner.length ? owner : @"(none)",
                (unsigned long)_friends.count);
        [_friends removeAllObjects];
        _resolved = NO;
    }
    _ownerUserID = [owner copy];
}

@end
