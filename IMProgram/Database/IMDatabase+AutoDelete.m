//  IMDatabase+AutoDelete.m
//  语义、拆分理由见 IMDatabase+AutoDelete.h。

#import "IMDatabase+AutoDelete.h"
#import "IMDatabase+Ranges.h"   // dbQueue / ownerUserID
#import "IMAutoDelete.h"
#import "IMProtocol.h"   // kIMTypeMsgOp
#import "IMLog.h"

#pragma mark - 内存缓存（落库闸用）

static NSMutableDictionary<NSString *, NSNumber *> *IMAutoDeleteCache(void) {
    static NSMutableDictionary *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    return cache;
}
static NSString *IMAutoDeleteKey(NSString *owner, NSString *convID) {
    return [NSString stringWithFormat:@"%@\n%@", owner, convID];
}
static void IMAutoDeleteCacheSet(NSString *owner, NSString *convID, int64_t sec) {
    NSMutableDictionary *c = IMAutoDeleteCache();
    @synchronized (c) { c[IMAutoDeleteKey(owner, convID)] = @(sec); }
}
static void IMAutoDeleteCacheDropOwner(NSString *owner) {
    NSMutableDictionary *c = IMAutoDeleteCache();
    NSString *prefix = [owner stringByAppendingString:@"\n"];
    @synchronized (c) {
        for (NSString *k in [c.allKeys copy]) { if ([k hasPrefix:prefix]) { [c removeObjectForKey:k]; } }
    }
}

/// 内存缓存命中则返回（hit=YES）。入库热路径（逐条 / 逐页）用它，免得每条消息多一次 SELECT。
static BOOL IMAutoDeleteCacheLookup(NSString *owner, NSString *convID, int64_t *sec) {
    NSMutableDictionary *c = IMAutoDeleteCache();
    NSNumber *hit;
    @synchronized (c) { hit = c[IMAutoDeleteKey(owner, convID)]; }
    if (hit) { *sec = hit.longLongValue; }
    return hit != nil;
}

/// 该会话档位（内存缓存；未命中就读小表并写回缓存——含 0，所以整页 10 万条最多多 1 次 SELECT）。
static int64_t IMAutoDeleteSecCached(FMDatabase *db, NSString *owner, NSString *convID) {
    NSMutableDictionary *c = IMAutoDeleteCache();
    NSNumber *hit;
    @synchronized (c) { hit = c[IMAutoDeleteKey(owner, convID)]; }
    if (hit) { return hit.longLongValue; }
    FMResultSet *rs = [db executeQuery:@"SELECT sec FROM im_conv_auto_delete_local WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
    int64_t sec = [rs next] ? [rs longLongIntForColumn:@"sec"] : 0;
    [rs close];
    IMAutoDeleteCacheSet(owner, convID, sec);
    return sec;
}

static int64_t IMAutoDeleteNowMs(void) { return (int64_t)([NSDate date].timeIntervalSince1970 * 1000); }

/// msg_op 事件行（撤回/编辑/置顶/删除…）不是消息正文：不受过期闸影响，照常落库 / 推游标（设计 §4；目标已过期则操作落空，幂等）。
static BOOL IMAutoDeleteIsEventRow(IMMessageModel *message) {
    return [message.contentType isEqualToString:kIMTypeMsgOp];
}

BOOL IMAutoDeleteDropsMessage(FMDatabase *db, NSString *owner, IMMessageModel *message) {
    if (IMAutoDeleteIsEventRow(message)) { return NO; }
    if (message.convSeq <= 0 || message.timestamp <= 0 || message.convID.length == 0) { return NO; }
    return IMAutoDeleteExpired(message.timestamp, IMAutoDeleteSecCached(db, owner, message.convID), IMAutoDeleteNowMs());
}

#pragma mark - 实现

@implementation IMDatabase (AutoDelete)

- (void)migrateAutoDeleteTableDB:(FMDatabase *)db {
    if (![db executeUpdate:
          @"CREATE TABLE IF NOT EXISTS im_conv_auto_delete_local ("
           "owner_uid TEXT NOT NULL, conv_id TEXT NOT NULL, sec INTEGER NOT NULL DEFAULT 0,"
           "PRIMARY KEY(owner_uid,conv_id))"]) {
        IMLogDatabase(@"自动删除档位建表失败: %@", db.lastErrorMessage);
        return;
    }
}

- (int64_t)autoDeleteSecForConv:(NSString *)convID {
    if (convID.length == 0) { return 0; }
    NSString *owner = [self ownerUserID];
    __block int64_t sec = 0;
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT sec FROM im_conv_auto_delete_local WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
        sec = [rs next] ? [rs longLongIntForColumn:@"sec"] : 0;
        [rs close];
    }];
    IMAutoDeleteCacheSet(owner, convID, sec);
    return sec;
}

- (BOOL)setAutoDeleteSec:(int64_t)sec forConv:(NSString *)convID {
    if (convID.length == 0) { return NO; }
    if (!IMAutoDeleteIsValidSec(sec)) { sec = 0; }
    NSString *owner = [self ownerUserID];
    int64_t old = [self autoDeleteSecForConv:convID];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        if (![db executeUpdate:
              @"INSERT INTO im_conv_auto_delete_local (owner_uid,conv_id,sec) VALUES (?,?,?) "
               "ON CONFLICT(owner_uid,conv_id) DO UPDATE SET sec=excluded.sec", owner, convID, @(sec)]) {
            IMLogDatabase(@"写自动删除档位失败 conv=%@: %@", convID, db.lastErrorMessage);
        }
    }];
    IMAutoDeleteCacheSet(owner, convID, sec);
    return old != sec;
}

- (void)persistAutoDeleteFromConversations:(NSArray<IMConversation *> *)conversations {
    NSString *owner = [self ownerUserID];
    __block BOOL committed = NO;
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if (![db executeUpdate:@"DELETE FROM im_conv_auto_delete_local WHERE owner_uid=?", owner]) { *rollback = YES; return; }
        for (IMConversation *c in conversations) {
            if (c.convID.length == 0) { continue; }
            int64_t sec = IMAutoDeleteIsValidSec(c.autoDeleteSec) ? c.autoDeleteSec : 0;
            if (sec <= 0) { continue; }
            if (![db executeUpdate:@"INSERT INTO im_conv_auto_delete_local (owner_uid,conv_id,sec) VALUES (?,?,?)",
                  owner, c.convID, @(sec)]) {
                IMLogDatabase(@"落自动删除档位失败 conv=%@: %@", c.convID, db.lastErrorMessage);
                *rollback = YES; return;
            }
        }
        committed = YES;
    }];
    if (!committed) { return; }
    // 提交后再换缓存（回滚时缓存与表保持一致）
    IMAutoDeleteCacheDropOwner(owner);
    for (IMConversation *c in conversations) {
        if (c.convID.length > 0) { IMAutoDeleteCacheSet(owner, c.convID, IMAutoDeleteIsValidSec(c.autoDeleteSec) ? c.autoDeleteSec : 0); }
    }
}

/// 缓存优先的档位读取（所有写档位的路径都会同步写缓存，未命中才回落读表）。
- (int64_t)cachedAutoDeleteSecForConv:(NSString *)convID {
    int64_t sec = 0;
    if (IMAutoDeleteCacheLookup([self ownerUserID], convID, &sec)) { return sec; }
    return [self autoDeleteSecForConv:convID];
}

- (BOOL)autoDeleteDropsIncoming:(IMMessageModel *)message {
    if (IMAutoDeleteIsEventRow(message)) { return NO; }
    if (message.convSeq <= 0 || message.timestamp <= 0 || message.convID.length == 0) { return NO; } // 无时间戳按未过期（同落库闸 IMAutoDeleteDropsMessage）
    return IMAutoDeleteExpired(message.timestamp, [self cachedAutoDeleteSecForConv:message.convID], IMAutoDeleteNowMs());
}

- (NSArray<IMMessageModel *> *)messagesDroppingAutoDeleteExpired:(NSArray<IMMessageModel *> *)messages {
    if (messages.count == 0) { return messages; }
    int64_t sec = [self cachedAutoDeleteSecForConv:messages.firstObject.convID];
    if (sec <= 0) { return messages; }
    int64_t now = IMAutoDeleteNowMs();
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray arrayWithCapacity:messages.count];
    for (IMMessageModel *m in messages) {
        if (m.convSeq <= 0 || m.timestamp <= 0 || IMAutoDeleteIsEventRow(m) || !IMAutoDeleteExpired(m.timestamp, sec, now)) { [out addObject:m]; }
    }
    return out;
}

- (NSArray<IMPinnedMessage *> *)pinnedItemsDroppingAutoDeleteExpired:(NSArray<IMPinnedMessage *> *)items convID:(NSString *)convID {
    int64_t sec = [self autoDeleteSecForConv:convID];
    if (sec <= 0 || items.count == 0) { return items; }
    int64_t now = IMAutoDeleteNowMs();
    NSMutableArray<IMPinnedMessage *> *out = [NSMutableArray arrayWithCapacity:items.count];
    for (IMPinnedMessage *p in items) { if (p.timestamp <= 0 || !IMAutoDeleteExpired(p.timestamp, sec, now)) { [out addObject:p]; } }
    return out;
}

- (NSDictionary<NSString *, NSNumber *> *)autoDeleteActiveConvs {
    NSString *owner = [self ownerUserID];
    NSMutableDictionary<NSString *, NSNumber *> *out = [NSMutableDictionary dictionary];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT conv_id,sec FROM im_conv_auto_delete_local WHERE owner_uid=? AND sec>0", owner];
        while ([rs next]) {
            out[[rs stringForColumn:@"conv_id"]] = @([rs longLongIntForColumn:@"sec"]);
            IMAutoDeleteCacheSet(owner, [rs stringForColumn:@"conv_id"], [rs longLongIntForColumn:@"sec"]);
        }
        [rs close];
    }];
    return out;
}

#pragma mark - 清理

- (NSArray<NSNumber *> *)deleteExpiredMessagesForConv:(NSString *)convID floorTs:(int64_t)floorTs {
    if (convID.length == 0 || floorTs <= 0) { return @[]; }
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
             "AND conv_seq>0 AND timestamp>0 AND timestamp<=? ORDER BY conv_seq", owner, convID, @(floorTs)];
        while ([rs next]) {
            int64_t seq = [rs longLongIntForColumn:@"conv_seq"];
            [removed addObject:@(seq)];
            NSString *from = [rs stringForColumn:@"sender"];
            BOOL incoming = from.length > 0 && ![from isEqualToString:owner];
            if (incoming && seq > readSeq && ![[rs stringForColumn:@"content_type"] isEqualToString:@"system"]) { unreadGone++; }
        }
        [rs close];
        if (removed.count == 0) { return; }
        if (![db executeUpdate:@"DELETE FROM im_message_local WHERE owner_uid=? AND conv_id=? AND conv_seq>0 AND timestamp>0 AND timestamp<=?",
              owner, convID, @(floorTs)]) {
            IMLogDatabase(@"自动删除清理失败 conv=%@: %@", convID, db.lastErrorMessage);
            [removed removeAllObjects]; *rollback = YES; return;
        }
        [self recomputeSummaryInDB:db owner:owner conv:convID floorTs:floorTs unreadGone:unreadGone];
    }];
    if (removed.count > 0) { IMLogDatabase(@"自动删除 conv=%@ removed=%lu floor=%lld", convID, (unsigned long)removed.count, floorTs); }
    return removed;
}

/// 会话行预览 / 未读本地重算。只在会话摘要所指的最后一条（timestamp）已过期时才改预览；未读按被删的未读条数扣减。
- (void)recomputeSummaryInDB:(FMDatabase *)db owner:(NSString *)owner conv:(NSString *)convID
                     floorTs:(int64_t)floorTs unreadGone:(NSInteger)unreadGone {
    if (unreadGone > 0) {
        [db executeUpdate:@"UPDATE im_conversation_local SET unread=MAX(0,unread-?) WHERE owner_uid=? AND conv_id=?",
         @(unreadGone), owner, convID];
        [db executeUpdate:@"UPDATE im_conversation_local SET mention_unread=0 WHERE owner_uid=? AND conv_id=? AND unread=0", owner, convID];
    }
    FMResultSet *rs = [db executeQuery:@"SELECT timestamp FROM im_conversation_local WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
    int64_t convTs = [rs next] ? [rs longLongIntForColumn:@"timestamp"] : -1;
    [rs close];
    if (convTs < 0 || convTs > floorTs) { return; } // 无会话行，或摘要指的那条没过期
    // 最后一条都过期了 = 整个会话都过期：未读直接清零（与服务端 / Android 同口径）。只按「删掉了几条」扣的话，
    // 本机没有落库的那部分未读（离线积压 / 窗口外）会留在角标上，直到下一次拉会话列表才校正。
    [db executeUpdate:@"UPDATE im_conversation_local SET unread=0,mention_unread=0 WHERE owner_uid=? AND conv_id=?", owner, convID];
    rs = [db executeQuery:
        @"SELECT content,sender,from_nickname,sys_segments,sys_event,sys_args,content_type,caption,recalled_at FROM im_message_local "
         "WHERE owner_uid=? AND conv_id=? AND conv_seq>0 ORDER BY conv_seq DESC LIMIT 1", owner, convID];
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

@end
