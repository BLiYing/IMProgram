//  IMDatabase.m
//  FMDB + SQLite 实现（线程安全用 FMDatabaseQueue）。接口见 IMDatabase.h，上层无感。

#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMMessageModel.h"
#import "IMLog.h"

#import <FMDB/FMDB.h>

@interface IMDatabase ()

- (BOOL)updateConversationForMessage:(IMMessageModel *)message
                               owner:(NSString *)owner
                            inserted:(BOOL)inserted
                                inDB:(FMDatabase *)db;
- (void)writeCachedConversations:(NSArray<IMConversation *> *)conversations;

@end

@implementation IMDatabase {
    FMDatabaseQueue *_queue;
    NSString *_ownerUserID;
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
        _ownerUserID = @"__default__";
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
             "owner_uid TEXT NOT NULL DEFAULT '',"
             "client_msg_id TEXT, server_msg_id TEXT, conv_id TEXT NOT NULL,"
             "sender TEXT, recipient TEXT, content_type TEXT, content TEXT,"
             "conv_seq INTEGER, timestamp INTEGER, status INTEGER, note TEXT)"];
        if (!ok) { IMLogDatabase(@"建表失败: %@", db.lastErrorMessage); }
        if (![self column:@"owner_uid" existsInTable:@"im_message_local" db:db]) {
            [db executeUpdate:@"ALTER TABLE im_message_local ADD COLUMN owner_uid TEXT NOT NULL DEFAULT ''"];
        }
        [db executeUpdate:@"CREATE INDEX IF NOT EXISTS idx_local_owner_conv ON im_message_local(owner_uid,conv_id)"];
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
            @"group_id": @"TEXT",     // M4+ 相册分组（同批多图/视频聚簇渲染宫格）
            @"poster": @"TEXT",       // M4+ 视频封面首帧 URL
        };
        for (NSString *col in opCols) {
            if (![self column:col existsInTable:@"im_message_local" db:db]) {
                [db executeUpdate:[NSString stringWithFormat:@"ALTER TABLE im_message_local ADD COLUMN %@ %@", col, opCols[col]]];
            }
        }

        ok = [db executeUpdate:
            @"CREATE TABLE IF NOT EXISTS im_conversation_local ("
             "owner_uid TEXT NOT NULL, conv_id TEXT NOT NULL, sort_order INTEGER NOT NULL,"
             "is_group INTEGER, name TEXT, avatar_url TEXT, member_count INTEGER,"
             "peer TEXT, peer_nickname TEXT, peer_avatar_url TEXT,"
             "last_content TEXT, last_from TEXT, last_from_nickname TEXT,"
             "last_recalled INTEGER, last_content_type TEXT, latest_conv_seq INTEGER,"
             "read_seq INTEGER, peer_read_seq INTEGER, timestamp INTEGER, unread INTEGER,"
             "pinned_at INTEGER, muted INTEGER, marked_unread INTEGER,server_snapshot_seq INTEGER NOT NULL DEFAULT 0,"
             "PRIMARY KEY(owner_uid,conv_id))"];
        if (!ok) { IMLogDatabase(@"会话缓存建表失败: %@", db.lastErrorMessage); }
        if (![self column:@"server_snapshot_seq" existsInTable:@"im_conversation_local" db:db]) {
            [db executeUpdate:@"ALTER TABLE im_conversation_local ADD COLUMN server_snapshot_seq INTEGER NOT NULL DEFAULT 0"];
        }
    }];
}

- (void)useOwnerUserID:(NSString *)userID {
    NSString *owner = [userID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (owner.length == 0) {
        IMLogDatabase(@"拒绝切换到空 owner_uid，继续使用当前账号命名空间");
        return;
    }
    @synchronized (self) {
        _ownerUserID = [owner copy];
    }
}

- (NSString *)ownerUserID {
    @synchronized (self) {
        return _ownerUserID ?: @"__default__";
    }
}

#pragma mark - 会话缓存

- (NSArray<IMConversation *> *)cachedConversations {
    NSString *owner = [self ownerUserID];
    NSMutableArray<IMConversation *> *out = [NSMutableArray array];
    [_queue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT * FROM im_conversation_local WHERE owner_uid=? ORDER BY CASE WHEN pinned_at>0 THEN 0 ELSE 1 END,pinned_at DESC,sort_order ASC", owner];
        if (!rs) {
            IMLogDatabase(@"读取会话缓存失败 owner=%@: %@", owner, db.lastErrorMessage);
            return;
        }
        while ([rs next]) {
            IMConversation *c = [IMConversation new];
            c.convID = [rs stringForColumn:@"conv_id"] ?: @"";
            c.isGroup = [rs boolForColumn:@"is_group"];
            c.name = [rs stringForColumn:@"name"];
            c.avatarURL = [rs stringForColumn:@"avatar_url"];
            c.memberCount = [rs longForColumn:@"member_count"];
            c.peer = [rs stringForColumn:@"peer"] ?: @"";
            c.peerNickname = [rs stringForColumn:@"peer_nickname"];
            c.peerAvatarURL = [rs stringForColumn:@"peer_avatar_url"];
            c.lastContent = [rs stringForColumn:@"last_content"];
            c.lastFrom = [rs stringForColumn:@"last_from"];
            c.lastFromNickname = [rs stringForColumn:@"last_from_nickname"];
            c.lastRecalled = [rs boolForColumn:@"last_recalled"];
            c.lastContentType = [rs stringForColumn:@"last_content_type"];
            c.latestConvSeq = [rs longLongIntForColumn:@"latest_conv_seq"];
            c.readSeq = [rs longLongIntForColumn:@"read_seq"];
            c.peerReadSeq = [rs longLongIntForColumn:@"peer_read_seq"];
            c.timestamp = [rs longLongIntForColumn:@"timestamp"];
            c.unread = [rs longForColumn:@"unread"];
            c.pinnedAt = [rs longLongIntForColumn:@"pinned_at"];
            c.muted = [rs boolForColumn:@"muted"];
            c.markedUnread = [rs boolForColumn:@"marked_unread"];
            if (c.convID.length > 0) { [out addObject:c]; }
        }
        [rs close];
    }];
    return out;
}

- (void)replaceCachedConversations:(NSArray<IMConversation *> *)conversations {
    [self writeCachedConversations:conversations];
}

- (void)writeCachedConversations:(NSArray<IMConversation *> *)conversations {
    NSString *owner = [self ownerUserID];
    [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if (![db executeUpdate:@"DELETE FROM im_conversation_local WHERE owner_uid=?", owner]) {
            IMLogDatabase(@"清理旧会话缓存失败 owner=%@: %@", owner, db.lastErrorMessage);
            *rollback = YES;
            return;
        }
        [conversations enumerateObjectsUsingBlock:^(IMConversation *c, NSUInteger idx, BOOL *stop) {
            if (c.convID.length == 0) { return; }
            BOOL ok = [db executeUpdate:
                @"INSERT INTO im_conversation_local (owner_uid,conv_id,sort_order,is_group,name,avatar_url,member_count,peer,peer_nickname,peer_avatar_url,last_content,last_from,last_from_nickname,last_recalled,last_content_type,latest_conv_seq,read_seq,peer_read_seq,timestamp,unread,pinned_at,muted,marked_unread,server_snapshot_seq) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                owner, c.convID, @(idx), @(c.isGroup), c.name ?: @"", c.avatarURL ?: @"",
                @(c.memberCount), c.peer ?: @"", c.peerNickname ?: @"", c.peerAvatarURL ?: @"",
                c.lastContent ?: @"", c.lastFrom ?: @"", c.lastFromNickname ?: @"", @(c.lastRecalled),
                c.lastContentType ?: @"", @(c.latestConvSeq), @(c.readSeq), @(c.peerReadSeq),
                @(c.timestamp), @(c.unread), @(c.pinnedAt), @(c.muted), @(c.markedUnread), @(c.latestConvSeq)];
            if (!ok) {
                IMLogDatabase(@"写入会话缓存失败 owner=%@ conv=%@: %@", owner, c.convID, db.lastErrorMessage);
                *rollback = YES;
                *stop = YES;
            }
        }];
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
    NSString *owner = [self ownerUserID];
    [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        NSNumber *rowID = [self existingRowIDFor:message owner:owner in:db];
        BOOL inserted = rowID == nil;
        BOOL ok = NO;
        if (rowID) {
            ok = [db executeUpdate:
                @"UPDATE im_message_local SET server_msg_id=?,sender=?,recipient=?,content_type=?,content=?,conv_seq=?,timestamp=?,status=?,note=?,from_nickname=?,recalled_at=?,recalled_by=?,edited_at=?,pinned_at=?,reply_to_conv_seq=?,reply_snapshot=?,forward_from=?,group_id=?,poster=? WHERE row_id=?",
                message.serverMsgID ?: @"", message.from ?: @"", message.to ?: @"",
                message.contentType ?: @"text", message.content ?: @"",
                @(message.convSeq), @(message.timestamp), @(message.status), message.note ?: @"",
                message.fromNickname ?: @"", @(message.recalledAt), message.recalledBy ?: @"",
                @(message.editedAt), @(message.pinnedAt), @(message.replyToConvSeq), message.replySnapshot ?: @"", message.forwardFrom ?: @"", message.groupID ?: @"", message.poster ?: @"", rowID];
        } else {
            ok = [db executeUpdate:
                @"INSERT INTO im_message_local (owner_uid,client_msg_id,server_msg_id,conv_id,sender,recipient,content_type,content,conv_seq,timestamp,status,note,from_nickname,recalled_at,recalled_by,edited_at,pinned_at,reply_to_conv_seq,reply_snapshot,forward_from,group_id,poster) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                owner, message.clientMsgID ?: @"", message.serverMsgID ?: @"", message.convID,
                message.from ?: @"", message.to ?: @"", message.contentType ?: @"text",
                message.content ?: @"", @(message.convSeq), @(message.timestamp), @(message.status),
                message.note ?: @"", message.fromNickname ?: @"", @(message.recalledAt),
                message.recalledBy ?: @"", @(message.editedAt), @(message.pinnedAt),
                @(message.replyToConvSeq), message.replySnapshot ?: @"", message.forwardFrom ?: @"", message.groupID ?: @"", message.poster ?: @""];
        }
        if (!ok) {
            IMLogDatabase(@"保存消息失败 owner=%@ conv=%@: %@", owner, message.convID, db.lastErrorMessage);
            *rollback = YES;
            return;
        }
        if (![self updateConversationForMessage:message owner:owner inserted:inserted inDB:db]) {
            *rollback = YES;
        }
    }];
}

/// 消息与会话摘要必须在同一事务收敛，否则断网杀进程后会出现“消息还在、会话不见了”。
- (BOOL)updateConversationForMessage:(IMMessageModel *)message
                               owner:(NSString *)owner
                            inserted:(BOOL)inserted
                                inDB:(FMDatabase *)db {
    BOOL isGroup = [message.convID hasPrefix:@"g_"];
    BOOL isOutgoing = message.from.length > 0 && [message.from isEqualToString:owner];
    BOOL isIncoming = isGroup ? !isOutgoing : (message.from.length > 0 && !isOutgoing);
    NSString *peer = isOutgoing ? message.to : message.from;
    if (!isGroup && peer.length == 0) {
        NSString *prefix = [NSString stringWithFormat:@"u_%@_u_", owner];
        NSString *suffix = [NSString stringWithFormat:@"_u_%@", owner];
        if ([message.convID hasPrefix:prefix]) {
            peer = [message.convID substringFromIndex:prefix.length];
        } else if ([message.convID hasPrefix:@"u_"] && [message.convID hasSuffix:suffix]) {
            peer = [message.convID substringWithRange:NSMakeRange(2, message.convID.length - 2 - suffix.length)];
        }
    }

    FMResultSet *rs = [db executeQuery:
        @"SELECT latest_conv_seq,read_seq,timestamp,pinned_at,server_snapshot_seq FROM im_conversation_local WHERE owner_uid=? AND conv_id=? LIMIT 1",
        owner, message.convID];
    BOOL exists = rs && [rs next];
    int64_t latestSeq = exists ? [rs longLongIntForColumn:@"latest_conv_seq"] : 0;
    int64_t readSeq = exists ? [rs longLongIntForColumn:@"read_seq"] : 0;
    int64_t timestamp = exists ? [rs longLongIntForColumn:@"timestamp"] : 0;
    int64_t pinnedAt = exists ? [rs longLongIntForColumn:@"pinned_at"] : 0;
    int64_t snapshotSeq = exists ? [rs longLongIntForColumn:@"server_snapshot_seq"] : 0;
    [rs close];

    // 无法判断收发方向的历史测试/残缺数据不凭空制造错误会话；群系统消息可由 g_ 前缀可靠识别。
    if (!exists && !isGroup && peer.length == 0) { return YES; }

    BOOL isLatest = !exists || (message.convSeq > 0
        ? message.convSeq >= latestSeq
        : message.timestamp >= timestamp);
    BOOL isUnread = message.convSeq == 0 || message.convSeq > readSeq;
    BOOL representedByServerSnapshot = message.convSeq > 0 && message.convSeq <= snapshotSeq;
    NSInteger unreadDelta = inserted && isIncoming && isUnread && !representedByServerSnapshot ? 1 : 0;
    if (!exists) {
        BOOL ok = [db executeUpdate:
            @"INSERT INTO im_conversation_local (owner_uid,conv_id,sort_order,is_group,name,avatar_url,member_count,peer,peer_nickname,peer_avatar_url,last_content,last_from,last_from_nickname,last_recalled,last_content_type,latest_conv_seq,read_seq,peer_read_seq,timestamp,unread,pinned_at,muted,marked_unread,server_snapshot_seq) VALUES (?,?,0,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,0,0,0)",
            owner, message.convID, @(isGroup), isGroup ? @"群聊" : @"", @"", @0,
            isGroup ? @"" : (peer ?: @""), isGroup ? @"" : (peer ?: @""), @"",
            message.content ?: @"", message.from ?: @"", message.fromNickname ?: @"",
            @(message.recalledAt > 0), message.contentType ?: @"text", @(message.convSeq), @0, @0,
            @(message.timestamp), @(unreadDelta)];
        if (!ok) {
            IMLogDatabase(@"由消息创建会话缓存失败 owner=%@ conv=%@: %@", owner, message.convID, db.lastErrorMessage);
            return NO;
        }
    } else if (isLatest) {
        BOOL ok = [db executeUpdate:
            @"UPDATE im_conversation_local SET last_content=?,last_from=?,last_from_nickname=?,last_recalled=?,last_content_type=?,latest_conv_seq=MAX(latest_conv_seq,?),timestamp=MAX(timestamp,?),unread=MIN(999,unread+?) WHERE owner_uid=? AND conv_id=?",
            message.content ?: @"", message.from ?: @"", message.fromNickname ?: @"",
            @(message.recalledAt > 0), message.contentType ?: @"text", @(message.convSeq),
            @(message.timestamp), @(unreadDelta), owner, message.convID];
        if (!ok) {
            IMLogDatabase(@"更新会话摘要失败 owner=%@ conv=%@: %@", owner, message.convID, db.lastErrorMessage);
            return NO;
        }
    } else if (unreadDelta > 0) {
        if (![db executeUpdate:@"UPDATE im_conversation_local SET unread=MIN(999,unread+1) WHERE owner_uid=? AND conv_id=?",
              owner, message.convID]) {
            IMLogDatabase(@"更新会话未读数失败 owner=%@ conv=%@: %@", owner, message.convID, db.lastErrorMessage);
            return NO;
        }
    }

    // 消息活跃会话移到未置顶区首位；置顶会话保持服务端确定的置顶相对顺序。
    if (pinnedAt == 0 && inserted && isLatest) {
        if (![db executeUpdate:@"UPDATE im_conversation_local SET sort_order=sort_order+1 WHERE owner_uid=? AND pinned_at=0 AND conv_id<>?",
              owner, message.convID] ||
            ![db executeUpdate:@"UPDATE im_conversation_local SET sort_order=(SELECT COUNT(*) FROM im_conversation_local WHERE owner_uid=? AND pinned_at>0) WHERE owner_uid=? AND conv_id=?",
              owner, owner, message.convID]) {
            IMLogDatabase(@"更新会话排序失败 owner=%@ conv=%@: %@", owner, message.convID, db.lastErrorMessage);
            return NO;
        }
    }
    return YES;
}

- (void)markConversation:(NSString *)convID readUpToConvSeq:(int64_t)convSeq {
    if (convID.length == 0 || convSeq <= 0) { return; }
    NSString *owner = [self ownerUserID];
    [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT read_seq,unread FROM im_conversation_local WHERE owner_uid=? AND conv_id=? LIMIT 1", owner, convID];
        if (!rs || ![rs next]) {
            [rs close];
            return;
        }
        int64_t oldReadSeq = [rs longLongIntForColumn:@"read_seq"];
        NSInteger oldUnread = [rs longForColumn:@"unread"];
        [rs close];
        if (convSeq <= oldReadSeq) { return; }

        FMResultSet *countRS = [db executeQuery:
            @"SELECT COUNT(*) AS n FROM im_message_local WHERE owner_uid=? AND conv_id=? AND conv_seq>? AND conv_seq<=? AND sender<>?",
            owner, convID, @(oldReadSeq), @(convSeq), owner];
        NSInteger newlyRead = [countRS next] ? [countRS longForColumn:@"n"] : 0;
        [countRS close];
        BOOL ok = [db executeUpdate:
            @"UPDATE im_conversation_local SET read_seq=?,unread=? WHERE owner_uid=? AND conv_id=?",
            @(convSeq), @(MAX(0, oldUnread - newlyRead)), owner, convID];
        if (!ok) {
            IMLogDatabase(@"更新本地会话已读失败 owner=%@ conv=%@: %@", owner, convID, db.lastErrorMessage);
            *rollback = YES;
        }
    }];
}

- (void)markConversation:(NSString *)convID peerReadUpToConvSeq:(int64_t)convSeq {
    if (convID.length == 0 || convSeq <= 0) { return; }
    NSString *owner = [self ownerUserID];
    [_queue inDatabase:^(FMDatabase *db) {
        if (![db executeUpdate:
              @"UPDATE im_conversation_local SET peer_read_seq=MAX(peer_read_seq,?) WHERE owner_uid=? AND conv_id=?",
              @(convSeq), owner, convID]) {
            IMLogDatabase(@"更新本地对端已读失败 owner=%@ conv=%@: %@", owner, convID, db.lastErrorMessage);
        }
    }];
}

- (void)markConversationFullyRead:(NSString *)convID upToConvSeq:(int64_t)convSeq {
    if (convID.length == 0 || convSeq <= 0) { return; }
    NSString *owner = [self ownerUserID];
    [_queue inDatabase:^(FMDatabase *db) {
        if (![db executeUpdate:
              @"UPDATE im_conversation_local SET read_seq=MAX(read_seq,?),unread=0 WHERE owner_uid=? AND conv_id=?",
              @(convSeq), owner, convID]) {
            IMLogDatabase(@"清零本地会话未读失败 owner=%@ conv=%@: %@", owner, convID, db.lastErrorMessage);
        }
    }];
}

- (void)applyCachedSettingsForConversation:(NSString *)convID
                                  pinnedAt:(int64_t)pinnedAt
                                     muted:(BOOL)muted
                              markedUnread:(BOOL)markedUnread {
    if (convID.length == 0) { return; }
    NSString *owner = [self ownerUserID];
    [_queue inDatabase:^(FMDatabase *db) {
        if (![db executeUpdate:
              @"UPDATE im_conversation_local SET pinned_at=?,muted=?,marked_unread=? WHERE owner_uid=? AND conv_id=?",
              @(pinnedAt), @(muted), @(markedUnread), owner, convID]) {
            IMLogDatabase(@"更新本地会话设置失败 owner=%@ conv=%@: %@", owner, convID, db.lastErrorMessage);
        }
    }];
}

- (void)deleteCachedConversation:(NSString *)convID {
    if (convID.length == 0) { return; }
    NSString *owner = [self ownerUserID];
    [_queue inDatabase:^(FMDatabase *db) {
        if (![db executeUpdate:@"DELETE FROM im_conversation_local WHERE owner_uid=? AND conv_id=?", owner, convID]) {
            IMLogDatabase(@"删除本地会话摘要失败 owner=%@ conv=%@: %@", owner, convID, db.lastErrorMessage);
        }
    }];
}

/// 出站消息按 (conv_id, client_msg_id) 匹配；入站（无 client_msg_id）按 (conv_id, conv_seq) 匹配。
- (NSNumber *)existingRowIDFor:(IMMessageModel *)message owner:(NSString *)owner in:(FMDatabase *)db {
    FMResultSet *rs = nil;
    if (message.clientMsgID.length > 0) {
        rs = [db executeQuery:@"SELECT row_id FROM im_message_local WHERE owner_uid=? AND conv_id=? AND client_msg_id=? LIMIT 1",
              owner, message.convID, message.clientMsgID];
    } else if (message.convSeq > 0) {
        rs = [db executeQuery:@"SELECT row_id FROM im_message_local WHERE owner_uid=? AND conv_id=? AND (client_msg_id IS NULL OR client_msg_id='') AND conv_seq=? LIMIT 1",
              owner, message.convID, @(message.convSeq)];
    }
    NSNumber *rowID = nil;
    if (rs && [rs next]) { rowID = @([rs longLongIntForColumn:@"row_id"]); }
    [rs close];
    return rowID;
}

- (NSArray<IMMessageModel *> *)messagesForConv:(NSString *)convID {
    NSString *owner = [self ownerUserID];
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray array];
    [_queue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT * FROM im_message_local WHERE owner_uid=? AND conv_id=? ORDER BY row_id ASC", owner, convID];
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
            NSString *gid = [rs stringForColumn:@"group_id"];
            m.groupID = gid.length > 0 ? gid : nil;
            NSString *poster = [rs stringForColumn:@"poster"];
            m.poster = poster.length > 0 ? poster : nil;
            [out addObject:m];
        }
        [rs close];
    }];
    return out;
}

- (void)deleteMessage:(IMMessageModel *)message {
    if (message.convID.length == 0) { return; }
    NSString *owner = [self ownerUserID];
    [_queue inDatabase:^(FMDatabase *db) {
        NSNumber *rowID = [self existingRowIDFor:message owner:owner in:db];
        if (rowID) {
            [db executeUpdate:@"DELETE FROM im_message_local WHERE row_id=?", rowID];
        }
    }];
}

- (NSInteger)clearMessagesForConv:(NSString *)convID {
    if (convID.length == 0) { return 0; }
    NSString *owner = [self ownerUserID];
    __block NSInteger removed = 0;
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db executeUpdate:@"DELETE FROM im_message_local WHERE owner_uid=? AND conv_id=?", owner, convID]) {
            removed = (NSInteger)db.changes;
        }
    }];
    return removed;
}

- (int64_t)maxConvSeqForConv:(NSString *)convID {
    NSString *owner = [self ownerUserID];
    __block int64_t maxSeq = 0;
    [_queue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT MAX(conv_seq) AS m FROM im_message_local WHERE owner_uid=? AND conv_id=?", owner, convID];
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
    NSString *owner = [self ownerUserID];
    [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        NSMutableArray *sets = [NSMutableArray array];
        NSMutableArray *args = [NSMutableArray array];
        if (recalledAt > 0) { [sets addObject:@"recalled_at=?"]; [args addObject:@(recalledAt)];
                              [sets addObject:@"recalled_by=?"]; [args addObject:recalledBy ?: @""]; }
        if (editedAt > 0)   { [sets addObject:@"edited_at=?"];   [args addObject:@(editedAt)]; }
        if (pinnedAt > 0)   { [sets addObject:@"pinned_at=?"];   [args addObject:@(pinnedAt)]; }
        if (newContent != nil) { [sets addObject:@"content=?"]; [args addObject:newContent]; }
        if (sets.count == 0) { return; }
        NSString *sql = [NSString stringWithFormat:@"UPDATE im_message_local SET %@ WHERE owner_uid=? AND conv_id=? AND conv_seq=?",
                         [sets componentsJoinedByString:@","]];
        [args addObject:owner];
        [args addObject:convID];
        [args addObject:@(targetConvSeq)];
        if (![db executeUpdate:sql withArgumentsInArray:args]) {
            IMLogDatabase(@"应用本地消息操作失败 owner=%@ conv=%@: %@", owner, convID, db.lastErrorMessage);
            *rollback = YES;
            return;
        }
        if (recalledAt > 0) {
            if (![db executeUpdate:
                  @"UPDATE im_conversation_local SET last_recalled=1 WHERE owner_uid=? AND conv_id=? AND latest_conv_seq=?",
                  owner, convID, @(targetConvSeq)]) {
                *rollback = YES;
            }
        }
        if (newContent != nil) {
            if (![db executeUpdate:
                  @"UPDATE im_conversation_local SET last_content=? WHERE owner_uid=? AND conv_id=? AND latest_conv_seq=?",
                  newContent, owner, convID, @(targetConvSeq)]) {
                *rollback = YES;
            }
        }
    }];
}

@end
