//
//  IMUserProfileCache.m
//

#import "IMUserProfileCache.h"

#import "IMDatabase.h"
#import "IMGroupInfo.h"
#import "IMHTTPService.h"
#import "IMLog.h"
#import "IMUserCard.h"

NSNotificationName const IMUserProfileCacheDidResolveNotification = @"IMUserProfileCacheDidResolveNotification";

/// 合并窗口：一屏 cell 在同一帧里问几十个 uid，攒 50ms 再发就是一次请求而不是几十次。
static const NSTimeInterval kCoalesceWindow = 0.05;
/// 单批上限，必须 ≤ 服务端的 profile.MaxBatchProfiles（100），超了整批被拒。
static const NSUInteger kMaxBatch = 100;
/// 负缓存有效期：查无此人（已注销/脏数据）先记 10 分钟，别每次滚动都重试一遍。
/// 不设永久是因为「查无此人」也可能是那一次请求恰好失败之外的服务端瞬时状态。
static const NSTimeInterval kMissingTTL = 600;
/// 一批失败后的**退避窗口**。失败的 uid 不写负缓存（一次抖动不该变成十分钟的"查无此人"），
/// 但也不能立刻重来：调用方是 cellForRow 这类渲染路径，每 reloadData 一次就重新排一遍队，
/// 断网时会以滚动/重绘的频率反复打同一个接口——服务端 60 次/分的配额几秒就烧光，
/// 之后一直 429，网络恢复了也解析不出来（自己把自己锁死）。
static const NSTimeInterval kFailureBackoff = 5;
/// 缓存条数上限。超了按插入序丢最老的一批——身份数据丢了顶多再解析一次，不值得为它做 LRU 计账。
static const NSUInteger kMaxCached = 2000;

@implementation IMUserProfileCache {
    NSMutableDictionary<NSString *, IMUserCard *> *_cards;
    NSMutableArray<NSString *> *_order;                  // 插入序，用于超限裁剪
    NSMutableDictionary<NSString *, NSDate *> *_missing; // 负缓存：uid → 判定时间
    NSMutableOrderedSet<NSString *> *_pending;           // 待发起解析（保持请求顺序，先看到的先解析）
    NSMutableSet<NSString *> *_inflight;                 // 已发出、未回来
    BOOL _flushScheduled;
    NSDate *_backoffUntil;              // 上一批失败后的退避截止时刻（nil=不在退避中）
    NSString *_ownerUserID;
}

+ (instancetype)sharedCache {
    static IMUserProfileCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [IMUserProfileCache new]; });
    return cache;
}

- (instancetype)init {
    if ((self = [super init])) {
        _cards = [NSMutableDictionary dictionary];
        _order = [NSMutableArray array];
        _missing = [NSMutableDictionary dictionary];
        _pending = [NSMutableOrderedSet orderedSet];
        _inflight = [NSMutableSet set];
        _ownerUserID = @"";
    }
    return self;
}

#pragma mark - 读

- (nullable IMUserCard *)cardForUserID:(NSString *)userID {
    if (userID.length == 0) { return nil; }
    IMUserCard *hit = [self lookup:userID enqueueOnMiss:YES];
    if (!hit) { [self scheduleFlush]; }
    return hit;
}

- (nullable IMUserCard *)peekCardForUserID:(NSString *)userID {
    if (userID.length == 0) { return nil; }
    return [self lookup:userID enqueueOnMiss:NO];
}

- (void)prefetchUserIDs:(NSArray<NSString *> *)userIDs {
    if (userIDs.count == 0) { return; }
    BOOL any = NO;
    for (NSString *uid in userIDs) {
        if (![uid isKindOfClass:NSString.class] || uid.length == 0) { continue; }
        if (![self lookup:uid enqueueOnMiss:YES]) { any = YES; }
    }
    if (any) { [self scheduleFlush]; }
}

/// 查一次缓存；enqueueOnMiss=YES 时未命中就排进待解析队列（负缓存未过期的不排）。
- (nullable IMUserCard *)lookup:(NSString *)userID enqueueOnMiss:(BOOL)enqueue {
    NSString *owner = [self currentOwner];
    @synchronized (self) {
        [self syncOwnerLocked:owner];
        IMUserCard *hit = _cards[userID];
        if (hit) { return hit; }
        if (!enqueue) { return nil; }
        if (_backoffUntil && _backoffUntil.timeIntervalSinceNow > 0) { return nil; } // 刚失败过，先歇一会
        NSDate *missedAt = _missing[userID];
        if (missedAt && -missedAt.timeIntervalSinceNow < kMissingTTL) { return nil; }
        if (missedAt) { [_missing removeObjectForKey:userID]; } // 过期了，允许再试一次
        if ([_inflight containsObject:userID]) { return nil; }
        [_pending addObject:userID];
        return nil;
    }
}

#pragma mark - 写（喂入）

- (void)ingestCards:(NSArray<IMUserCard *> *)cards {
    if (cards.count == 0) { return; }
    NSString *owner = [self currentOwner];
    @synchronized (self) {
        [self syncOwnerLocked:owner];
        for (IMUserCard *c in cards) {
            if (![c isKindOfClass:IMUserCard.class] || c.userID.length == 0) { continue; }
            [self storeLocked:c];
        }
    }
}

- (void)ingestGroupMembers:(NSArray<IMGroupMember *> *)members {
    if (members.count == 0) { return; }
    NSMutableArray<IMUserCard *> *cards = [NSMutableArray arrayWithCapacity:members.count];
    for (IMGroupMember *m in members) {
        if (![m isKindOfClass:IMGroupMember.class] || m.userID.length == 0) { continue; }
        IMUserCard *c = [IMUserCard new];
        c.userID = m.userID;
        c.username = m.username ?: @"";
        // **喂全局昵称、不喂群昵称**：本缓存是跨会话的身份表，群昵称只在那个群里成立，
        // 塞进来会让 A 群的群昵称漏到 B 群的气泡上。群昵称仍由各群自己的成员表覆盖。
        c.nickname = m.nickname ?: @"";
        c.avatarURL = m.avatarURL ?: @"";
        [cards addObject:c];
    }
    [self ingestCards:cards];
}

/// 落一条（须持锁）。同 uid 覆盖：喂入源（群成员表/好友列表/批量解析）都比缓存新。
- (void)storeLocked:(IMUserCard *)card {
    if (!_cards[card.userID]) { [_order addObject:card.userID]; }
    _cards[card.userID] = card;
    [_missing removeObjectForKey:card.userID]; // 之前判过"查无此人"的，现在有了
    while (_order.count > kMaxCached) {
        NSString *oldest = _order.firstObject;
        [_order removeObjectAtIndex:0];
        [_cards removeObjectForKey:oldest];
    }
}

#pragma mark - 批量解析

- (void)scheduleFlush {
    @synchronized (self) {
        if (_flushScheduled || _pending.count == 0) { return; }
        _flushScheduled = YES;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCoalesceWindow * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [weakSelf flush]; });
}

- (void)flush {
    NSString *token = IMHTTPService.sharedService.currentToken;
    NSString *owner = [self currentOwner];
    NSArray<NSString *> *batch = nil;
    @synchronized (self) {
        [self syncOwnerLocked:owner];
        _flushScheduled = NO;
        if (token.length == 0) {
            // 没登录：**清空待解析队列**而不是留着。留着会在登录后一次性涌出一大批
            // 早已不在屏幕上的 uid；真正还要显示的那些，下一帧 cellForRow 会重新问。
            [_pending removeAllObjects];
            return;
        }
        // 退避中不发。**这一条也要有**：失败那批若有超过 kMaxBatch 的余量，handleBatch 会顺手
        // scheduleFlush 把余量发出去——那一发正好绕过刚设的退避。队列原样留着，
        // 退避过去后下一次 cardForUserID: 会重新 scheduleFlush。
        if (_backoffUntil && _backoffUntil.timeIntervalSinceNow > 0) { return; }
        NSUInteger n = MIN(_pending.count, kMaxBatch);
        if (n == 0) { return; }
        batch = [[_pending.array subarrayWithRange:NSMakeRange(0, n)] copy];
        [_pending removeObjectsInRange:NSMakeRange(0, n)];
        [_inflight addObjectsFromArray:batch];
    }
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService usersBatchWithToken:token userIDs:batch
                                          completion:^(NSArray<IMUserCard *> *users,
                                                       NSArray<NSString *> *missing,
                                                       NSError *error) {
        [weakSelf handleBatch:batch owner:owner users:users missing:missing error:error];
    }];
}

/// requestOwner 是**发起这批请求时**的账号。回来时若已换号就整批丢弃——
/// 公开名片本身与账号无关，但把上一个账号触发的解析结果写进新账号的缓存，
/// 会让"换号即清空"这条不变式变成有洞的（下一个人调试时怎么也想不通那条记录哪来的）。
- (void)handleBatch:(NSArray<NSString *> *)batch
              owner:(NSString *)requestOwner
              users:(NSArray<IMUserCard *> *)users
            missing:(NSArray<NSString *> *)missing
              error:(NSError *)error {
    NSString *owner = [self currentOwner];
    NSMutableArray<NSString *> *resolved = [NSMutableArray array];
    @synchronized (self) {
        [self syncOwnerLocked:owner];
        for (NSString *uid in batch) { [_inflight removeObject:uid]; }
        if (![owner isEqualToString:requestOwner]) { return; }
        if (error) {
            // **失败不写负缓存**：那会把一次网络抖动变成 10 分钟的"查无此人"。
            // 也不自动重排队重试——下一帧 cellForRow 还需要的话自然会再问一次，
            // 那才是"还在屏幕上"的证据；无条件重试会在断网时打转。
            _backoffUntil = [NSDate dateWithTimeIntervalSinceNow:kFailureBackoff];
            IMLogWarnWithTag(IMLogTagHTTP, @"user_profile_batch_failed count=%lu error=%@",
                             (unsigned long)batch.count, error.localizedDescription ?: @"");
        } else {
            for (IMUserCard *c in users) {
                if (c.userID.length == 0) { continue; }
                [self storeLocked:c];
                [resolved addObject:c.userID];
            }
            _backoffUntil = nil; // 这一批成功了，解除退避
            NSDate *now = [NSDate date];
            for (NSString *uid in missing) {
                if (![uid isKindOfClass:NSString.class] || uid.length == 0) { continue; }
                _missing[uid] = now;
                [resolved addObject:uid]; // 也要通知：调用方据此停止转圈、落到兜底显示
            }
        }
    }
    if (resolved.count == 0) { [self scheduleFlush]; return; } // 还有剩下的批次
    [NSNotificationCenter.defaultCenter postNotificationName:IMUserProfileCacheDidResolveNotification
                                                      object:nil
                                                    userInfo:@{@"user_ids": [resolved copy]}];
    [self scheduleFlush]; // 队列里可能还有超过 kMaxBatch 的余量
}

#pragma mark - 账号隔离

/// 当前账号 owner。**必须在取本类锁之前调用**——同 IMFriendStateStore 的锁序约定：
/// 本类锁是叶子锁，锁内不得回头调 IMDatabase（否则与 DB 锁形成反向锁序而可能死锁）。
- (NSString *)currentOwner {
    return IMDatabase.sharedDatabase.currentAccountContext.ownerUserID ?: @"";
}

- (void)syncOwnerLocked:(NSString *)owner {
    if ([owner isEqualToString:_ownerUserID]) { return; }
    if (_cards.count > 0 || _missing.count > 0 || _pending.count > 0) {
        IMLogUI(@"账号切换，清空用户资料缓存 old_uid=%@ new_uid=%@ count=%lu",
                _ownerUserID.length ? _ownerUserID : @"(none)", owner.length ? owner : @"(none)",
                (unsigned long)_cards.count);
    }
    [_cards removeAllObjects];
    [_order removeAllObjects];
    [_missing removeAllObjects];
    [_pending removeAllObjects];
    _backoffUntil = nil;
    // _inflight 也清空：在飞的那批回来时会被 handleBatch 的 requestOwner 比对挡掉，
    // 不清的话换号后它们会一直占着"已在飞"的名额、让新账号对同一批 uid 永远排不进队。
    [_inflight removeAllObjects];
    _ownerUserID = [owner copy];
}

@end
