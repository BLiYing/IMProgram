//  IMDatabase.m
//  FMDB + SQLite 实现（线程安全用 FMDatabaseQueue）。接口见 IMDatabase.h，上层无感。

#import "IMDatabase.h"
#import "IMMessageModel.h"
#import "IMLog.h"

#import <FMDB/FMDB.h>

@implementation IMDatabase {
    FMDatabaseQueue *_queue;
}

+ (instancetype)sharedDatabase {
    static IMDatabase *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                           inDomains:NSUserDomainMask].firstObject;
        instance = [[IMDatabase alloc] initWithFileURL:[docs URLByAppendingPathComponent:@"im.sqlite"]];
    });
    return instance;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        _queue = [FMDatabaseQueue databaseQueueWithPath:fileURL.path];
        [self createTables];
    }
    return self;
}

- (void)createTables {
    [_queue inDatabase:^(FMDatabase *db) {
        BOOL ok = [db executeUpdate:
            @"CREATE TABLE IF NOT EXISTS im_message_local ("
             "row_id INTEGER PRIMARY KEY AUTOINCREMENT,"
             "client_msg_id TEXT, server_msg_id TEXT, conv_id TEXT NOT NULL,"
             "sender TEXT, recipient TEXT, content_type TEXT, content TEXT,"
             "conv_seq INTEGER, timestamp INTEGER, status INTEGER, note TEXT)"];
        if (!ok) { IMLog(@"[db] 建表失败: %@", db.lastErrorMessage); }
        [db executeUpdate:@"CREATE INDEX IF NOT EXISTS idx_local_conv ON im_message_local(conv_id)"];
        // 老库迁移（非破坏）：补 note 列——失败消息的系统提示（如被拉黑拒收文案）落库，重进会话不丢。
        if (![self column:@"note" existsInTable:@"im_message_local" db:db]) {
            [db executeUpdate:@"ALTER TABLE im_message_local ADD COLUMN note TEXT"];
        }
        // 老库迁移（非破坏）：补 from_nickname 列——群消息发送者昵称落库，重进群聊气泡仍显昵称（M3）。
        if (![self column:@"from_nickname" existsInTable:@"im_message_local" db:db]) {
            [db executeUpdate:@"ALTER TABLE im_message_local ADD COLUMN from_nickname TEXT"];
        }
        // 老库迁移（非破坏）：补 M4 消息操作派生状态列（撤回/编辑/置顶），重进会话撤回态仍在。
        NSDictionary<NSString *, NSString *> *opCols = @{
            @"recalled_at": @"INTEGER", @"recalled_by": @"TEXT",
            @"edited_at": @"INTEGER", @"pinned_at": @"INTEGER",
            @"reply_to_conv_seq": @"INTEGER", @"reply_snapshot": @"TEXT", // M4-2 引用回复
            @"forward_from": @"TEXT", // M4-3 转发溯源
        };
        for (NSString *col in opCols) {
            if (![self column:col existsInTable:@"im_message_local" db:db]) {
                [db executeUpdate:[NSString stringWithFormat:@"ALTER TABLE im_message_local ADD COLUMN %@ %@", col, opCols[col]]];
            }
        }
    }];
}

/// 列是否存在（PRAGMA table_info），用于幂等的非破坏迁移。
- (BOOL)column:(NSString *)col existsInTable:(NSString *)table db:(FMDatabase *)db {
    FMResultSet *rs = [db executeQuery:[NSString stringWithFormat:@"PRAGMA table_info(%@)", table]];
    BOOL found = NO;
    while ([rs next]) {
        if ([[rs stringForColumn:@"name"] isEqualToString:col]) { found = YES; break; }
    }
    [rs close];
    return found;
}

#pragma mark - 读写（接口语义同归档版：出站按 client_msg_id upsert，入站按 conv_seq 去重；保持插入顺序）

- (void)saveMessage:(IMMessageModel *)message {
    if (message.convID.length == 0) { return; }
    [_queue inDatabase:^(FMDatabase *db) {
        NSNumber *rowID = [self existingRowIDFor:message in:db];
        if (rowID) {
            [db executeUpdate:
                @"UPDATE im_message_local SET server_msg_id=?,sender=?,recipient=?,content_type=?,content=?,conv_seq=?,timestamp=?,status=?,note=?,from_nickname=?,recalled_at=?,recalled_by=?,edited_at=?,pinned_at=?,reply_to_conv_seq=?,reply_snapshot=?,forward_from=? WHERE row_id=?",
                message.serverMsgID ?: @"", message.from ?: @"", message.to ?: @"",
                message.contentType ?: @"text", message.content ?: @"",
                @(message.convSeq), @(message.timestamp), @(message.status), message.note ?: @"",
                message.fromNickname ?: @"", @(message.recalledAt), message.recalledBy ?: @"",
                @(message.editedAt), @(message.pinnedAt), @(message.replyToConvSeq), message.replySnapshot ?: @"", message.forwardFrom ?: @"", rowID];
        } else {
            [db executeUpdate:
                @"INSERT INTO im_message_local (client_msg_id,server_msg_id,conv_id,sender,recipient,content_type,content,conv_seq,timestamp,status,note,from_nickname,recalled_at,recalled_by,edited_at,pinned_at,reply_to_conv_seq,reply_snapshot,forward_from) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                message.clientMsgID ?: @"", message.serverMsgID ?: @"", message.convID,
                message.from ?: @"", message.to ?: @"", message.contentType ?: @"text",
                message.content ?: @"", @(message.convSeq), @(message.timestamp), @(message.status),
                message.note ?: @"", message.fromNickname ?: @"", @(message.recalledAt),
                message.recalledBy ?: @"", @(message.editedAt), @(message.pinnedAt),
                @(message.replyToConvSeq), message.replySnapshot ?: @"", message.forwardFrom ?: @""];
        }
    }];
}

/// 出站消息按 (conv_id, client_msg_id) 匹配；入站（无 client_msg_id）按 (conv_id, conv_seq) 匹配。
- (NSNumber *)existingRowIDFor:(IMMessageModel *)message in:(FMDatabase *)db {
    FMResultSet *rs = nil;
    if (message.clientMsgID.length > 0) {
        rs = [db executeQuery:@"SELECT row_id FROM im_message_local WHERE conv_id=? AND client_msg_id=? LIMIT 1",
              message.convID, message.clientMsgID];
    } else if (message.convSeq > 0) {
        rs = [db executeQuery:@"SELECT row_id FROM im_message_local WHERE conv_id=? AND (client_msg_id IS NULL OR client_msg_id='') AND conv_seq=? LIMIT 1",
              message.convID, @(message.convSeq)];
    }
    NSNumber *rowID = nil;
    if (rs && [rs next]) { rowID = @([rs longLongIntForColumn:@"row_id"]); }
    [rs close];
    return rowID;
}

- (NSArray<IMMessageModel *> *)messagesForConv:(NSString *)convID {
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray array];
    [_queue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT * FROM im_message_local WHERE conv_id=? ORDER BY row_id ASC", convID];
        while ([rs next]) {
            IMMessageModel *m = [IMMessageModel new];
            m.clientMsgID = [rs stringForColumn:@"client_msg_id"];
            m.serverMsgID = [rs stringForColumn:@"server_msg_id"];
            m.convID      = [rs stringForColumn:@"conv_id"];
            m.from        = [rs stringForColumn:@"sender"];
            m.to          = [rs stringForColumn:@"recipient"];
            m.contentType = [rs stringForColumn:@"content_type"];
            m.content     = [rs stringForColumn:@"content"];
            m.convSeq     = [rs longLongIntForColumn:@"conv_seq"];
            m.timestamp   = [rs longLongIntForColumn:@"timestamp"];
            m.status      = (IMMessageStatus)[rs longForColumn:@"status"];
            NSString *note = [rs stringForColumn:@"note"];
            m.note        = note.length > 0 ? note : nil; // 空串视作无系统提示
            NSString *nick = [rs stringForColumn:@"from_nickname"];
            m.fromNickname = nick.length > 0 ? nick : nil; // 空串视作无昵称（回退 uid）
            m.recalledAt  = [rs longLongIntForColumn:@"recalled_at"];
            NSString *rby = [rs stringForColumn:@"recalled_by"];
            m.recalledBy  = rby.length > 0 ? rby : nil;
            m.editedAt    = [rs longLongIntForColumn:@"edited_at"];
            m.pinnedAt    = [rs longLongIntForColumn:@"pinned_at"];
            m.replyToConvSeq = [rs longLongIntForColumn:@"reply_to_conv_seq"];
            NSString *snap = [rs stringForColumn:@"reply_snapshot"];
            m.replySnapshot = snap.length > 0 ? snap : nil;
            NSString *ff = [rs stringForColumn:@"forward_from"];
            m.forwardFrom = ff.length > 0 ? ff : nil;
            [out addObject:m];
        }
        [rs close];
    }];
    return out;
}

- (void)deleteMessage:(IMMessageModel *)message {
    if (message.convID.length == 0) { return; }
    [_queue inDatabase:^(FMDatabase *db) {
        NSNumber *rowID = [self existingRowIDFor:message in:db];
        if (rowID) {
            [db executeUpdate:@"DELETE FROM im_message_local WHERE row_id=?", rowID];
        }
    }];
}

- (int64_t)maxConvSeqForConv:(NSString *)convID {
    __block int64_t maxSeq = 0;
    [_queue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT MAX(conv_seq) AS m FROM im_message_local WHERE conv_id=?", convID];
        if ([rs next]) { maxSeq = [rs longLongIntForColumn:@"m"]; }
        [rs close];
    }];
    return maxSeq;
}

- (void)applyMsgOpForConv:(NSString *)convID
            targetConvSeq:(int64_t)targetConvSeq
               recalledAt:(int64_t)recalledAt
               recalledBy:(nullable NSString *)recalledBy
                 editedAt:(int64_t)editedAt
                 pinnedAt:(int64_t)pinnedAt
               newContent:(nullable NSString *)newContent {
    if (convID.length == 0 || targetConvSeq <= 0) { return; }
    [_queue inDatabase:^(FMDatabase *db) {
        NSMutableArray *sets = [NSMutableArray array];
        NSMutableArray *args = [NSMutableArray array];
        if (recalledAt > 0) { [sets addObject:@"recalled_at=?"]; [args addObject:@(recalledAt)];
                              [sets addObject:@"recalled_by=?"]; [args addObject:recalledBy ?: @""]; }
        if (editedAt > 0)   { [sets addObject:@"edited_at=?"];   [args addObject:@(editedAt)]; }
        if (pinnedAt > 0)   { [sets addObject:@"pinned_at=?"];   [args addObject:@(pinnedAt)]; }
        if (newContent != nil) { [sets addObject:@"content=?"]; [args addObject:newContent]; }
        if (sets.count == 0) { return; }
        NSString *sql = [NSString stringWithFormat:@"UPDATE im_message_local SET %@ WHERE conv_id=? AND conv_seq=?",
                         [sets componentsJoinedByString:@","]];
        [args addObject:convID];
        [args addObject:@(targetConvSeq)];
        [db executeUpdate:sql withArgumentsInArray:args];
    }];
}

@end
