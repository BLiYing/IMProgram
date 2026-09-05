#import "IMDatabase+Ranges.h"
#import "IMLog.h"

BOOL IMRegisterRangeInDB(FMDatabase *db, NSString *owner, NSString *convID, int64_t lo, int64_t hi) {
    if (owner.length == 0 || convID.length == 0 || hi < lo || hi <= 0) { return YES; } // 无效入参当无事发生
    int64_t newLo = MAX((int64_t)1, lo), mergedLo = MAX((int64_t)1, lo), mergedHi = hi;
    // 与新区间**重叠或相邻**的既有段全部吞并。相邻也要并（hi+1==lo）：conv_seq 是连续整数，
    // [1,10] 与 [11,20] 之间没有空隙，留成两段会让"本地齐全"判定永远为假。
    FMResultSet *rs = [db executeQuery:
        @"SELECT lo,hi FROM im_conv_range_local WHERE owner_uid=? AND conv_id=? AND hi>=? AND lo<=?",
        owner, convID, @(newLo - 1), @(hi + 1)];
    while ([rs next]) {
        mergedLo = MIN(mergedLo, [rs longLongIntForColumn:@"lo"]);
        mergedHi = MAX(mergedHi, [rs longLongIntForColumn:@"hi"]);
    }
    [rs close];
    if (![db executeUpdate:@"DELETE FROM im_conv_range_local WHERE owner_uid=? AND conv_id=? AND hi>=? AND lo<=?",
          owner, convID, @(newLo - 1), @(hi + 1)]) { return NO; }
    return [db executeUpdate:@"INSERT OR REPLACE INTO im_conv_range_local (owner_uid,conv_id,lo,hi) VALUES (?,?,?,?)",
            owner, convID, @(mergedLo), @(mergedHi)];
}

@implementation IMDatabase (Ranges)

- (int64_t)localSegmentStartInConv:(NSString *)convID containingSeq:(int64_t)seq {
    if (convID.length == 0 || seq <= 0) { return 0; }
    NSString *owner = [self ownerUserID];
    __block int64_t start = 0;
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT lo FROM im_conv_range_local WHERE owner_uid=? AND conv_id=? AND lo<=? AND hi>=? LIMIT 1",
            owner, convID, @(seq), @(seq)];
        if ([rs next]) { start = [rs longLongIntForColumn:@"lo"]; }
        [rs close];
        if (start == 0) {
            // 老库兼容（同 rangesForConv:）：没有任何区间行时，连续游标即首段 [1, synced]。
            FMResultSet *c = [db executeQuery:
                @"SELECT COUNT(*) AS n FROM im_conv_range_local WHERE owner_uid=? AND conv_id=?", owner, convID];
            BOOL empty = [c next] && [c longForColumn:@"n"] == 0;
            [c close];
            if (empty) {
                FMResultSet *s2 = [db executeQuery:
                    @"SELECT synced_conv_seq FROM im_conversation_local WHERE owner_uid=? AND conv_id=? LIMIT 1",
                    owner, convID];
                int64_t synced = [s2 next] ? [s2 longLongIntForColumn:@"synced_conv_seq"] : 0;
                [s2 close];
                if (synced >= seq) { start = 1; }
            }
        }
    }];
    return start;
}

/// 在已开启的 db 上读区间（升序）。私有：对外一律走 rangesForConv:，它带 owner 隔离与队列。
- (NSArray<NSArray<NSNumber *> *> *)rangesInConv:(NSString *)convID owner:(NSString *)owner db:(FMDatabase *)db {
    NSMutableArray<NSArray<NSNumber *> *> *out = [NSMutableArray array];
    FMResultSet *rs = [db executeQuery:
        @"SELECT lo,hi FROM im_conv_range_local WHERE owner_uid=? AND conv_id=? ORDER BY lo ASC", owner, convID];
    while ([rs next]) {
        [out addObject:@[@([rs longLongIntForColumn:@"lo"]), @([rs longLongIntForColumn:@"hi"])]];
    }
    [rs close];
    return out;
}

- (NSArray<NSArray<NSNumber *> *> *)rangesForConv:(NSString *)convID {
    if (convID.length == 0) { return @[]; }
    NSString *owner = [self ownerUserID];
    __block NSArray<NSArray<NSNumber *> *> *out = @[];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        out = [self rangesInConv:convID owner:owner db:db];
        // 老库兼容：还没有任何区间行时，用连续游标反推出首段 [1, synced]——升级前本地就是
        // "从头连续拉到游标处"，那正好是一段。不这么做的话，所有老用户升级后会被判成
        // "整个会话都有缺口"，本地搜索一夜之间全改走服务端、离线时集体降级。
        if (out.count == 0) {
            FMResultSet *rs = [db executeQuery:
                @"SELECT synced_conv_seq FROM im_conversation_local WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
            int64_t synced = [rs next] ? [rs longLongIntForColumn:@"synced_conv_seq"] : 0;
            [rs close];
            if (synced > 0) { out = @[@[@1, @(synced)]]; }
        }
    }];
    return out;
}

- (NSArray<NSArray<NSNumber *> *> *)registerRangeInConv:(NSString *)convID from:(int64_t)lo to:(int64_t)hi {
    if (convID.length == 0 || hi < lo || hi <= 0) { return [self rangesForConv:convID]; }
    NSString *owner = [self ownerUserID];
    __block NSArray<NSArray<NSNumber *> *> *out = @[];
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if (!IMRegisterRangeInDB(db, owner, convID, lo, hi)) {
            IMLogDatabase(@"区间登记失败 conv=%@ [%lld,%lld]: %@", convID, lo, hi, db.lastErrorMessage);
            *rollback = YES; return;
        }
        out = [self rangesInConv:convID owner:owner db:db];
    }];
    return out;
}

- (int64_t)headConvSeqForConv:(NSString *)convID {
    if (convID.length == 0) { return 0; }
    NSString *owner = [self ownerUserID];
    __block int64_t head = 0;
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT head_conv_seq FROM im_conversation_local WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
        if ([rs next]) { head = [rs longLongIntForColumn:@"head_conv_seq"]; }
        [rs close];
    }];
    return head;
}

- (void)updateHeadConvSeq:(int64_t)head forConv:(NSString *)convID {
    if (convID.length == 0 || head <= 0) { return; }
    NSString *owner = [self ownerUserID];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        // MAX 单调：head 只会前进。乱序到达的旧快照不得把它拉回去，否则"齐全"判定会来回抖。
        if (![db executeUpdate:
              @"UPDATE im_conversation_local SET head_conv_seq=MAX(head_conv_seq,?) WHERE owner_uid=? AND conv_id=?",
              @(head), owner, convID]) {
            IMLogDatabase(@"head 位点写入失败 conv=%@ head=%lld: %@", convID, head, db.lastErrorMessage);
        } else if (db.changes == 0) {
            // 会话缓存行还没建（列表接口尚未回来）→ 这次 head 就丢了。刻意**不** INSERT 占位行：
            // 会话列表是 `SELECT * FROM im_conversation_local` 直出，凭空插一行会变成界面上一条
            // 无名空会话。留日志即可，下一次 sync/bump 会补上。
            IMLogDatabase(@"head 位点无处可写（会话缓存行尚未建）conv=%@ head=%lld", convID, head);
        }
    }];
}

- (BOOL)conv:(NSString *)convID coversFrom:(int64_t)lo to:(int64_t)hi {
    if (hi < lo) { return NO; }
    for (NSArray<NSNumber *> *r in [self rangesForConv:convID]) {
        if (r.firstObject.longLongValue <= lo && r.lastObject.longLongValue >= hi) { return YES; }
    }
    return NO;
}

- (BOOL)isConvComplete:(NSString *)convID {
    int64_t head = [self headConvSeqForConv:convID];
    if (head <= 0) { return YES; } // 上界未知 → 无从判断缺什么，保持改造前的行为（当作齐全）
    for (NSArray<NSNumber *> *r in [self rangesForConv:convID]) {
        if (r.firstObject.longLongValue <= 1 && r.lastObject.longLongValue >= head) { return YES; }
    }
    return NO;
}

#pragma mark - 整页原子落库

- (BOOL)saveIncomingPage:(NSArray<IMMessageModel *> *)messages
               advanceTo:(int64_t)advanceTo
                 rangeLo:(int64_t)rangeLo
                 rangeHi:(int64_t)rangeHi {
    if (messages.count == 0) { return YES; }
    NSString *convID = messages.firstObject.convID;
    if (convID.length == 0) { return NO; }
    NSString *owner = [self ownerUserID];
    __block BOOL ok = NO;
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        for (IMMessageModel *m in messages) {
            // 逐条写，但**游标由页尾统一推**（这里传 0）：页内任一条失败即整页回滚，
            // 于是"消息没落住"与"位点越过了"不可能同时发生。
            if (![self writeIncomingMessage:m owner:owner advancingSyncedConvSeq:0 inDB:db]) {
                IMLogDatabase(@"整页落库失败，回滚 conv=%@ seq=%lld", convID, m.convSeq);
                *rollback = YES;
                return;
            }
        }
        if (advanceTo > 0 && ![db executeUpdate:
              @"UPDATE im_conversation_local SET synced_conv_seq=MAX(synced_conv_seq,?) WHERE owner_uid=? AND conv_id=?",
              @(advanceTo), owner, convID]) {
            IMLogDatabase(@"整页游标推进失败 conv=%@ to=%lld: %@", convID, advanceTo, db.lastErrorMessage);
            *rollback = YES;
            return;
        }
        if (rangeHi >= rangeLo && rangeHi > 0 && !IMRegisterRangeInDB(db, owner, convID, rangeLo, rangeHi)) {
            IMLogDatabase(@"整页区间登记失败 conv=%@ [%lld,%lld]: %@", convID, rangeLo, rangeHi, db.lastErrorMessage);
            *rollback = YES;
            return;
        }
        ok = YES;
    }];
    return ok;
}

#pragma mark - ↓N 计数

// 与 isConvComplete: 成对使用：本地齐全时数本地（准且快），有缺口时数出来必然偏小，
// 调用方须改用 head−已滚入位点（OFFLINE_BACKLOG_DESIGN §4.9 第 8 项）。
- (NSArray<IMMessageModel *> *)latestContiguousMessagesForConv:(NSString *)convID limit:(NSInteger)limit {
    NSArray<IMMessageModel *> *rows = [self latestMessagesForConv:convID limit:limit];
    if (rows.count == 0) { return rows; }
    int64_t newest = 0;
    for (IMMessageModel *m in rows) { if (m.convSeq > newest) { newest = m.convSeq; } }
    if (newest <= 0) { return rows; }                       // 全是待发消息，无段可言
    int64_t segStart = [self localSegmentStartInConv:convID containingSeq:newest];
    if (segStart <= 0) { return rows; }                     // 老库没登记过区间 → 维持原行为
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray arrayWithCapacity:rows.count];
    // conv_seq<=0 是待发/失败的本地消息，排序后必在尾段里，**不能**被段判据剔掉，
    // 否则刚发出去还没拿到序号的那条会从首窗里消失。
    for (IMMessageModel *m in rows) {
        if (m.convSeq <= 0 || m.convSeq >= segStart) { [out addObject:m]; }
    }
    return out;
}

- (NSArray<IMMessageModel *> *)contiguousMessagesForConv:(NSString *)convID
                                           beforeConvSeq:(int64_t)beforeConvSeq
                                                   limit:(NSInteger)limit {
    if (beforeConvSeq <= 0) { return @[]; }
    int64_t segStart = [self localSegmentStartInConv:convID containingSeq:beforeConvSeq];
    if (segStart <= 0 || segStart >= beforeConvSeq) { return @[]; } // 无清单可依 / 本段已到头
    NSArray<IMMessageModel *> *rows = [self messagesForConv:convID beforeConvSeq:beforeConvSeq limit:limit];
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray arrayWithCapacity:rows.count];
    for (IMMessageModel *m in rows) {
        if (m.convSeq >= segStart) { [out addObject:m]; } // 段外的一律丢弃：那是缺口另一侧的旧岛
    }
    return out;
}

/// 包含 seq 的那一段的**终点**；seq 不在任何段内返回 0。与 localSegmentStartInConv: 对称。
- (int64_t)localSegmentEndInConv:(NSString *)convID containingSeq:(int64_t)seq {
    if (convID.length == 0 || seq <= 0) { return 0; }
    NSString *owner = [self ownerUserID];
    __block int64_t end = 0;
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT hi FROM im_conv_range_local WHERE owner_uid=? AND conv_id=? AND lo<=? AND hi>=? LIMIT 1",
            owner, convID, @(seq), @(seq)];
        if ([rs next]) { end = [rs longLongIntForColumn:@"hi"]; }
        [rs close];
    }];
    return end;
}

- (NSArray<IMMessageModel *> *)contiguousMessagesForConv:(NSString *)convID
                                            afterConvSeq:(int64_t)afterConvSeq
                                                   limit:(NSInteger)limit {
    if (afterConvSeq <= 0) { return @[]; }
    int64_t segEnd = [self localSegmentEndInConv:convID containingSeq:afterConvSeq];
    if (segEnd <= 0) {
        // 无清单可依（老库从没登记过区间）→ 维持改造前行为，直接取下一页。
        return [self messagesForConv:convID aroundConvSeq:afterConvSeq before:0 after:limit];
    }
    if (segEnd <= afterConvSeq) { return @[]; }   // 本段已到头
    NSArray<IMMessageModel *> *rows = [self messagesForConv:convID aroundConvSeq:afterConvSeq before:0 after:limit];
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray arrayWithCapacity:rows.count];
    for (IMMessageModel *m in rows) {
        if (m.convSeq <= segEnd) { [out addObject:m]; } // 段外的一律丢弃：那是缺口另一侧的下一段
    }
    return out;
}

- (NSInteger)countIncomingInConv:(NSString *)convID afterConvSeq:(int64_t)afterConvSeq {
    __block NSInteger n = 0;
    NSString *owner = [self ownerUserID];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT COUNT(*) AS n FROM im_message_local "
             "WHERE owner_uid=? AND conv_id=? AND sender<>? AND conv_seq>?",
            owner, convID, owner, @(afterConvSeq)];
        if ([rs next]) { n = (NSInteger)[rs longForColumn:@"n"]; }
        [rs close];
    }];
    return n;
}

@end
