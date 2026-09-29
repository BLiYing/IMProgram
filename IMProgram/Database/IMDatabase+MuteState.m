//  IMDatabase+MuteState.m
//  接口与拆分理由见 IMDatabase+MuteState.h。

#import "IMDatabase+MuteState.h"
#import "IMLog.h"

/// 列是否存在（PRAGMA table_info），自包含实现（不借 IMDatabase.m 的私有同名方法——
/// 那个方法没有在任何跨文件可见的头里声明，本类别没有访问权限，犯不着为一次迁移专门开洞）。
static BOOL IMColumnExists(FMDatabase *db, NSString *column, NSString *table) {
    FMResultSet *rs = [db executeQuery:[NSString stringWithFormat:@"PRAGMA table_info(%@)", table]];
    BOOL found = NO;
    while ([rs next]) {
        if ([[rs stringForColumn:@"name"] isEqualToString:column]) { found = YES; break; }
    }
    [rs close];
    return found;
}

@implementation IMDatabase (MuteState)

- (void)migrateMuteUntilColumnDB:(FMDatabase *)db {
    if (IMColumnExists(db, @"mute_until", @"im_conversation_local")) { return; }
    if (![db executeUpdate:@"ALTER TABLE im_conversation_local ADD COLUMN mute_until INTEGER NOT NULL DEFAULT 0"]) {
        IMLogDatabase(@"迁移失败：im_conversation_local 补列 mute_until 未成功: %@", db.lastErrorMessage);
    }
}

@end
