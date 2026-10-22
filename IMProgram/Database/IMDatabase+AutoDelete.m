//  IMDatabase+AutoDelete.m
//  语义、拆分理由见 IMDatabase+AutoDelete.h。

#import "IMDatabase+AutoDelete.h"
#import "IMDatabase+Ranges.h"   // dbQueue / ownerUserID
#import "IMAutoDelete.h"
#import "IMProtocol.h"   // kIMTypeMsgOp
#import "IMLog.h"

#pragma mark - 内存缓存（落库闸用）

static NSMutableDictionary<NSString *, IMAutoDeleteConfig *> *IMAutoDeleteCache(void) {
    static NSMutableDictionary *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    return cache;
}
static NSString *IMAutoDeleteKey(NSString *owner, NSString *convID) {
    return [NSString stringWithFormat:@"%@\n%@", owner, convID];
}
static void IMAutoDeleteCacheSet(NSString *owner, NSString *convID, IMAutoDeleteConfig *cfg) {
    NSMutableDictionary *c = IMAutoDeleteCache();
    @synchronized (c) { c[IMAutoDeleteKey(owner, convID)] = cfg; }
}
static void IMAutoDeleteCacheDropOwner(NSString *owner) {
    NSMutableDictionary *c = IMAutoDeleteCache();
    NSString *prefix = [owner stringByAppendingString:@"\n"];
    @synchronized (c) {
        for (NSString *k in [c.allKeys copy]) { if ([k hasPrefix:prefix]) { [c removeObjectForKey:k]; } }
    }
}

/// 内存缓存命中则返回（nil = 未命中）。入库热路径（逐条 / 逐页）用它，免得每条消息多一次 SELECT。
static IMAutoDeleteConfig *IMAutoDeleteCacheLookup(NSString *owner, NSString *convID) {
    NSMutableDictionary *c = IMAutoDeleteCache();
    @synchronized (c) { return c[IMAutoDeleteKey(owner, convID)]; }
}

static IMAutoDeleteConfig *IMAutoDeleteReadRow(FMDatabase *db, NSString *owner, NSString *convID) {
    FMResultSet *rs = [db executeQuery:@"SELECT sec,from_ms FROM im_conv_auto_delete_local WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
    IMAutoDeleteConfig *cfg = [rs next] ? [IMAutoDeleteConfig configWithSec:[rs longLongIntForColumn:@"sec"] from:[rs longLongIntForColumn:@"from_ms"]]
                                        : [IMAutoDeleteConfig configWithSec:0 from:0];
    [rs close];
    return cfg;
}

/// 该会话设置（内存缓存；未命中就读小表并写回缓存——含「关」，所以整页 10 万条最多多 1 次 SELECT）。
static IMAutoDeleteConfig *IMAutoDeleteConfigCached(FMDatabase *db, NSString *owner, NSString *convID) {
    IMAutoDeleteConfig *hit = IMAutoDeleteCacheLookup(owner, convID);
    if (hit) { return hit; }
    IMAutoDeleteConfig *cfg = IMAutoDeleteReadRow(db, owner, convID);
    IMAutoDeleteCacheSet(owner, convID, cfg);
    return cfg;
}

/// 本进程内已被服务端列表（GET /conversations，已按档位过滤预览 / 未读）整份写过摘要的会话：纯摘要重算对它们让路，
/// 否则「列表落库 -> 本地重算清空 -> 通知列表重拉 -> 列表落库」会循环，且会盖掉服务端给的 from 之前的预览 / 未读。
static NSMutableSet<NSString *> *IMAutoDeleteServerSyncedSet(void) {
    static NSMutableSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSMutableSet set]; });
    return set;
}

static int64_t IMAutoDeleteNowMs(void) { return (int64_t)([NSDate date].timeIntervalSince1970 * 1000); }

/// msg_op 事件行（撤回/编辑/置顶/删除…）不是消息正文：不受过期闸影响，照常落库 / 推游标（设计 §4；目标已过期则操作落空，幂等）。
static BOOL IMAutoDeleteIsEventRow(IMMessageModel *message) {
    return [message.contentType isEqualToString:kIMTypeMsgOp];
}

BOOL IMAutoDeleteDropsMessage(FMDatabase *db, NSString *owner, IMMessageModel *message) {
    if (IMAutoDeleteIsEventRow(message)) { return NO; }
    if (message.convSeq <= 0 || message.timestamp <= 0 || message.convID.length == 0) { return NO; }
    return [IMAutoDeleteConfigCached(db, owner, message.convID) isExpiredTimestamp:message.timestamp now:IMAutoDeleteNowMs()];
}

#pragma mark - 实现

@implementation IMDatabase (AutoDelete)

- (void)migrateAutoDeleteTableDB:(FMDatabase *)db {
    if (![db executeUpdate:
          @"CREATE TABLE IF NOT EXISTS im_conv_auto_delete_local ("
           "owner_uid TEXT NOT NULL, conv_id TEXT NOT NULL, sec INTEGER NOT NULL DEFAULT 0,"
           "from_ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(owner_uid,conv_id))"]) {
        IMLogDatabase(@"自动删除设置建表失败: %@", db.lastErrorMessage);
        return;
    }
    // v1（个人档位，只有 sec 列）→ v2：补 from_ms 列，并整表清掉 v1 个人档位——from=0 配旧档位会把整段历史当成可追溯清理。
    // 不迁移：升级后首次拉会话列表即被服务端会话级值覆盖。
    FMResultSet *rs = [db executeQuery:@"PRAGMA table_info(im_conv_auto_delete_local)"];
    BOOL hasFrom = NO;
    while ([rs next]) { if ([[rs stringForColumn:@"name"] isEqualToString:@"from_ms"]) { hasFrom = YES; break; } }
    [rs close];
    if (hasFrom) { return; }
    if (![db executeUpdate:@"ALTER TABLE im_conv_auto_delete_local ADD COLUMN from_ms INTEGER NOT NULL DEFAULT 0"]
        || ![db executeUpdate:@"DELETE FROM im_conv_auto_delete_local"]) {
        IMLogDatabase(@"迁移失败：im_conv_auto_delete_local 补列 from_ms 未成功: %@", db.lastErrorMessage);
    }
}

- (IMAutoDeleteConfig *)autoDeleteConfigForConv:(NSString *)convID {
    if (convID.length == 0) { return [IMAutoDeleteConfig configWithSec:0 from:0]; }
    NSString *owner = [self ownerUserID];
    __block IMAutoDeleteConfig *cfg;
    [self.dbQueue inDatabase:^(FMDatabase *db) { cfg = IMAutoDeleteReadRow(db, owner, convID); }];
    IMAutoDeleteCacheSet(owner, convID, cfg);
    return cfg;
}

- (int64_t)autoDeleteSecForConv:(NSString *)convID { return [self autoDeleteConfigForConv:convID].sec; }

- (BOOL)setAutoDeleteSec:(int64_t)sec from:(int64_t)from forConv:(NSString *)convID {
    if (!IMAutoDeleteIsValidSec(sec)) { sec = 0; }
    return [self setAutoDeleteConfig:[IMAutoDeleteConfig configWithSec:sec from:from] forConv:convID];
}

- (BOOL)setAutoDeleteConfig:(IMAutoDeleteConfig *)config forConv:(NSString *)convID {
    if (convID.length == 0) { return NO; }
    NSString *owner = [self ownerUserID];
    BOOL changed = ![[self autoDeleteConfigForConv:convID] isEqualToConfig:config];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        if (![db executeUpdate:
              @"INSERT INTO im_conv_auto_delete_local (owner_uid,conv_id,sec,from_ms) VALUES (?,?,?,?) "
               "ON CONFLICT(owner_uid,conv_id) DO UPDATE SET sec=excluded.sec, from_ms=excluded.from_ms",
              owner, convID, @(config.sec), @(config.from)]) {
            IMLogDatabase(@"写自动删除设置失败 conv=%@: %@", convID, db.lastErrorMessage);
        }
    }];
    IMAutoDeleteCacheSet(owner, convID, config);
    return changed;
}

- (void)persistAutoDeleteFromConversations:(NSArray<IMConversation *> *)conversations {
    NSString *owner = [self ownerUserID];
    NSMutableDictionary<NSString *, IMAutoDeleteConfig *> *fresh = [NSMutableDictionary dictionary];
    for (IMConversation *c in conversations) {
        if (c.convID.length == 0) { continue; }
        fresh[c.convID] = IMAutoDeleteIsValidSec(c.autoDeleteSec) && c.autoDeleteSec > 0
            ? [IMAutoDeleteConfig configWithSec:c.autoDeleteSec from:c.autoDeleteFrom] : [IMAutoDeleteConfig configWithSec:0 from:0];
    }
    __block BOOL committed = NO;
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if (![db executeUpdate:@"DELETE FROM im_conv_auto_delete_local WHERE owner_uid=?", owner]) { *rollback = YES; return; }
        for (NSString *convID in fresh) {
            IMAutoDeleteConfig *cfg = fresh[convID];
            if (!cfg.active) { continue; }
            if (![db executeUpdate:@"INSERT INTO im_conv_auto_delete_local (owner_uid,conv_id,sec,from_ms) VALUES (?,?,?,?)",
                  owner, convID, @(cfg.sec), @(cfg.from)]) {
                IMLogDatabase(@"落自动删除设置失败 conv=%@: %@", convID, db.lastErrorMessage);
                *rollback = YES; return;
            }
        }
        committed = YES;
    }];
    if (!committed) { return; }
    // 提交后再换缓存（回滚时缓存与表保持一致）
    IMAutoDeleteCacheDropOwner(owner);
    for (NSString *convID in fresh) { IMAutoDeleteCacheSet(owner, convID, fresh[convID]); }
    NSMutableSet *synced = IMAutoDeleteServerSyncedSet();
    @synchronized (synced) { for (NSString *convID in fresh) { [synced addObject:IMAutoDeleteKey(owner, convID)]; } }
}

/// 缓存优先的读取（所有写设置的路径都会同步写缓存，未命中才回落读表）。
- (IMAutoDeleteConfig *)cachedAutoDeleteConfigForConv:(NSString *)convID {
    IMAutoDeleteConfig *hit = IMAutoDeleteCacheLookup([self ownerUserID], convID);
    return hit ?: [self autoDeleteConfigForConv:convID];
}

- (BOOL)autoDeleteDropsIncoming:(IMMessageModel *)message {
    if (IMAutoDeleteIsEventRow(message)) { return NO; }
    if (message.convSeq <= 0 || message.timestamp <= 0 || message.convID.length == 0) { return NO; } // 无时间戳按未过期（同落库闸 IMAutoDeleteDropsMessage）
    return [[self cachedAutoDeleteConfigForConv:message.convID] isExpiredTimestamp:message.timestamp now:IMAutoDeleteNowMs()];
}

- (NSArray<IMMessageModel *> *)messagesDroppingAutoDeleteExpired:(NSArray<IMMessageModel *> *)messages {
    if (messages.count == 0) { return messages; }
    IMAutoDeleteConfig *cfg = [self cachedAutoDeleteConfigForConv:messages.firstObject.convID];
    if (!cfg.active) { return messages; }
    int64_t now = IMAutoDeleteNowMs();
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray arrayWithCapacity:messages.count];
    for (IMMessageModel *m in messages) {
        if (m.convSeq <= 0 || m.timestamp <= 0 || IMAutoDeleteIsEventRow(m) || ![cfg isExpiredTimestamp:m.timestamp now:now]) { [out addObject:m]; }
    }
    return out;
}

- (NSArray<IMPinnedMessage *> *)pinnedItemsDroppingAutoDeleteExpired:(NSArray<IMPinnedMessage *> *)items convID:(NSString *)convID {
    IMAutoDeleteConfig *cfg = [self autoDeleteConfigForConv:convID];
    if (!cfg.active || items.count == 0) { return items; }
    int64_t now = IMAutoDeleteNowMs();
    NSMutableArray<IMPinnedMessage *> *out = [NSMutableArray arrayWithCapacity:items.count];
    for (IMPinnedMessage *p in items) { if (p.timestamp <= 0 || ![cfg isExpiredTimestamp:p.timestamp now:now]) { [out addObject:p]; } }
    return out;
}

- (NSDictionary<NSString *, IMAutoDeleteConfig *> *)autoDeleteActiveConvs {
    NSString *owner = [self ownerUserID];
    NSMutableDictionary<NSString *, IMAutoDeleteConfig *> *out = [NSMutableDictionary dictionary];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT conv_id,sec,from_ms FROM im_conv_auto_delete_local WHERE owner_uid=? AND sec>0", owner];
        while ([rs next]) {
            NSString *convID = [rs stringForColumn:@"conv_id"];
            IMAutoDeleteConfig *cfg = [IMAutoDeleteConfig configWithSec:[rs longLongIntForColumn:@"sec"] from:[rs longLongIntForColumn:@"from_ms"]];
            out[convID] = cfg;
            IMAutoDeleteCacheSet(owner, convID, cfg);
        }
        [rs close];
    }];
    return out;
}

#pragma mark - 清理

- (NSArray<NSNumber *> *)deleteExpiredMessagesForConv:(NSString *)convID config:(IMAutoDeleteConfig *)config nowMs:(int64_t)nowMs {
    int64_t lo = 0, hi = 0;
    if (convID.length == 0 || !IMAutoDeleteWindow(config.sec, config.from, nowMs, &lo, &hi)) { return @[]; }
    NSString *owner = [self ownerUserID];
    NSMutableArray<NSNumber *> *removed = [NSMutableArray array];
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        int64_t readSeq = 0;
        FMResultSet *rs = [db executeQuery:@"SELECT read_seq FROM im_conversation_local WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
        if ([rs next]) { readSeq = [rs longLongIntForColumn:@"read_seq"]; }
        [rs close];
        NSInteger unreadGone = 0;
        rs = [db executeQuery:
            @"SELECT conv_seq,sender,content_type FROM im_message_local WHERE owner_uid=? AND conv_id=? "
             "AND conv_seq>0 AND timestamp>0 AND timestamp>=? AND timestamp<=? ORDER BY conv_seq", owner, convID, @(lo), @(hi)];
        while ([rs next]) {
            int64_t seq = [rs longLongIntForColumn:@"conv_seq"];
            [removed addObject:@(seq)];
            NSString *from = [rs stringForColumn:@"sender"];
            BOOL incoming = from.length > 0 && ![from isEqualToString:owner];
            if (incoming && seq > readSeq && ![[rs stringForColumn:@"content_type"] isEqualToString:@"system"]) { unreadGone++; }
        }
        [rs close];
        if (removed.count > 0
            && ![db executeUpdate:@"DELETE FROM im_message_local WHERE owner_uid=? AND conv_id=? AND conv_seq>0 AND timestamp>0 AND timestamp>=? AND timestamp<=?",
                 owner, convID, @(lo), @(hi)]) {
            IMLogDatabase(@"自动删除清理失败 conv=%@: %@", convID, db.lastErrorMessage);
            [removed removeAllObjects]; *rollback = YES; return;
        }
        if (removed.count == 0) { return; }
        [self recomputeSummaryInDB:db owner:owner conv:convID lo:lo hi:hi unreadGone:unreadGone];
    }];
    if (removed.count > 0) { IMLogDatabase(@"自动删除 conv=%@ removed=%lu window=[%lld,%lld]", convID, (unsigned long)removed.count, lo, hi); }
    return removed;
}

/// 会话行预览 / 未读本地重算的快照（用来判断「是否真的变了」，避免每 30 秒扫描都重复通知列表）。
static NSString *IMAutoDeleteSummarySignature(FMDatabase *db, NSString *owner, NSString *convID) {
    FMResultSet *rs = [db executeQuery:
        @"SELECT unread,mention_unread,last_content,last_from,last_sys_event,last_sys_args,last_content_type,last_caption,last_recalled "
         "FROM im_conversation_local WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
    NSString *sig = @"";
    if ([rs next]) {
        sig = [NSString stringWithFormat:@"%lld|%lld|%@|%@|%@|%@|%@|%@|%lld", [rs longLongIntForColumn:@"unread"], [rs longLongIntForColumn:@"mention_unread"],
               [rs stringForColumn:@"last_content"] ?: @"", [rs stringForColumn:@"last_from"] ?: @"", [rs stringForColumn:@"last_sys_event"] ?: @"",
               [rs stringForColumn:@"last_sys_args"] ?: @"", [rs stringForColumn:@"last_content_type"] ?: @"", [rs stringForColumn:@"last_caption"] ?: @"",
               [rs longLongIntForColumn:@"last_recalled"]];
    }
    [rs close];
    return sig;
}

/// 未读重算：最后一条落在窗口内时，窗口外（from 之前）仍可能有本机已下载的未读——取「现有未读」与「本机剩余未读条数」的较小者。
static void IMAutoDeleteRecountUnread(FMDatabase *db, NSString *owner, NSString *convID, int64_t lo, int64_t hi) {
    FMResultSet *rs = [db executeQuery:
        @"SELECT COUNT(*) AS n FROM im_message_local m WHERE m.owner_uid=? AND m.conv_id=? AND m.conv_seq>0 "
         "AND m.conv_seq>(SELECT COALESCE(read_seq,0) FROM im_conversation_local WHERE owner_uid=? AND conv_id=?) "
         "AND m.sender<>'' AND m.sender<>? AND m.content_type<>'system' AND (m.timestamp<=0 OR m.timestamp<? OR m.timestamp>?)",
        owner, convID, owner, convID, owner, @(lo), @(hi)];
    int64_t remain = [rs next] ? [rs longLongIntForColumn:@"n"] : 0;
    [rs close];
    [db executeUpdate:@"UPDATE im_conversation_local SET unread=MIN(unread,?) WHERE owner_uid=? AND conv_id=?", @(remain), owner, convID];
    [db executeUpdate:@"UPDATE im_conversation_local SET mention_unread=0 WHERE owner_uid=? AND conv_id=? AND unread=0", owner, convID];
}

/// 会话行预览 / 未读本地重算。只在会话摘要所指的最后一条（timestamp）落在过期窗口 [lo,hi] 内时才改预览：
/// 预览取本地最后一条**未过期**的可见消息（可越过窗口取 from 之前的），没有则空预览；timestamp 不动（排序位置不变）。
/// 未读：先按被删的未读条数扣，再与本机剩余未读取较小者。返回会话行是否真的变了。
- (BOOL)recomputeSummaryInDB:(FMDatabase *)db owner:(NSString *)owner conv:(NSString *)convID
                          lo:(int64_t)lo hi:(int64_t)hi unreadGone:(NSInteger)unreadGone {
    NSString *before = IMAutoDeleteSummarySignature(db, owner, convID);
    if (unreadGone > 0) {
        [db executeUpdate:@"UPDATE im_conversation_local SET unread=MAX(0,unread-?) WHERE owner_uid=? AND conv_id=?", @(unreadGone), owner, convID];
        [db executeUpdate:@"UPDATE im_conversation_local SET mention_unread=0 WHERE owner_uid=? AND conv_id=? AND unread=0", owner, convID];
    }
    FMResultSet *rs = [db executeQuery:@"SELECT timestamp FROM im_conversation_local WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
    int64_t convTs = [rs next] ? [rs longLongIntForColumn:@"timestamp"] : -1;
    [rs close];
    // 无会话行 / 无时间戳（不知道摘要是哪条）/ 摘要指的那条不在窗口内（没过期）→ 预览不动。
    if (convTs > 0 && convTs >= lo && convTs <= hi) {
        IMAutoDeleteRecountUnread(db, owner, convID, lo, hi);
        [self replacePreviewInDB:db owner:owner conv:convID lo:lo hi:hi];
    }
    return ![before isEqualToString:IMAutoDeleteSummarySignature(db, owner, convID)];
}

- (void)replacePreviewInDB:(FMDatabase *)db owner:(NSString *)owner conv:(NSString *)convID lo:(int64_t)lo hi:(int64_t)hi {
    FMResultSet *rs = [db executeQuery:
        @"SELECT content,sender,from_nickname,sys_segments,sys_event,sys_args,content_type,caption,recalled_at FROM im_message_local "
         "WHERE owner_uid=? AND conv_id=? AND conv_seq>0 AND (timestamp<=0 OR timestamp<? OR timestamp>?) ORDER BY conv_seq DESC LIMIT 1",
        owner, convID, @(lo), @(hi)];
    BOOL has = [rs next];
    NSString *content = has ? ([rs stringForColumn:@"content"] ?: @"") : @"";
    NSString *sender = has ? ([rs stringForColumn:@"sender"] ?: @"") : @"";
    NSString *nick = has ? ([rs stringForColumn:@"from_nickname"] ?: @"") : @"";
    NSString *segs = has ? ([rs stringForColumn:@"sys_segments"] ?: @"") : @"";
    NSString *sysEvent = has ? ([rs stringForColumn:@"sys_event"] ?: @"") : @"";
    NSString *sysArgs = has ? ([rs stringForColumn:@"sys_args"] ?: @"") : @"";
    NSString *ctype = has ? ([rs stringForColumn:@"content_type"] ?: @"text") : @"text";
    NSString *caption = has ? ([rs stringForColumn:@"caption"] ?: @"") : @"";
    BOOL recalled = has && [rs longLongIntForColumn:@"recalled_at"] > 0;
    [rs close];
    // 空预览：last_* 清空（仍保留会话行与 timestamp，列表位置不动）。sys_event/args 取剩余那条的值，没有则清空，免得串到旧系统消息文案。
    if (![db executeUpdate:
          @"UPDATE im_conversation_local SET last_content=?,last_from=?,last_from_nickname=?,last_sys_segments=?,"
           "last_sys_event=?,last_sys_args=?,last_recalled=?,last_content_type=?,last_caption=? WHERE owner_uid=? AND conv_id=?",
          content, sender, nick, segs, sysEvent, sysArgs, @(recalled), ctype, caption, owner, convID]) {
        IMLogDatabase(@"自动删除后重算会话预览失败 conv=%@: %@", convID, db.lastErrorMessage);
    }
}

/// 本机没有这些消息行（离线积压 / 窗口外 / 重启后只剩会话列表缓存）时，`deleteExpiredMessagesForConv:` 删不到行，
/// 但会话行的预览 / 未读仍指向已过期的那条：单独重算一次。返回会话行是否真的变了（调用方据此通知列表刷新）。
- (BOOL)refreshAutoDeleteSummaryForConv:(NSString *)convID config:(IMAutoDeleteConfig *)config nowMs:(int64_t)nowMs {
    int64_t lo = 0, hi = 0;
    if (convID.length == 0 || !IMAutoDeleteWindow(config.sec, config.from, nowMs, &lo, &hi)) { return NO; }
    NSString *owner = [self ownerUserID];
    NSMutableSet *synced = IMAutoDeleteServerSyncedSet();
    @synchronized (synced) { if ([synced containsObject:IMAutoDeleteKey(owner, convID)]) { return NO; } } // 服务端刚给过权威摘要
    __block BOOL changed = NO;
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        changed = [self recomputeSummaryInDB:db owner:owner conv:convID lo:lo hi:hi unreadGone:0];
    }];
    return changed;
}

- (void)resetServerSyncedSummaryMarks {
    NSMutableSet *synced = IMAutoDeleteServerSyncedSet();
    @synchronized (synced) { [synced removeAllObjects]; }
}

@end
