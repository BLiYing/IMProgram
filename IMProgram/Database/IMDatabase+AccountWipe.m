//  IMDatabase+AccountWipe.m
//  语义、拆分理由见 IMDatabase+AccountWipe.h。

#import "IMDatabase+AccountWipe.h"
#import "IMDatabase+Ranges.h"   // dbQueue / ownerUserID 内部访问器
#import "IMLog.h"
#import "IMPendingMediaStore.h"

/// 带 owner_uid 列的全部用户表名（排除 sqlite_ 内部表）。
static NSArray<NSString *> *IMOwnerScopedTables(FMDatabase *db) {
    NSMutableArray<NSString *> *tables = [NSMutableArray array];
    FMResultSet *rs = [db executeQuery:@"SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"];
    while ([rs next]) { [tables addObject:[rs stringForColumnIndex:0]]; }
    [rs close];
    NSMutableArray<NSString *> *scoped = [NSMutableArray array];
    for (NSString *t in tables) {
        FMResultSet *info = [db executeQuery:[NSString stringWithFormat:@"PRAGMA table_info(\"%@\")", t]];
        while ([info next]) {
            if ([[info stringForColumn:@"name"] isEqualToString:@"owner_uid"]) { [scoped addObject:t]; break; }
        }
        [info close];
    }
    return scoped;
}

@implementation IMDatabase (AccountWipe)

- (NSArray<NSString *> *)pendingMediaLocalRefsForCurrentOwner {
    NSString *owner = [self ownerUserID];
    if (owner.length == 0 || [owner isEqualToString:@"__default__"]) { return @[]; }
    NSMutableArray<NSString *> *refs = [NSMutableArray array];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT content FROM im_message_local WHERE owner_uid=? AND content LIKE ?",
                           owner, [kIMPendingMediaScheme stringByAppendingString:@"%"]];
        while ([rs next]) {
            NSString *c = [rs stringForColumnIndex:0];
            if (c.length > 0) { [refs addObject:c]; }
        }
        [rs close];
    }];
    return refs;
}

- (BOOL)wipeAllDataForCurrentOwner {
    NSString *owner = [self ownerUserID];
    if (owner.length == 0 || [owner isEqualToString:@"__default__"]) { return NO; }
    __block BOOL ok = YES;
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        for (NSString *table in IMOwnerScopedTables(db)) {
            NSString *sql = [NSString stringWithFormat:@"DELETE FROM \"%@\" WHERE owner_uid=?", table];
            if (![db executeUpdate:sql, owner]) {
                IMLogDatabase(@"注销清库失败 table=%@: %@", table, db.lastErrorMessage);
                ok = NO;
                *rollback = YES;
                return;
            }
        }
    }];
    return ok;
}

@end
