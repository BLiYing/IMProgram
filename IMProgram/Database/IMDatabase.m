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
             "conv_seq INTEGER, timestamp INTEGER, status INTEGER)"];
        if (!ok) { IMLog(@"[db] 建表失败: %@", db.lastErrorMessage); }
        [db executeUpdate:@"CREATE INDEX IF NOT EXISTS idx_local_conv ON im_message_local(conv_id)"];
    }];
}

#pragma mark - 读写（接口语义同归档版：出站按 client_msg_id upsert，入站按 conv_seq 去重；保持插入顺序）

- (void)saveMessage:(IMMessageModel *)message {
    if (message.convID.length == 0) { return; }
    [_queue inDatabase:^(FMDatabase *db) {
        NSNumber *rowID = [self existingRowIDFor:message in:db];
        if (rowID) {
            [db executeUpdate:
                @"UPDATE im_message_local SET server_msg_id=?,sender=?,recipient=?,content_type=?,content=?,conv_seq=?,timestamp=?,status=? WHERE row_id=?",
                message.serverMsgID ?: @"", message.from ?: @"", message.to ?: @"",
                message.contentType ?: @"text", message.content ?: @"",
                @(message.convSeq), @(message.timestamp), @(message.status), rowID];
        } else {
            [db executeUpdate:
                @"INSERT INTO im_message_local (client_msg_id,server_msg_id,conv_id,sender,recipient,content_type,content,conv_seq,timestamp,status) VALUES (?,?,?,?,?,?,?,?,?,?)",
                message.clientMsgID ?: @"", message.serverMsgID ?: @"", message.convID,
                message.from ?: @"", message.to ?: @"", message.contentType ?: @"text",
                message.content ?: @"", @(message.convSeq), @(message.timestamp), @(message.status)];
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

@end
