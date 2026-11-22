//  IMOrgChatLocks.m

#import "IMOrgChatLocks.h"
#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMSocketManager.h"

NSNotificationName const IMOrgChatLocksDidChangeNotification = @"IMOrgChatLocksDidChangeNotification";
NSString * const IMOrgChatLockOrgLeft = @"org_left";
NSString * const IMOrgChatLockServiceEnded = @"service_ended";

NSString *IMOrgChatLockTextKey(NSString *reason) {
    if ([reason isEqualToString:IMOrgChatLockOrgLeft]) { return @"chat.input.disabled_org_left"; }
    if ([reason isEqualToString:IMOrgChatLockServiceEnded]) { return @"chat.input.disabled_service_ended"; }
    return nil;
}

@implementation IMOrgChatLocks {
    NSString *_owner;                                     // 表属于哪个账号（换号即清空）
    NSMutableDictionary<NSString *, NSString *> *_locks;  // peer → 原因
    NSMutableSet<NSString *> *_direct;                    // 已知免好友直聊的对端
}

+ (instancetype)shared {
    static IMOrgChatLocks *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMOrgChatLocks new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _locks = [NSMutableDictionary dictionary];
        _direct = [NSMutableSet set];
        // 好友事件 org_exit（对方或我脱离集团）：会话列表刷新前先锁上。
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onFriendEvent:)
                                                   name:IMSocketDidReceiveFriendEventNotification object:nil];
    }
    return self;
}

- (void)onFriendEvent:(NSNotification *)note {
    if ([note.userInfo[kIMFriendEventKey] isEqualToString:@"org_exit"]) { [self markOrgLeftForPeer:note.userInfo[kIMFriendEventFromKey]]; }
}

/// 换号即清空。只在主线程调用。
- (void)syncOwner {
    NSString *uid = IMDatabase.sharedDatabase.currentAccountContext.ownerUserID ?: @"";
    if (![uid isEqualToString:_owner ?: @""]) {
        _owner = [uid copy];
        [_locks removeAllObjects];
        [_direct removeAllObjects];
    }
}

- (NSString *)lockTextKeyForPeer:(NSString *)peerID {
    if (peerID.length == 0) { return nil; }
    [self syncOwner];
    return IMOrgChatLockTextKey(_locks[peerID]);
}

/// 改一个对端的原因（nil = 解除）；变了才发通知。主线程。
- (void)setReason:(NSString *)reason forPeer:(NSString *)peer {
    [self syncOwner];
    if ((reason == nil && _locks[peer] == nil) || [_locks[peer] isEqualToString:reason]) { return; }
    _locks[peer] = reason;
    [NSNotificationCenter.defaultCenter postNotificationName:IMOrgChatLocksDidChangeNotification object:nil];
}

- (void)markOrgLeftForPeer:(NSString *)peerID {
    if (![peerID isKindOfClass:NSString.class] || peerID.length == 0) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_direct removeObject:peerID]; // 不在同一集团就没有直聊
        [self setReason:IMOrgChatLockOrgLeft forPeer:peerID];
    });
}

- (void)noteDirectChatForPeer:(NSString *)peerID {
    if (peerID.length == 0) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{ [self setReason:nil forPeer:peerID]; });
}

- (BOOL)isDirectPeer:(NSString *)peerID {
    if (peerID.length == 0) { return NO; }
    [self syncOwner];
    return [_direct containsObject:peerID];
}

- (void)setDirect:(BOOL)direct forPeer:(NSString *)peerID {
    if (peerID.length == 0) { return; }
    [self syncOwner];
    if (direct) { [_direct addObject:peerID]; } else { [_direct removeObject:peerID]; }
}

- (void)ingestConversations:(NSArray<IMConversation *> *)conversations {
    NSArray<IMConversation *> *convs = [conversations copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self syncOwner];
        BOOL changed = NO;
        for (IMConversation *c in convs) {
            if (c.isGroup || c.peer.length == 0) { continue; }
            if (c.peerDirectChat) { [self->_direct addObject:c.peer]; } else { [self->_direct removeObject:c.peer]; }
            NSString *reason = c.peerChatLock.length > 0 ? c.peerChatLock : nil;
            if ((reason == nil && self->_locks[c.peer] == nil) || [self->_locks[c.peer] isEqualToString:reason]) { continue; }
            self->_locks[c.peer] = reason;
            changed = YES;
        }
        if (changed) { [NSNotificationCenter.defaultCenter postNotificationName:IMOrgChatLocksDidChangeNotification object:nil]; }
    });
}

@end
