//  IMDatabase+ClearFloor.m
//  语义、拆分理由见 IMDatabase+ClearFloor.h。

#import "IMDatabase+ClearFloor.h"
#import "IMDatabase+Ranges.h"   // dbQueue / ownerUserID（RangesPrivate 内部访问器）
#import "IMLog.h"

int64_t IMClearFloorAtClear(int64_t head, int64_t latestConvSeq, int64_t synced, int64_t maxLocalSeq,
                            int64_t existingClearedUpTo) {
    return MAX(MAX(MAX(head, latestConvSeq), MAX(synced, maxLocalSeq)), MAX(existingClearedUpTo, (int64_t)0));
}

int64_t IMClearedUpToInDB(FMDatabase *db, NSString *owner, NSString *convID) {
    if (owner.length == 0 || convID.length == 0) { return 0; }
    FMResultSet *rs = [db executeQuery:
        @"SELECT cleared_up_to FROM im_conv_clear_floor_local WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
    int64_t floor = [rs next] ? [rs longLongIntForColumn:@"cleared_up_to"] : 0;
    [rs close];
    return floor;
}

BOOL IMRaiseSyncedToClearFloorInDB(FMDatabase *db, NSString *owner, NSString * _Nullable convID) {
    NSString *sql = @"UPDATE im_conversation_local SET synced_conv_seq=MAX(synced_conv_seq, COALESCE("
        "(SELECT f.cleared_up_to FROM im_conv_clear_floor_local f WHERE f.owner_uid=im_conversation_local.owner_uid "
        "AND f.conv_id=im_conversation_local.conv_id),0)) WHERE owner_uid=?";
    BOOL ok = convID.length > 0 ? [db executeUpdate:[sql stringByAppendingString:@" AND conv_id=?"], owner, convID]
                                : [db executeUpdate:sql, owner];
    if (!ok) { IMLogDatabase(@"游标抬到清空位点失败 owner=%@ conv=%@: %@", owner, convID ?: @"*", db.lastErrorMessage); }
    return ok;
}

/// 列是否存在（同 IMDatabase+MuteState.m：自包含，不借主文件的私有同名方法）。
static BOOL IMClearFloorColumnExists(FMDatabase *db, NSString *column, NSString *table) {
    FMResultSet *rs = [db executeQuery:[NSString stringWithFormat:@"PRAGMA table_info(%@)", table]];
    BOOL found = NO;
    while ([rs next]) {
        if ([[rs stringForColumn:@"name"] isEqualToString:column]) { found = YES; break; }
    }
    [rs close];
    return found;
}

NSArray<IMMessageModel *> *IMDropClearedMessages(NSArray<IMMessageModel *> *messages, int64_t clearedUpTo) {
    if (clearedUpTo <= 0 || messages.count == 0) { return messages; }
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray arrayWithCapacity:messages.count];
    for (IMMessageModel *m in messages) {
        if (m.convSeq <= 0 || m.convSeq > clearedUpTo) { [out addObject:m]; }
    }
    return out;
}

/// 小表是否已存在（迁移只在它刚建出来的那一次跑）。
static BOOL IMClearFloorTableExists(FMDatabase *db) {
    FMResultSet *rs = [db executeQuery:@"SELECT name FROM sqlite_master WHERE type='table' AND name='im_conv_clear_floor_local'"];
    BOOL found = [rs next];
    [rs close];
    return found;
}

@implementation IMDatabase (ClearFloor)

- (int64_t)clearedUpToForConv:(NSString *)convID {
    if (convID.length == 0) { return 0; }
    NSString *owner = [self ownerUserID];
    __block int64_t floor = 0;
    [self.dbQueue inDatabase:^(FMDatabase *db) { floor = IMClearedUpToInDB(db, owner, convID); }];
    return floor;
}

- (void)migrateClearedUpToColumnDB:(FMDatabase *)db {
    if (IMClearFloorTableExists(db)) { return; }
    BOOL hadColumn = IMClearFloorColumnExists(db, @"cleared_up_to", @"im_conversation_local");
    if (![db beginTransaction]) {
        IMLogDatabase(@"迁移失败：清空位点小表开事务失败: %@", db.lastErrorMessage);
        return;
    }
    BOOL ok = [db executeUpdate:
        @"CREATE TABLE IF NOT EXISTS im_conv_clear_floor_local ("
         "owner_uid TEXT NOT NULL, conv_id TEXT NOT NULL, cleared_up_to INTEGER NOT NULL DEFAULT 0,"
         "PRIMARY KEY(owner_uid,conv_id))"];
    // 早期实现把位点放在会话行的列里：拷过来（MAX 语义；旧列留着不再读写，不做 DROP COLUMN）。
    NSString *upsert = @" ON CONFLICT(owner_uid,conv_id) DO UPDATE SET cleared_up_to=MAX(cleared_up_to,excluded.cleared_up_to)";
    NSString *copy = @"INSERT INTO im_conv_clear_floor_local (owner_uid,conv_id,cleared_up_to) "
        "SELECT owner_uid,conv_id,cleared_up_to FROM im_conversation_local WHERE cleared_up_to>0";
    // 升级回填（对应 Android MIGRATION_15_16）：游标以内本地没有的那一截 = 当年清掉的。
    NSString *backfill = @"INSERT INTO im_conv_clear_floor_local (owner_uid,conv_id,cleared_up_to) "
        "SELECT c.owner_uid,c.conv_id,v FROM (SELECT owner_uid,conv_id,COALESCE("
        "(SELECT MIN(m.conv_seq) FROM im_message_local m WHERE m.owner_uid=im_conversation_local.owner_uid "
        "AND m.conv_id=im_conversation_local.conv_id AND m.conv_seq>0 "
        "AND m.conv_seq<=im_conversation_local.synced_conv_seq) - 1, synced_conv_seq) AS v "
        "FROM im_conversation_local WHERE synced_conv_seq>0) c WHERE c.v>0";
    ok = ok && [db executeUpdate:[(hadColumn ? copy : backfill) stringByAppendingString:upsert]];
    if (ok) { ok = [db commit]; }
    if (!ok) {
        IMLogDatabase(@"迁移失败：清空位点小表建表/拷贝/回填未成功，整体回滚、下次启动重试: %@", db.lastErrorMessage);
        [db rollback];
    }
}

#pragma mark - 清空

/// 一个事务里：删消息、清区间清单、抬位点、游标推到位点。**不动**别的会话、会话行本身（预览/置顶/免打扰）
/// 与任何「隐藏/删除」记录（iOS 本机没有独立墓碑表：本地删除是物理删行，随消息一起走）。
- (NSInteger)clearMessagesForConv:(NSString *)convID {
    if (convID.length == 0) { return 0; }
    NSString *owner = [self ownerUserID];
    __block NSInteger removed = 0;
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        int64_t head = 0, latest = 0, synced = 0, maxLocal = 0;
        int64_t existing = IMClearedUpToInDB(db, owner, convID);
        FMResultSet *rs = [db executeQuery:
            @"SELECT head_conv_seq,latest_conv_seq,synced_conv_seq FROM im_conversation_local "
             "WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
        if ([rs next]) {
            head = [rs longLongIntForColumn:@"head_conv_seq"];
            latest = [rs longLongIntForColumn:@"latest_conv_seq"];
            synced = [rs longLongIntForColumn:@"synced_conv_seq"];
        }
        [rs close];
        rs = [db executeQuery:@"SELECT MAX(conv_seq) AS m FROM im_message_local WHERE owner_uid=? AND conv_id=?", owner, convID];
        if ([rs next]) { maxLocal = [rs longLongIntForColumn:@"m"]; }
        [rs close];
        int64_t floor = IMClearFloorAtClear(head, latest, synced, maxLocal, existing);

        if (![db executeUpdate:@"DELETE FROM im_message_local WHERE owner_uid=? AND conv_id=?", owner, convID]) {
            IMLogDatabase(@"清空消息失败 conv=%@: %@", convID, db.lastErrorMessage);
            *rollback = YES; return;
        }
        removed = (NSInteger)db.changes;
        // 区间清单连消息一起清（清单宣称「这段齐全」而手里一条没有 = 会话空白且不自愈）；
        // 「不拉回」不再靠清单碰巧，而由位点负责。
        if (![db executeUpdate:@"DELETE FROM im_conv_range_local WHERE owner_uid=? AND conv_id=?", owner, convID]) {
            IMLogDatabase(@"清空区间清单失败 conv=%@: %@", convID, db.lastErrorMessage);
            *rollback = YES; return;
        }
        // 位点写独立小表（MAX 只增不减），**不依赖会话行**；会话行在的话游标顺带推到位点。
        if (floor > 0 && !([db executeUpdate:
              @"INSERT INTO im_conv_clear_floor_local (owner_uid,conv_id,cleared_up_to) VALUES (?,?,?) "
               "ON CONFLICT(owner_uid,conv_id) DO UPDATE SET cleared_up_to=MAX(cleared_up_to,excluded.cleared_up_to)",
              owner, convID, @(floor)] && IMRaiseSyncedToClearFloorInDB(db, owner, convID))) {
            IMLogDatabase(@"抬清空位点失败 conv=%@ floor=%lld: %@", convID, floor, db.lastErrorMessage);
            *rollback = YES; return;
        }
        IMLogDatabase(@"清空聊天记录 conv=%@ removed=%ld cleared_up_to=%lld", convID, (long)removed, floor);
    }];
    return removed;
}

@end
