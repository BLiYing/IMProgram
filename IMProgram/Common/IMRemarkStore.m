//  IMRemarkStore.m

#import "IMRemarkStore.h"

#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMLog.h"
#import "IMUserCard.h"

NSString * const IMRemarkStoreDidChangeNotification = @"IMRemarkStoreDidChangeNotification";
NSString * const kIMRemarkPeerIDKey = @"peerID";

@implementation IMRemarkStore {
    NSMutableDictionary<NSString *, NSString *> *_remarks; // uid → 备注（恒非空串）
    NSString *_ownerUserID;                                // 记账用：换号即整表清空
}

+ (instancetype)sharedStore {
    static IMRemarkStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [IMRemarkStore new]; });
    return store;
}

- (instancetype)init {
    if ((self = [super init])) {
        _remarks = [NSMutableDictionary dictionary];
        _ownerUserID = @"";
    }
    return self;
}

#pragma mark - 读

- (nullable NSString *)remarkForUser:(NSString *)userID {
    if (userID.length == 0) { return nil; }
    NSString *owner = [self currentOwner];
    @synchronized (self) {
        [self syncOwnerLocked:owner];
        return _remarks[userID];
    }
}

- (NSString *)displayNameForUser:(NSString *)userID fallback:(NSString *)fallback {
    NSString *remark = [self remarkForUser:userID];
    if (remark.length > 0) { return remark; }
    return fallback.length > 0 ? fallback : (userID ?: @"");
}

#pragma mark - 写

- (void)applyRemark:(NSString *)remark forUser:(NSString *)userID {
    if (userID.length == 0) { return; }
    NSString *owner = [self currentOwner];
    BOOL changed = NO;
    @synchronized (self) {
        [self syncOwnerLocked:owner];
        changed = [self setLocked:remark forUser:userID];
    }
    if (changed) { [self postChangeForPeer:userID]; }
}

- (void)ingestFriends:(NSArray<IMUserCard *> *)cards authoritative:(BOOL)authoritative {
    if (cards == nil) { return; }
    NSString *owner = [self currentOwner];
    BOOL changed = NO;
    @synchronized (self) {
        [self syncOwnerLocked:owner];
        NSMutableSet<NSString *> *seen = [NSMutableSet setWithCapacity:cards.count];
        for (IMUserCard *c in cards) {
            if (c.userID.length == 0) { continue; }
            [seen addObject:c.userID];
            changed |= [self setLocked:c.remark forUser:c.userID];
        }
        // 全集才做清扫：把表里"这批没提到的" uid 视为已无备注清掉，否则在别处清空备注后
        // 本表会一直留着旧值（清除是最容易被漏掉的那一半）。子集绝不能清，会误伤其他好友。
        if (authoritative) {
            for (NSString *uid in [_remarks.allKeys copy]) {
                if (![seen containsObject:uid]) { changed |= [self setLocked:nil forUser:uid]; }
            }
        }
    }
    if (changed) { [self postChangeForPeer:nil]; }
}

- (void)ingestConversations:(NSArray<IMConversation *> *)conversations {
    if (conversations == nil) { return; }
    NSString *owner = [self currentOwner];
    BOOL changed = NO;
    @synchronized (self) {
        [self syncOwnerLocked:owner];
        // 会话列表**不是**好友全集（只含有会话的单聊对端），故只覆盖出现过的 uid、不做清扫。
        for (IMConversation *c in conversations) {
            if (c.isGroup || c.peer.length == 0) { continue; }
            changed |= [self setLocked:c.peerRemark forUser:c.peer];
        }
    }
    if (changed) { [self postChangeForPeer:nil]; }
}

#pragma mark - 内部

/// 归一化写入：空串/空白/nil 一律按"无备注"删除键。返回值是否真的变了（决定要不要发通知）。
- (BOOL)setLocked:(NSString *)remark forUser:(NSString *)userID {
    NSString *v = [remark stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *old = _remarks[userID];
    if (v.length == 0) {
        if (old == nil) { return NO; }
        [_remarks removeObjectForKey:userID];
        return YES;
    }
    if ([old isEqualToString:v]) { return NO; }
    _remarks[userID] = v;
    return YES;
}

/// 当前账号 owner。**必须在取本类锁之前调用**：`IMDatabase.performWithAccountContext:` 会
/// 持有 IMDatabase 的锁执行 block，而 block 里读 cachedConversations/cachedFriends 又会回调本类
/// （DB 锁 → 本类锁）。若本类持锁期间再去问 IMDatabase，就形成反向锁序（本类锁 → DB 锁）而可能死锁。
/// 故本类锁是**叶子锁**：锁内不得调用 IMDatabase 的任何方法。
- (NSString *)currentOwner {
    return IMDatabase.sharedDatabase.currentAccountContext.ownerUserID ?: @"";
}

/// 账号自愈：与传入的当前 owner 不一致即整表清空。备注是每账号私有的，串号显示等于泄露。
- (void)syncOwnerLocked:(NSString *)owner {
    if ([owner isEqualToString:_ownerUserID]) { return; }
    if (_remarks.count > 0) {
        IMLogUI(@"账号切换，清空备注名缓存 old_uid=%@ new_uid=%@ count=%lu",
                _ownerUserID.length ? _ownerUserID : @"(none)", owner.length ? owner : @"(none)",
                (unsigned long)_remarks.count);
        [_remarks removeAllObjects];
    }
    _ownerUserID = [owner copy];
}

- (void)postChangeForPeer:(nullable NSString *)peerID {
    NSDictionary *info = peerID.length > 0 ? @{ kIMRemarkPeerIDKey: peerID } : @{};
    if (NSThread.isMainThread) {
        [NSNotificationCenter.defaultCenter postNotificationName:IMRemarkStoreDidChangeNotification
                                                          object:self userInfo:info];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:IMRemarkStoreDidChangeNotification
                                                          object:self userInfo:info];
    });
}

@end
