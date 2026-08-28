//  IMDatabase.m
//  FMDB + SQLite 实现（线程安全用 FMDatabaseQueue）。接口见 IMDatabase.h，上层无感。

#import "IMDatabase.h"
#import "IMConversation.h"
#import "IMMessageModel.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"
#import "IMLog.h"
#import "IMRemarkStore.h"

#import <FMDB/FMDB.h>

@interface IMDatabase ()

- (BOOL)updateConversationForMessage:(IMMessageModel *)message
                               owner:(NSString *)owner
                            inserted:(BOOL)inserted
                                inDB:(FMDatabase *)db;
- (void)writeCachedConversations:(NSArray<IMConversation *> *)conversations;
+ (IMMessageModel *)messageFromResultSet:(FMResultSet *)rs;   // 行→模型唯一映射（列清单第③处）
+ (NSString *)escapeLikePattern:(NSString *)raw;              // LIKE 通配符转义（镜像后端 escapeLike）

@end

@interface IMDatabaseAccountContext ()
@property (nonatomic, copy, readwrite) NSString *ownerUserID;
@property (nonatomic, copy) NSString *databaseIdentifier;
@property (nonatomic, assign) NSUInteger generation;
- (instancetype)initWithOwnerUserID:(NSString *)ownerUserID
                  databaseIdentifier:(NSString *)databaseIdentifier
                          generation:(NSUInteger)generation;
@end

@implementation IMDatabaseAccountContext

- (instancetype)initWithOwnerUserID:(NSString *)ownerUserID
                  databaseIdentifier:(NSString *)databaseIdentifier
                          generation:(NSUInteger)generation {
    self = [super init];
    if (self) {
        _ownerUserID = [ownerUserID copy];
        _databaseIdentifier = [databaseIdentifier copy];
        _generation = generation;
    }
    return self;
}

@end

@implementation IMDatabase {
    FMDatabaseQueue *_queue;
    NSString *_ownerUserID;
    NSString *_databaseIdentifier;
    NSUInteger _accountGeneration;
    IMDatabaseAccountContext *_accountContext;
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
        _databaseIdentifier = NSUUID.UUID.UUIDString;
        _queue = [FMDatabaseQueue databaseQueueWithPath:fileURL.path];
        [self createTables];
    }
    return self;
}

/// im_message_local 的**唯一列清单**（row_id 主键除外，按建表顺序）。建表语句与老库迁移
/// **都从这里生成**，从结构上杜绝历史事故：CREATE 加了列却漏加进迁移表 → 老库缺列 →
/// 每条 INSERT 报 "no column named ..." → 消息落库全失败、同步游标永不推进、客户端热循环
/// 重拉同一页（file_name 曾如此，真机日志 13s 内 2.2 万条失败）。
/// **今后新增字段共四处**：① 这里加一行（建表/迁移/INSERT 列序即全就位）② insertRowForMessage
/// 加值映射（缺了 NSAssert 现形）③ messagesForConv 的 SELECT 映射 ④ IMDatabaseSchemaTests
/// 的 fullyPopulated/assert 各补一行（③ 漏改由 ④ 的回环断言抓出）。
/// 注：ALTER ADD COLUMN 不能加"NOT NULL 无默认"列；conv_id 属最初建表列、任何真实库都已存在，
/// 其迁移分支永不触发，故保留 NOT NULL 无碍。owner_uid 用 DEFAULT '' 兜底，可安全 ADD。
+ (NSArray<NSArray<NSString *> *> *)messageColumns {
    return @[
        @[@"owner_uid",        @"TEXT NOT NULL DEFAULT ''"],
        @[@"client_msg_id",    @"TEXT"],
        @[@"server_msg_id",    @"TEXT"],
        @[@"conv_id",          @"TEXT NOT NULL"],
        @[@"sender",           @"TEXT"],
        @[@"recipient",        @"TEXT"],
        @[@"content_type",     @"TEXT"],
        @[@"content",          @"TEXT"],
        @[@"file_name",        @"TEXT"],                    // 文件消息原始文件名（曾漏迁移，见上）
        @[@"file_size",        @"INTEGER NOT NULL DEFAULT 0"], // 文件/媒体原始字节数
        @[@"caption",          @"TEXT"],                    // 图文/视频文/文件文随附文本（Telegram 图说模型）
        @[@"mentions",         @"TEXT"],                    // M4-8 被 @ 成员 uid（JSON 数组）：转发重发 mentions 用（强提醒）
        @[@"mention_all",      @"INTEGER NOT NULL DEFAULT 0"], // M4-8 @所有人
        @[@"sys_segments",     @"TEXT"],                    // 系统消息结构化分段（JSON）：名字换本地显示名 + 可点
        @[@"conv_seq",         @"INTEGER"],
        @[@"timestamp",        @"INTEGER"],
        @[@"status",           @"INTEGER"],
        @[@"note",             @"TEXT"],                    // 失败消息的系统提示（如被拉黑拒收文案）
        @[@"from_nickname",    @"TEXT"],                    // 群消息发送者昵称（M3，重进群聊气泡仍显昵称）
        @[@"recalled_at",      @"INTEGER"],                 // M4 撤回/编辑/置顶派生状态
        @[@"recalled_by",      @"TEXT"],
        @[@"edited_at",        @"INTEGER"],
        @[@"pinned_at",        @"INTEGER"],
        @[@"reply_to_conv_seq",@"INTEGER"],                 // M4-2 引用回复
        @[@"reply_snapshot",   @"TEXT"],
        @[@"reply_to_from",    @"TEXT"],                    // M4-x 被引用者 uid（群聊引用条显示发送者）
        @[@"forward_from",     @"TEXT"],                    // M4-3 转发溯源
        @[@"group_id",         @"TEXT"],                    // M4+ 相册分组（同批多图/视频聚簇渲染宫格）
        @[@"poster",           @"TEXT"],                    // M4+ 视频封面首帧 URL
        @[@"media_w",          @"INTEGER NOT NULL DEFAULT 0"], // M4+ 媒体像素宽（按原比例渲染气泡）
        @[@"media_h",          @"INTEGER NOT NULL DEFAULT 0"], // M4+ 媒体像素高
        @[@"duration",         @"INTEGER NOT NULL DEFAULT 0"], // M4+ 视频时长（毫秒，封面左上角角标）
        @[@"thumb",            @"TEXT"],                    // M4-7 极小模糊预览（~20px JPEG 的 data URI）
        @[@"waveform",         @"TEXT"],                    // voice 振幅指纹（base64≤160 rune，P0）：收端画气泡波形免下载音频
        @[@"from_role",        @"TEXT"],                    // 群主/管理员气泡徽标兜底（owner/admin 冗余下发）
    ];
}

- (void)createTables {
    [_queue inDatabase:^(FMDatabase *db) {
        // im_message_local：建表 + 老库迁移**同源**于 +messageColumns（见其注释：防列清单漂移事故）。
        NSMutableString *msgCols = [NSMutableString stringWithString:@"row_id INTEGER PRIMARY KEY AUTOINCREMENT"];
        for (NSArray<NSString *> *c in [IMDatabase messageColumns]) { [msgCols appendFormat:@", %@ %@", c[0], c[1]]; }
        if (![db executeUpdate:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS im_message_local (%@)", msgCols]]) {
            IMLogDatabase(@"建表失败: %@", db.lastErrorMessage);
        }
        // 老库迁移（非破坏）：逐列缺则补，ADD COLUMN 幂等；与建表同一份清单，永不漂移。
        // ALTER 失败必须落日志（CODING_STYLE §5）：列缺失=后续每条 INSERT 全败、同步卡死
        //（file_name 事故形态），迁移期的这行日志是唯一能定位根因的线索。
        for (NSArray<NSString *> *c in [IMDatabase messageColumns]) {
            if (![self column:c[0] existsInTable:@"im_message_local" db:db]) {
                if (![db executeUpdate:[NSString stringWithFormat:@"ALTER TABLE im_message_local ADD COLUMN %@ %@", c[0], c[1]]]) {
                    IMLogDatabase(@"迁移失败：im_message_local 补列 %@ 未成功: %@", c[0], db.lastErrorMessage);
                }
            }
        }
        [db executeUpdate:@"CREATE INDEX IF NOT EXISTS idx_local_owner_conv ON im_message_local(owner_uid,conv_id)"];

        BOOL ok = [db executeUpdate:
            @"CREATE TABLE IF NOT EXISTS im_sent_file_local ("
             "owner_uid TEXT NOT NULL, server_msg_id TEXT NOT NULL, url TEXT NOT NULL,"
             "name TEXT NOT NULL, size INTEGER NOT NULL DEFAULT 0, timestamp INTEGER NOT NULL,"
             "PRIMARY KEY(owner_uid,url))"];
        if (!ok) { IMLogDatabase(@"创建已发送文件缓存失败: %@", db.lastErrorMessage); }
        [db executeUpdate:@"CREATE INDEX IF NOT EXISTS idx_sent_file_owner_time ON im_sent_file_local(owner_uid,timestamp DESC)"];
        if (![self column:@"size" existsInTable:@"im_sent_file_local" db:db]) {
            if (![db executeUpdate:@"ALTER TABLE im_sent_file_local ADD COLUMN size INTEGER NOT NULL DEFAULT 0"]) {
                IMLogDatabase(@"迁移失败：im_sent_file_local 补列 size 未成功: %@", db.lastErrorMessage);
            }
        }

        ok = [db executeUpdate:
            @"CREATE TABLE IF NOT EXISTS im_conversation_local ("
             "owner_uid TEXT NOT NULL, conv_id TEXT NOT NULL, sort_order INTEGER NOT NULL,"
             "is_group INTEGER, name TEXT, avatar_url TEXT, member_count INTEGER,"
             "peer TEXT, peer_nickname TEXT, peer_avatar_url TEXT, peer_remark TEXT NOT NULL DEFAULT '',"
             "last_content TEXT, last_from TEXT, last_from_nickname TEXT,"
             "last_recalled INTEGER, last_content_type TEXT, last_caption TEXT NOT NULL DEFAULT '', latest_conv_seq INTEGER,"
             "read_seq INTEGER, peer_read_seq INTEGER, timestamp INTEGER, unread INTEGER,"
             "pinned_at INTEGER, muted INTEGER, marked_unread INTEGER,server_snapshot_seq INTEGER NOT NULL DEFAULT 0,"
             "synced_conv_seq INTEGER NOT NULL DEFAULT 0, remark TEXT NOT NULL DEFAULT '',"
             "mention_unread INTEGER NOT NULL DEFAULT 0,"
             "PRIMARY KEY(owner_uid,conv_id))"];
        if (!ok) { IMLogDatabase(@"会话缓存建表失败: %@", db.lastErrorMessage); }
        if (![self column:@"server_snapshot_seq" existsInTable:@"im_conversation_local" db:db]) {
            [db executeUpdate:@"ALTER TABLE im_conversation_local ADD COLUMN server_snapshot_seq INTEGER NOT NULL DEFAULT 0"];
        }
        // 连续同步位置是独立状态；0 表示尚未证明任何连续区间，必须从头确认，不能由本地 MAX(conv_seq) 推断。
        if (![self column:@"synced_conv_seq" existsInTable:@"im_conversation_local" db:db]) {
            [db executeUpdate:@"ALTER TABLE im_conversation_local ADD COLUMN synced_conv_seq INTEGER NOT NULL DEFAULT 0"];
        }
        // 会话备注（G1，仅本人可见、多端同步）；缓存持久化，避免消息风暴触发的本地刷新把备注名闪成真实群名。
        if (![self column:@"remark" existsInTable:@"im_conversation_local" db:db]) {
            if (![db executeUpdate:@"ALTER TABLE im_conversation_local ADD COLUMN remark TEXT NOT NULL DEFAULT ''"]) {
                IMLogDatabase(@"迁移失败：im_conversation_local 补列 remark 未成功: %@", db.lastErrorMessage);
            }
        }
        // 好友备注名（仅本人可见、多端同步）：单聊显示名靠它，必须持久化——否则冷启动首屏
        // （本地快路）先显真实昵称、等 HTTP 权威列表回来才跳成备注，肉眼可见闪一下。
        if (![self column:@"peer_remark" existsInTable:@"im_conversation_local" db:db]) {
            if (![db executeUpdate:@"ALTER TABLE im_conversation_local ADD COLUMN peer_remark TEXT NOT NULL DEFAULT ''"]) {
                IMLogDatabase(@"迁移失败：im_conversation_local 补列 peer_remark 未成功: %@", db.lastErrorMessage);
            }
        }
        // 图说 caption（Telegram 模型）：会话列表预览「有字显字」；老库补列，缺则回退 [图片] 等。
        if (![self column:@"last_caption" existsInTable:@"im_conversation_local" db:db]) {
            if (![db executeUpdate:@"ALTER TABLE im_conversation_local ADD COLUMN last_caption TEXT NOT NULL DEFAULT ''"]) {
                IMLogDatabase(@"迁移失败：im_conversation_local 补列 last_caption 未成功: %@", db.lastErrorMessage);
            }
        }
        // 群「@我」未读（M4-8）：必须持久化，否则 HTTP 权威列表（带 mention_unread）与本地快路
        // （cachedConversations 恒 NO）对同一行的「[有人@我]」前缀渲染相反，消息/刷新风暴下肉眼即闪。
        if (![self column:@"mention_unread" existsInTable:@"im_conversation_local" db:db]) {
            if (![db executeUpdate:@"ALTER TABLE im_conversation_local ADD COLUMN mention_unread INTEGER NOT NULL DEFAULT 0"]) {
                IMLogDatabase(@"迁移失败：im_conversation_local 补列 mention_unread 未成功: %@", db.lastErrorMessage);
            }
        }

        // 任务5：好友/群组本地快照（断网离线首屏）。仅缓存列表渲染所需字段，按 owner_uid 隔离。
        ok = [db executeUpdate:
            @"CREATE TABLE IF NOT EXISTS im_friend_local ("
             "owner_uid TEXT NOT NULL, user_id TEXT NOT NULL, sort_order INTEGER NOT NULL,"
             "nickname TEXT, avatar_url TEXT, status INTEGER, blocked INTEGER, updated_at INTEGER,"
             "remark TEXT NOT NULL DEFAULT '',"
             "PRIMARY KEY(owner_uid,user_id))"];
        if (!ok) { IMLogDatabase(@"好友缓存建表失败: %@", db.lastErrorMessage); }
        // 好友备注名：通讯录离线首屏也要按备注排/显，故随好友快照一起落地（老库补列）。
        if (![self column:@"remark" existsInTable:@"im_friend_local" db:db]) {
            if (![db executeUpdate:@"ALTER TABLE im_friend_local ADD COLUMN remark TEXT NOT NULL DEFAULT ''"]) {
                IMLogDatabase(@"迁移失败：im_friend_local 补列 remark 未成功: %@", db.lastErrorMessage);
            }
        }
        ok = [db executeUpdate:
            @"CREATE TABLE IF NOT EXISTS im_group_local ("
             "owner_uid TEXT NOT NULL, conv_id TEXT NOT NULL, sort_order INTEGER NOT NULL,"
             "name TEXT, avatar_url TEXT, owner TEXT, created_at INTEGER, my_role INTEGER,"
             "PRIMARY KEY(owner_uid,conv_id))"];
        if (!ok) { IMLogDatabase(@"群组缓存建表失败: %@", db.lastErrorMessage); }
    }];
}

- (nullable IMDatabaseAccountContext *)useOwnerUserID:(NSString *)userID {
    NSString *owner = [userID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (owner.length == 0) {
        IMLogDatabase(@"拒绝切换到空 owner_uid，继续使用当前账号命名空间");
        return nil;
    }
    @synchronized (self) {
        _ownerUserID = [owner copy];
        _accountGeneration++;
        _accountContext = [[IMDatabaseAccountContext alloc] initWithOwnerUserID:_ownerUserID
                                                             databaseIdentifier:_databaseIdentifier
                                                                     generation:_accountGeneration];
        return _accountContext;
    }
}

- (nullable IMDatabaseAccountContext *)currentAccountContext {
    @synchronized (self) {
        return _accountContext;
    }
}

- (BOOL)performWithAccountContext:(IMDatabaseAccountContext *)context
                            block:(void (^)(IMDatabase *database))block {
    if (!context || !block) { return NO; }
    @synchronized (self) {
        BOOL current = [_databaseIdentifier isEqualToString:context.databaseIdentifier]
            && _accountGeneration == context.generation
            && [_ownerUserID isEqualToString:context.ownerUserID];
        if (!current) {
            IMLogDatabase(@"丢弃失效账号上下文的数据库操作 owner=%@ generation=%lu",
                          context.ownerUserID, (unsigned long)context.generation);
            return NO;
        }
        block(self);
        return YES;
    }
}

- (NSString *)ownerUserID {
    @synchronized (self) {
        return _ownerUserID ?: @"__default__";
    }
}

#pragma mark - 会话缓存

- (NSArray<NSDictionary *> *)cachedSentFiles {
    NSString *owner = [self ownerUserID];
    NSMutableArray<NSDictionary *> *files = [NSMutableArray array];
    [_queue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT server_msg_id,url,name,size,timestamp FROM im_sent_file_local WHERE owner_uid=? ORDER BY timestamp DESC,server_msg_id DESC",
            owner];
        while ([rs next]) {
            [files addObject:@{
                @"server_msg_id": [rs stringForColumn:@"server_msg_id"] ?: @"",
                @"url": [rs stringForColumn:@"url"] ?: @"",
                @"name": [rs stringForColumn:@"name"] ?: @"",
                @"size": @([rs longLongIntForColumn:@"size"]),
                @"timestamp": @([rs longLongIntForColumn:@"timestamp"]),
            }];
        }
        [rs close];
    }];
    return files;
}

- (void)cacheSentFiles:(NSArray<NSDictionary *> *)files {
    if (files.count == 0) { return; }
    NSString *owner = [self ownerUserID];
    [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        for (NSDictionary *file in files) {
            NSString *serverID = [file[@"server_msg_id"] isKindOfClass:NSString.class] ? file[@"server_msg_id"] : @"";
            NSString *url = [file[@"url"] isKindOfClass:NSString.class] ? file[@"url"] : @"";
            NSString *name = [file[@"name"] isKindOfClass:NSString.class] ? file[@"name"] : @"";
            if (serverID.length == 0 || url.length == 0 || name.length == 0) { continue; }
            BOOL ok = [db executeUpdate:
                @"INSERT INTO im_sent_file_local(owner_uid,server_msg_id,url,name,size,timestamp) VALUES(?,?,?,?,?,?) "
                 "ON CONFLICT(owner_uid,url) DO UPDATE SET server_msg_id=excluded.server_msg_id,name=excluded.name,size=excluded.size,timestamp=excluded.timestamp",
                owner, serverID, url, name, @([file[@"size"] longLongValue]), @([file[@"timestamp"] longLongValue])];
            if (!ok) {
                IMLogDatabase(@"缓存已发送文件失败 owner=%@: %@", owner, db.lastErrorMessage);
                *rollback = YES;
                return;
            }
        }
    }];
}

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
            c.peerRemark = [rs stringForColumn:@"peer_remark"];
            c.peerAvatarURL = [rs stringForColumn:@"peer_avatar_url"];
            c.lastContent = [rs stringForColumn:@"last_content"];
            c.lastFrom = [rs stringForColumn:@"last_from"];
            c.lastFromNickname = [rs stringForColumn:@"last_from_nickname"];
            c.lastRecalled = [rs boolForColumn:@"last_recalled"];
            c.lastContentType = [rs stringForColumn:@"last_content_type"];
            c.lastCaption = [rs stringForColumn:@"last_caption"];
            c.latestConvSeq = [rs longLongIntForColumn:@"latest_conv_seq"];
            c.readSeq = [rs longLongIntForColumn:@"read_seq"];
            c.peerReadSeq = [rs longLongIntForColumn:@"peer_read_seq"];
            c.timestamp = [rs longLongIntForColumn:@"timestamp"];
            c.unread = [rs longForColumn:@"unread"];
            c.pinnedAt = [rs longLongIntForColumn:@"pinned_at"];
            c.muted = [rs boolForColumn:@"muted"];
            c.markedUnread = [rs boolForColumn:@"marked_unread"];
            c.mentionUnread = [rs boolForColumn:@"mention_unread"];
            NSString *rmk = [rs stringForColumn:@"remark"];
            c.remark = rmk.length > 0 ? rmk : nil; // 空串视作无备注
            if (c.convID.length > 0) { [out addObject:c]; }
        }
        [rs close];
    }];
    // 冷启动/离线首屏的显示名也走全局缓存（同 HTTP 路径）；会话行只覆盖有会话的对端，非全集。
    [IMRemarkStore.sharedStore ingestConversations:out];
    return out;
}

- (void)replaceCachedConversations:(NSArray<IMConversation *> *)conversations {
    [self writeCachedConversations:conversations];
}

- (void)writeCachedConversations:(NSArray<IMConversation *> *)conversations {
    NSString *owner = [self ownerUserID];
    [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        // HTTP 会话快照只描述列表状态，不能抹掉 WebSocket 已连续同步到的位置。
        NSMutableDictionary<NSString *, NSNumber *> *syncCursors = [NSMutableDictionary dictionary];
        FMResultSet *cursorRS = [db executeQuery:
            @"SELECT conv_id,synced_conv_seq FROM im_conversation_local WHERE owner_uid=?", owner];
        while ([cursorRS next]) {
            NSString *convID = [cursorRS stringForColumn:@"conv_id"] ?: @"";
            if (convID.length > 0) {
                syncCursors[convID] = @([cursorRS longLongIntForColumn:@"synced_conv_seq"]);
            }
        }
        [cursorRS close];
        if (![db executeUpdate:@"DELETE FROM im_conversation_local WHERE owner_uid=?", owner]) {
            IMLogDatabase(@"清理旧会话缓存失败 owner=%@: %@", owner, db.lastErrorMessage);
            *rollback = YES;
            return;
        }
        [conversations enumerateObjectsUsingBlock:^(IMConversation *c, NSUInteger idx, BOOL *stop) {
            if (c.convID.length == 0) { return; }
            BOOL ok = [db executeUpdate:
                @"INSERT INTO im_conversation_local (owner_uid,conv_id,sort_order,is_group,name,avatar_url,member_count,peer,peer_nickname,peer_avatar_url,peer_remark,last_content,last_from,last_from_nickname,last_recalled,last_content_type,last_caption,latest_conv_seq,read_seq,peer_read_seq,timestamp,unread,pinned_at,muted,marked_unread,server_snapshot_seq,synced_conv_seq,remark,mention_unread) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                owner, c.convID, @(idx), @(c.isGroup), c.name ?: @"", c.avatarURL ?: @"",
                @(c.memberCount), c.peer ?: @"", c.peerNickname ?: @"", c.peerAvatarURL ?: @"", c.peerRemark ?: @"",
                c.lastContent ?: @"", c.lastFrom ?: @"", c.lastFromNickname ?: @"", @(c.lastRecalled),
                c.lastContentType ?: @"", c.lastCaption ?: @"", @(c.latestConvSeq), @(c.readSeq), @(c.peerReadSeq),
                @(c.timestamp), @(c.unread), @(c.pinnedAt), @(c.muted), @(c.markedUnread), @(c.latestConvSeq),
                syncCursors[c.convID] ?: @0, c.remark ?: @"", @(c.mentionUnread)];
            if (!ok) {
                IMLogDatabase(@"写入会话缓存失败 owner=%@ conv=%@: %@", owner, c.convID, db.lastErrorMessage);
                *rollback = YES;
                *stop = YES;
            }
        }];
    }];
}

#pragma mark - 好友 / 群组缓存（任务5·断网离线首屏）

- (NSArray<IMUserCard *> *)cachedFriends {
    NSString *owner = [self ownerUserID];
    NSMutableArray<IMUserCard *> *out = [NSMutableArray array];
    [_queue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT * FROM im_friend_local WHERE owner_uid=? ORDER BY sort_order ASC", owner];
        if (!rs) { IMLogDatabase(@"读取好友缓存失败 owner=%@: %@", owner, db.lastErrorMessage); return; }
        while ([rs next]) {
            IMUserCard *c = [IMUserCard new];
            c.userID = [rs stringForColumn:@"user_id"] ?: @"";
            c.nickname = [rs stringForColumn:@"nickname"] ?: @"";
            c.remark = [rs stringForColumn:@"remark"] ?: @"";
            c.avatarURL = [rs stringForColumn:@"avatar_url"] ?: @"";
            c.status = (IMFriendStatus)[rs longForColumn:@"status"];
            c.blocked = [rs boolForColumn:@"blocked"];
            c.updatedAt = [rs longLongIntForColumn:@"updated_at"];
            if (c.userID.length > 0) { [out addObject:c]; }
        }
        [rs close];
    }];
    // 冷启动/离线首屏也要有备注名：本地好友快照是全集，直接喂给全局显示名缓存。
    [IMRemarkStore.sharedStore ingestFriends:out authoritative:YES];
    return out;
}

- (void)replaceCachedFriends:(NSArray<IMUserCard *> *)friends {
    NSString *owner = [self ownerUserID];
    [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if (![db executeUpdate:@"DELETE FROM im_friend_local WHERE owner_uid=?", owner]) {
            IMLogDatabase(@"清理旧好友缓存失败 owner=%@: %@", owner, db.lastErrorMessage);
            *rollback = YES; return;
        }
        [friends enumerateObjectsUsingBlock:^(IMUserCard *c, NSUInteger idx, BOOL *stop) {
            if (c.userID.length == 0) { return; }
            BOOL ok = [db executeUpdate:
                @"INSERT INTO im_friend_local (owner_uid,user_id,sort_order,nickname,avatar_url,status,blocked,updated_at,remark) VALUES (?,?,?,?,?,?,?,?,?)",
                owner, c.userID, @(idx), c.nickname ?: @"", c.avatarURL ?: @"",
                @(c.status), @(c.blocked), @(c.updatedAt), c.remark ?: @""];
            if (!ok) {
                IMLogDatabase(@"写入好友缓存失败 owner=%@ uid=%@: %@", owner, c.userID, db.lastErrorMessage);
                *rollback = YES; *stop = YES;
            }
        }];
    }];
}

- (NSArray<IMGroupInfo *> *)cachedGroups {
    NSString *owner = [self ownerUserID];
    NSMutableArray<IMGroupInfo *> *out = [NSMutableArray array];
    [_queue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT * FROM im_group_local WHERE owner_uid=? ORDER BY sort_order ASC", owner];
        if (!rs) { IMLogDatabase(@"读取群组缓存失败 owner=%@: %@", owner, db.lastErrorMessage); return; }
        while ([rs next]) {
            IMGroupInfo *g = [IMGroupInfo new];
            g.convID = [rs stringForColumn:@"conv_id"] ?: @"";
            g.name = [rs stringForColumn:@"name"] ?: @"";
            g.avatarURL = [rs stringForColumn:@"avatar_url"] ?: @"";
            g.owner = [rs stringForColumn:@"owner"] ?: @"";
            g.createdAt = [rs longLongIntForColumn:@"created_at"];
            g.myRole = (IMGroupRole)[rs longForColumn:@"my_role"];
            g.members = @[]; // 列表不需要成员详情；进群聊详情时再联网权威拉取
            if (g.convID.length > 0) { [out addObject:g]; }
        }
        [rs close];
    }];
    return out;
}

- (void)replaceCachedGroups:(NSArray<IMGroupInfo *> *)groups {
    NSString *owner = [self ownerUserID];
    [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if (![db executeUpdate:@"DELETE FROM im_group_local WHERE owner_uid=?", owner]) {
            IMLogDatabase(@"清理旧群组缓存失败 owner=%@: %@", owner, db.lastErrorMessage);
            *rollback = YES; return;
        }
        [groups enumerateObjectsUsingBlock:^(IMGroupInfo *g, NSUInteger idx, BOOL *stop) {
            if (g.convID.length == 0) { return; }
            BOOL ok = [db executeUpdate:
                @"INSERT INTO im_group_local (owner_uid,conv_id,sort_order,name,avatar_url,owner,created_at,my_role) VALUES (?,?,?,?,?,?,?,?)",
                owner, g.convID, @(idx), g.name ?: @"", g.avatarURL ?: @"", g.owner ?: @"",
                @(g.createdAt), @(g.myRole)];
            if (!ok) {
                IMLogDatabase(@"写入群组缓存失败 owner=%@ conv=%@: %@", owner, g.convID, db.lastErrorMessage);
                *rollback = YES; *stop = YES;
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
    [self saveIncomingMessage:message advancingSyncedConvSeq:0];
}

/// INSERT 用的 列名→值 映射，键与 +messageColumns 逐一对应（差一列即 NSAssert 现形）。
/// **新增字段：messageColumns 加一行 + 这里加一行**，建表/迁移/INSERT 三处即全部就位。
- (NSDictionary<NSString *, id> *)insertRowForMessage:(IMMessageModel *)message owner:(NSString *)owner {
    return @{
        @"owner_uid":         owner,
        @"client_msg_id":     message.clientMsgID ?: @"",
        @"server_msg_id":     message.serverMsgID ?: @"",
        @"conv_id":           message.convID,
        @"sender":            message.from ?: @"",
        @"recipient":         message.to ?: @"",
        @"content_type":      message.contentType ?: @"text",
        @"content":           message.content ?: @"",
        @"file_name":         message.fileName ?: @"",
        @"file_size":         @(message.fileSize),
        @"caption":           message.caption ?: @"",
        @"conv_seq":          @(message.convSeq),
        @"timestamp":         @(message.timestamp),
        @"status":            @(message.status),
        @"note":              message.note ?: @"",
        @"from_nickname":     message.fromNickname ?: @"",
        @"from_role":         message.fromRole ?: @"",
        @"recalled_at":       @(message.recalledAt),
        @"recalled_by":       message.recalledBy ?: @"",
        @"edited_at":         @(message.editedAt),
        @"pinned_at":         @(message.pinnedAt),
        @"reply_to_conv_seq": @(message.replyToConvSeq),
        @"reply_snapshot":    message.replySnapshot ?: @"",
        @"reply_to_from":     message.replyToFrom ?: @"",
        @"forward_from":      message.forwardFrom ?: @"",
        @"group_id":          message.groupID ?: @"",
        @"poster":            message.poster ?: @"",
        @"media_w":           @(message.mediaW),
        @"media_h":           @(message.mediaH),
        @"duration":          @(message.duration),
        @"thumb":             message.thumb ?: @"",
        @"waveform":          message.waveform ?: @"",
        @"mentions":          IMEncodeMentions(message.mentions),
        @"mention_all":       @(message.mentionAll),
        @"sys_segments":      IMEncodeSysSegments(message.sysSegments),
    };
}

/// 系统消息分段 ↔ TEXT 列（JSON 数组；空存空串）。必须落库：否则重进会话/冷启动读本地库时
/// 分段丢失，系统消息会退回"显真实昵称、名字不可点"，与刚收到时不一致。
/// 解析失败按「无分段」降级（回退整句），不阻断消息读取（与 mentions 同取舍）。
static NSString *IMEncodeSysSegments(NSArray<IMSysSegment *> *segments) {
    if (segments.count == 0) { return @""; }
    NSArray *raw = [IMSysSegment arrayFromSegments:segments];
    NSData *d = raw.count > 0 ? [NSJSONSerialization dataWithJSONObject:raw options:0 error:NULL] : nil;
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"";
}

static NSArray<IMSysSegment *> *IMDecodeSysSegments(NSString *raw) {
    if (raw.length == 0) { return nil; }
    NSData *d = [raw dataUsingEncoding:NSUTF8StringEncoding];
    id arr = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    return [IMSysSegment segmentsFromArray:arr];
}

/// mentions []NSString ↔ TEXT 列（JSON 数组；空存空串）。解析失败按「未 @ 任何人」降级——
/// @ 只影响转发重发的提醒强度，绝不能让脏数据阻断消息读取（与后端 decodeMentions 同取舍）。
static NSString *IMEncodeMentions(NSArray<NSString *> *mentions) {
    if (mentions.count == 0) { return @""; }
    NSData *d = [NSJSONSerialization dataWithJSONObject:mentions options:0 error:NULL];
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"";
}

static NSArray<NSString *> *IMDecodeMentions(NSString *raw) {
    if (raw.length == 0) { return nil; }
    NSData *d = [raw dataUsingEncoding:NSUTF8StringEncoding];
    id arr = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if (![arr isKindOfClass:[NSArray class]]) { return nil; }
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id v in (NSArray *)arr) {
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) { [out addObject:v]; }
    }
    return out.count > 0 ? out : nil;
}

- (BOOL)saveIncomingMessage:(IMMessageModel *)message advancingSyncedConvSeq:(int64_t)syncedConvSeq {
    if (message.convID.length == 0) { return NO; }
    NSString *owner = [self ownerUserID];
    __block BOOL saved = NO;
    [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        NSNumber *rowID = [self existingRowIDFor:message owner:owner in:db];
        BOOL inserted = rowID == nil;
        BOOL ok = NO;
        if (rowID) {
            // UPDATE 保留手写：CASE WHEN 是**每列不同的业务保值策略**（本地量出的 file_name/thumb/
            // 尺寸/时长优先于服务端回声的空值），不是可从列清单生成的样板；硬表驱动需发明策略 DSL，
            // 反而难读难查。列名本身由建表/迁移同源保证存在，这里只依赖列名不定义列清单。
            ok = [db executeUpdate:
                @"UPDATE im_message_local SET server_msg_id=?,sender=?,recipient=?,content_type=?,content=?,"
                 "file_name=CASE WHEN LENGTH(?)>0 THEN ? ELSE file_name END,"
                 "file_size=CASE WHEN ?>0 THEN ? ELSE file_size END,"
                 // 媒体尺寸/时长同 file_size：本地发送端量出的值优先保留，服务端回声若为 0（老消息/老端）不覆盖。
                 "media_w=CASE WHEN ?>0 THEN ? ELSE media_w END,"
                 "media_h=CASE WHEN ?>0 THEN ? ELSE media_h END,"
                 "duration=CASE WHEN ?>0 THEN ? ELSE duration END,"
                 // thumb 同 file_name：本地发送端生成的模糊预览优先保留，服务端回声若为空不覆盖
                 // （否则重进会话拿不到 thumb，未下载卡片退回中性占位）。
                 "thumb=CASE WHEN LENGTH(?)>0 THEN ? ELSE thumb END,"
                 // waveform 同 thumb：本地录制端生成的振幅指纹优先保留（voice P0）。
                 "waveform=CASE WHEN LENGTH(?)>0 THEN ? ELSE waveform END,"
                 "conv_seq=?,timestamp=?,status=?,note=?,from_nickname=?,from_role=?,recalled_at=?,recalled_by=?,edited_at=?,pinned_at=?,reply_to_conv_seq=?,reply_snapshot=?,reply_to_from=?,forward_from=?,group_id=?,poster=? WHERE row_id=?",
                message.serverMsgID ?: @"", message.from ?: @"", message.to ?: @"",
                message.contentType ?: @"text", message.content ?: @"",
                message.fileName ?: @"", message.fileName ?: @"", @(message.fileSize), @(message.fileSize),
                @(message.mediaW), @(message.mediaW), @(message.mediaH), @(message.mediaH),
                @(message.duration), @(message.duration),
                message.thumb ?: @"", message.thumb ?: @"",
                message.waveform ?: @"", message.waveform ?: @"",
                @(message.convSeq), @(message.timestamp), @(message.status), message.note ?: @"",
                message.fromNickname ?: @"", message.fromRole ?: @"", @(message.recalledAt), message.recalledBy ?: @"",
                @(message.editedAt), @(message.pinnedAt), @(message.replyToConvSeq), message.replySnapshot ?: @"", message.replyToFrom ?: @"", message.forwardFrom ?: @"", message.groupID ?: @"", message.poster ?: @"", rowID];
        } else {
            // INSERT 列名串 + 值序列均由 +messageColumns × insertRowForMessage 同源生成：
            // 新增字段只改"列清单一行 + 值映射一行"，列串漂移（当年 file_name 事故）结构上不可能。
            // 列清单是运行期常量 → SQL 串与列序 dispatch_once 缓存一次；每条插入只构造值数组
            //（同步 burst 可达 2 万+ 条，之前每条重建 30×2 数组/字典/两次 join 是纯浪费）。
            static NSString *insertSQL;
            static NSArray<NSString *> *insertColumns;
            static dispatch_once_t once;
            dispatch_once(&once, ^{
                NSArray<NSArray<NSString *> *> *schema = [IMDatabase messageColumns];
                NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:schema.count];
                NSMutableArray<NSString *> *marks = [NSMutableArray arrayWithCapacity:schema.count];
                for (NSArray<NSString *> *c in schema) { [names addObject:c[0]]; [marks addObject:@"?"]; }
                insertColumns = names;
                insertSQL = [NSString stringWithFormat:@"INSERT INTO im_message_local (%@) VALUES (%@)",
                             [names componentsJoinedByString:@","], [marks componentsJoinedByString:@","]];
            });
            NSDictionary<NSString *, id> *row = [self insertRowForMessage:message owner:owner];
            NSAssert(row.count == insertColumns.count,
                     @"messageColumns 与 insertRowForMessage 漂移：%lu 列 vs %lu 值",
                     (unsigned long)insertColumns.count, (unsigned long)row.count);
            NSMutableArray *values = [NSMutableArray arrayWithCapacity:insertColumns.count];
            for (NSString *col in insertColumns) {
                id v = row[col];
                NSAssert(v, @"insertRowForMessage 缺列 %@ 的值", col);
                // release 兜底绑 NULL（列数恒与 SQL 对齐）：可空列落 NULL、NOT NULL 列让 INSERT
                // **显式报错**并落日志——绝不静默把列从语句里抠掉（那是 file_name 事故的安静变种）。
                [values addObject:v ?: NSNull.null];
            }
            ok = [db executeUpdate:insertSQL withArgumentsInArray:values];
        }
        if (!ok) {
            IMLogDatabase(@"保存消息失败 owner=%@ conv=%@: %@", owner, message.convID, db.lastErrorMessage);
            *rollback = YES;
            return;
        }
        if (![self updateConversationForMessage:message owner:owner inserted:inserted inDB:db]) {
            *rollback = YES;
            return;
        }
        if (syncedConvSeq > 0 && ![db executeUpdate:
            @"UPDATE im_conversation_local SET synced_conv_seq=MAX(synced_conv_seq,?) WHERE owner_uid=? AND conv_id=?",
            @(syncedConvSeq), owner, message.convID]) {
            IMLogDatabase(@"消息与连续位置原子提交失败 owner=%@ conv=%@: %@", owner, message.convID, db.lastErrorMessage);
            *rollback = YES;
            return;
        }
        saved = YES;
    }];
    return saved;
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
    // 系统消息（进群/改名/踢人等）不计未读：服务端 unread 也排除它，否则群系统事件会把本地角标
    // 顶得比权威值高，直到下次拉取 /conversations 才收敛（与服务端口径对齐）。
    BOOL isSystem = [message.contentType isEqualToString:@"system"];
    NSInteger unreadDelta = inserted && isIncoming && isUnread && !representedByServerSnapshot && !isSystem ? 1 : 0;
    if (!exists) {
        BOOL ok = [db executeUpdate:
            @"INSERT INTO im_conversation_local (owner_uid,conv_id,sort_order,is_group,name,avatar_url,member_count,peer,peer_nickname,peer_avatar_url,last_content,last_from,last_from_nickname,last_recalled,last_content_type,last_caption,latest_conv_seq,read_seq,peer_read_seq,timestamp,unread,pinned_at,muted,marked_unread,server_snapshot_seq) VALUES (?,?,0,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,0,0,0)",
            owner, message.convID, @(isGroup), isGroup ? @"群聊" : @"", @"", @0,
            isGroup ? @"" : (peer ?: @""), isGroup ? @"" : (peer ?: @""), @"",
            message.content ?: @"", message.from ?: @"", message.fromNickname ?: @"",
            @(message.recalledAt > 0), message.contentType ?: @"text", message.caption ?: @"", @(message.convSeq), @0, @0,
            @(message.timestamp), @(unreadDelta)];
        if (!ok) {
            IMLogDatabase(@"由消息创建会话缓存失败 owner=%@ conv=%@: %@", owner, message.convID, db.lastErrorMessage);
            return NO;
        }
    } else if (isLatest) {
        BOOL ok = [db executeUpdate:
            // last_caption 必须随每条新消息**覆写**（含无 caption 的空串）：漏写会把上一条的图说文字
            // 串到新消息的预览上（code-review 2026-08-19——快照写入路径有它、实时路径漏了）。
            @"UPDATE im_conversation_local SET last_content=?,last_from=?,last_from_nickname=?,last_recalled=?,last_content_type=?,last_caption=?,latest_conv_seq=MAX(latest_conv_seq,?),timestamp=MAX(timestamp,?),unread=MIN(999,unread+?) WHERE owner_uid=? AND conv_id=?",
            message.content ?: @"", message.from ?: @"", message.fromNickname ?: @"",
            @(message.recalledAt > 0), message.contentType ?: @"text", message.caption ?: @"", @(message.convSeq),
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
        // 读到底即清「@我」未读：与服务端 mention_unread 收敛同口径，避免本地快路残留「[有人@我]」前缀。
        if (![db executeUpdate:
              @"UPDATE im_conversation_local SET read_seq=MAX(read_seq,?),unread=0,mention_unread=0 WHERE owner_uid=? AND conv_id=?",
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

/// 单独把会话备注写进本地缓存（conv_update remark 到达 / 本端改备注乐观更新用）。
/// 与 applyCachedSettings 分开：备注变更不动三开关，反之亦然。
- (void)applyCachedRemarkForConversation:(NSString *)convID remark:(nullable NSString *)remark {
    if (convID.length == 0) { return; }
    NSString *owner = [self ownerUserID];
    [_queue inDatabase:^(FMDatabase *db) {
        if (![db executeUpdate:@"UPDATE im_conversation_local SET remark=? WHERE owner_uid=? AND conv_id=?",
              remark ?: @"", owner, convID]) {
            IMLogDatabase(@"更新本地会话备注失败 owner=%@ conv=%@: %@", owner, convID, db.lastErrorMessage);
        }
    }];
}

/// 好友备注名落缓存：单聊会话行（列表显示名）与好友快照行（通讯录显示名）是两张表，
/// 同一份备注得同时写，否则两处冷启动会显示不一致的名字。会话行按 peer 定位——
/// 单聊 conv_id 由双方 uid 拼成，但拼法归 IMConversationID 管，这里不重复该规则。
- (void)applyCachedRemark:(nullable NSString *)remark forPeer:(NSString *)peerID {
    if (peerID.length == 0) { return; }
    NSString *owner = [self ownerUserID];
    NSString *value = remark ?: @"";
    [_queue inDatabase:^(FMDatabase *db) {
        if (![db executeUpdate:@"UPDATE im_conversation_local SET peer_remark=? WHERE owner_uid=? AND peer=?",
              value, owner, peerID]) {
            IMLogDatabase(@"更新本地好友备注（会话行）失败 owner=%@ peer=%@: %@", owner, peerID, db.lastErrorMessage);
        }
        if (![db executeUpdate:@"UPDATE im_friend_local SET remark=? WHERE owner_uid=? AND user_id=?",
              value, owner, peerID]) {
            IMLogDatabase(@"更新本地好友备注（好友行）失败 owner=%@ peer=%@: %@", owner, peerID, db.lastErrorMessage);
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

/// 出站消息按 (conv_id, client_msg_id) 匹配；入站按 (conv_id, conv_seq) 匹配所有消息。
/// 后者包含本机带 client_msg_id 的乐观消息，重启补拉时才能用服务端记录覆盖原行而非插入重复气泡。
- (void)replaceClientMsgID:(NSString *)oldClientMsgID
           withClientMsgID:(NSString *)newClientMsgID
                    inConv:(NSString *)convID {
    if (oldClientMsgID.length == 0 || newClientMsgID.length == 0 || convID.length == 0) { return; }
    if ([oldClientMsgID isEqualToString:newClientMsgID]) { return; }
    NSString *owner = [self ownerUserID];
    [_queue inDatabase:^(FMDatabase *db) {
        if (![db executeUpdate:@"UPDATE im_message_local SET client_msg_id=? WHERE owner_uid=? AND conv_id=? AND client_msg_id=?",
              newClientMsgID, owner, convID, oldClientMsgID]) {
            IMLogDatabase(@"改写 client_msg_id 失败 conv=%@: %@", convID, db.lastErrorMessage);
        }
    }];
}

- (NSNumber *)existingRowIDFor:(IMMessageModel *)message owner:(NSString *)owner in:(FMDatabase *)db {
    FMResultSet *rs = nil;
    if (message.clientMsgID.length > 0) {
        rs = [db executeQuery:@"SELECT row_id FROM im_message_local WHERE owner_uid=? AND conv_id=? AND client_msg_id=? LIMIT 1",
              owner, message.convID, message.clientMsgID];
    } else if (message.convSeq > 0) {
        rs = [db executeQuery:@"SELECT row_id FROM im_message_local WHERE owner_uid=? AND conv_id=? AND conv_seq=? LIMIT 1",
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
        // 排序**按时间戳优先**（与 im-web App.tsx 的渲染排序 `timestamp || (convSeq||MAX)` 逐条对齐）。
        // 曾用 `CASE WHEN conv_seq>0 THEN 0 ELSE 1`（conv_seq=0 一律垫底）——本意是让「刚发出、
        // 还没 ack 的临时消息」显示在最底部，但**被拒收的消息永远 conv_seq=0**，于是从「临时垫底」
        // 变成「永久钉底」：后续收到的消息（conv_seq>0）全插到它上面，用户滚到底只看到旧的失败消息、
        // 误以为没收到（2026-08-05 复盘，1001↔1003 单向删除场景）。
        // 改法：timestamp 主排（拒收老消息按真实时间落位）；同毫秒时 conv_seq=0 视为最大值垫底
        // （保住「待发临时消息在底部」的原意，等价于 im-web 的 `convSeq || MAX_SAFE_INTEGER`）；
        // row_id 兜同刻同序。补拉的旧消息时间戳本就旧，timestamp 主排同样正确排到上方，不破坏同步语义。
        // ⚠️ 新增字段的第③处：下方逐列映射须同步补一行（第④处是 IMDatabaseSchemaTests 的
        // 回环断言——漏改这里由它抓出）。SELECT * 名字取列，天然不受列序影响。
        FMResultSet *rs = [db executeQuery:
            @"SELECT * FROM im_message_local WHERE owner_uid=? AND conv_id=? "
             "ORDER BY timestamp ASC,"
             "CASE WHEN conv_seq>0 THEN conv_seq ELSE 9223372036854775807 END ASC,"
             "row_id ASC",
            owner, convID];
        while ([rs next]) {
            [out addObject:[IMDatabase messageFromResultSet:rs]];
        }
        [rs close];
    }];
    return out;
}

/// im_message_local 行 → IMMessageModel 的**唯一映射**（列清单第③处，见 +messageColumns 注释）。
/// messagesForConv / searchMessagesMatching 共用，杜绝两处映射漂移。SELECT * 名字取列，不受列序影响。
+ (IMMessageModel *)messageFromResultSet:(FMResultSet *)rs {
    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = [rs stringForColumn:@"client_msg_id"];
    m.serverMsgID = [rs stringForColumn:@"server_msg_id"];
    m.convID      = [rs stringForColumn:@"conv_id"];
    m.from        = [rs stringForColumn:@"sender"];
    m.to          = [rs stringForColumn:@"recipient"];
    m.contentType = [rs stringForColumn:@"content_type"];
    m.content     = [rs stringForColumn:@"content"];
    NSString *fileName = [rs stringForColumn:@"file_name"];
    m.fileName    = fileName.length > 0 ? fileName : nil;
    m.fileSize    = [rs longLongIntForColumn:@"file_size"];
    NSString *caption = [rs stringForColumn:@"caption"];
    m.caption     = caption.length > 0 ? caption : nil;
    m.mentions    = IMDecodeMentions([rs stringForColumn:@"mentions"]);
    m.mentionAll  = [rs boolForColumn:@"mention_all"];
    m.sysSegments = IMDecodeSysSegments([rs stringForColumn:@"sys_segments"]);
    m.convSeq     = [rs longLongIntForColumn:@"conv_seq"];
    m.timestamp   = [rs longLongIntForColumn:@"timestamp"];
    m.status      = (IMMessageStatus)[rs longForColumn:@"status"];
    NSString *note = [rs stringForColumn:@"note"];
    m.note        = note.length > 0 ? note : nil; // 空串视作无系统提示
    NSString *nick = [rs stringForColumn:@"from_nickname"];
    m.fromNickname = nick.length > 0 ? nick : nil; // 空串视作无昵称（回退 uid）
    NSString *frole = [rs stringForColumn:@"from_role"];
    m.fromRole = frole.length > 0 ? frole : nil;   // 空串视作无（普通成员/单聊）
    m.recalledAt  = [rs longLongIntForColumn:@"recalled_at"];
    NSString *rby = [rs stringForColumn:@"recalled_by"];
    m.recalledBy  = rby.length > 0 ? rby : nil;
    m.editedAt    = [rs longLongIntForColumn:@"edited_at"];
    m.pinnedAt    = [rs longLongIntForColumn:@"pinned_at"];
    m.replyToConvSeq = [rs longLongIntForColumn:@"reply_to_conv_seq"];
    NSString *snap = [rs stringForColumn:@"reply_snapshot"];
    m.replySnapshot = snap.length > 0 ? snap : nil;
    NSString *rf = [rs stringForColumn:@"reply_to_from"];
    m.replyToFrom = rf.length > 0 ? rf : nil;
    NSString *ff = [rs stringForColumn:@"forward_from"];
    m.forwardFrom = ff.length > 0 ? ff : nil;
    NSString *gid = [rs stringForColumn:@"group_id"];
    m.groupID = gid.length > 0 ? gid : nil;
    NSString *poster = [rs stringForColumn:@"poster"];
    m.poster = poster.length > 0 ? poster : nil;
    m.mediaW   = [rs longForColumn:@"media_w"];
    m.mediaH   = [rs longForColumn:@"media_h"];
    m.duration = [rs longLongIntForColumn:@"duration"];
    NSString *thumb = [rs stringForColumn:@"thumb"];
    m.thumb = thumb.length > 0 ? thumb : nil; // 空串视作无模糊预览（回退中性占位）
    NSString *waveform = [rs stringForColumn:@"waveform"];
    m.waveform = waveform.length > 0 ? waveform : nil; // 空=退化等高条纹（voice P0）
    return m;
}

/// 本地全文搜索（搜索功能 P0，纯本地）。convID 传 nil = 跨全部会话（首页全局搜索）；否则限该会话（会话内搜索）。
/// 命中口径与后端 G4 一致：`content_type='text' 的 content` 或任意消息的 `caption` 子串（大小写不敏感，`escapeLikePattern:` 转义 %_\）。
/// 排除撤回（recalled_at>0）；本地删除是物理删行故天然不含。按 timestamp 倒序（新在前），limit<=0 用默认上限。
- (NSArray<IMMessageModel *> *)searchMessagesMatching:(NSString *)keyword
                                               inConv:(nullable NSString *)convID
                                                limit:(NSInteger)limit {
    NSString *trimmed = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) { return @[]; }
    NSString *owner = [self ownerUserID];
    NSString *like = [NSString stringWithFormat:@"%%%@%%", [IMDatabase escapeLikePattern:trimmed]];
    NSInteger cap = (limit > 0) ? limit : 500;
    NSMutableArray<IMMessageModel *> *out = [NSMutableArray array];
    [_queue inDatabase:^(FMDatabase *db) {
        // 命中：text 消息 content / 任意消息 caption / 文件消息 file_name（P2：找「Q3预算.xlsx」这类文件名）。
        // 媒体/文件的 content 是 URL，仍不参与（撞 URL 片段会命中看不见文字的消息）。
        NSMutableString *sql = [NSMutableString stringWithString:
            @"SELECT * FROM im_message_local WHERE owner_uid=? AND recalled_at=0 "
             "AND ((content_type='text' AND content LIKE ? ESCAPE '\\') "
             "OR (caption IS NOT NULL AND caption<>'' AND caption LIKE ? ESCAPE '\\') "
             "OR (file_name IS NOT NULL AND file_name<>'' AND file_name LIKE ? ESCAPE '\\')) "];
        NSMutableArray *args = [NSMutableArray arrayWithObjects:owner, like, like, like, nil];
        if (convID.length > 0) { [sql appendString:@"AND conv_id=? "]; [args addObject:convID]; }
        [sql appendString:@"ORDER BY timestamp DESC, conv_seq DESC, row_id DESC LIMIT ?"];
        [args addObject:@(cap)];
        FMResultSet *rs = [db executeQuery:sql withArgumentsInArray:args];
        while ([rs next]) { [out addObject:[IMDatabase messageFromResultSet:rs]]; }
        [rs close];
    }];
    return out;
}

/// SQLite LIKE 通配符转义（镜像后端 store.escapeLike）：`\`→`\\`、`%`→`\%`、`_`→`\_`，配合 `ESCAPE '\'`。
+ (NSString *)escapeLikePattern:(NSString *)raw {
    NSString *s = [raw stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    s = [s stringByReplacingOccurrencesOfString:@"%" withString:@"\\%"];
    s = [s stringByReplacingOccurrencesOfString:@"_" withString:@"\\_"];
    return s;
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

- (int64_t)syncedConvSeqForConv:(NSString *)convID {
    if (convID.length == 0) { return 0; }
    NSString *owner = [self ownerUserID];
    __block int64_t syncedSeq = 0;
    [_queue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:
            @"SELECT synced_conv_seq FROM im_conversation_local WHERE owner_uid=? AND conv_id=? LIMIT 1",
            owner, convID];
        if ([rs next]) { syncedSeq = [rs longLongIntForColumn:@"synced_conv_seq"]; }
        [rs close];
    }];
    return syncedSeq;
}

- (void)advanceSyncedConvSeqForConv:(NSString *)convID toConvSeq:(int64_t)convSeq {
    if (convID.length == 0 || convSeq <= 0) { return; }
    NSString *owner = [self ownerUserID];
    [_queue inDatabase:^(FMDatabase *db) {
        if (![db executeUpdate:
              @"UPDATE im_conversation_local SET synced_conv_seq=MAX(synced_conv_seq,?) WHERE owner_uid=? AND conv_id=?",
              @(convSeq), owner, convID]) {
            IMLogDatabase(@"推进连续同步位置失败 owner=%@ conv=%@: %@", owner, convID, db.lastErrorMessage);
        }
    }];
}

- (void)applyMsgOpForConv:(NSString *)convID
            targetConvSeq:(int64_t)targetConvSeq
               recalledAt:(int64_t)recalledAt
               recalledBy:(nullable NSString *)recalledBy
                 editedAt:(int64_t)editedAt
                 pinnedAt:(int64_t)pinnedAt
               newContent:(nullable NSString *)newContent {
    [self applyMsgOpForConv:convID targetConvSeq:targetConvSeq
                 recalledAt:recalledAt recalledBy:recalledBy
                   editedAt:editedAt pinnedAt:pinnedAt newContent:newContent
      advancingSyncedConvSeq:0];
}

- (BOOL)applyMsgOpForConv:(NSString *)convID
            targetConvSeq:(int64_t)targetConvSeq
               recalledAt:(int64_t)recalledAt
               recalledBy:(nullable NSString *)recalledBy
                 editedAt:(int64_t)editedAt
                 pinnedAt:(int64_t)pinnedAt
               newContent:(nullable NSString *)newContent
    advancingSyncedConvSeq:(int64_t)syncedConvSeq {
    if (convID.length == 0 || targetConvSeq <= 0) { return NO; }
    NSString *owner = [self ownerUserID];
    __block BOOL applied = NO;
    [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        NSMutableArray *sets = [NSMutableArray array];
        NSMutableArray *args = [NSMutableArray array];
        if (recalledAt > 0) { [sets addObject:@"recalled_at=?"]; [args addObject:@(recalledAt)];
                              [sets addObject:@"recalled_by=?"]; [args addObject:recalledBy ?: @""]; }
        if (editedAt > 0)   { [sets addObject:@"edited_at=?"];   [args addObject:@(editedAt)]; }
        // 置顶：>0 置顶、**<0 取消置顶**（写回 0）、0 不改该项。
        // 取消置顶与置顶共用 op=pin，若沿用"0=不改"就永远落不了地——本地会一直显示已置顶（G0 修）。
        if (pinnedAt > 0)      { [sets addObject:@"pinned_at=?"];   [args addObject:@(pinnedAt)]; }
        else if (pinnedAt < 0) { [sets addObject:@"pinned_at=?"];   [args addObject:@(0)]; }
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
            // 撤回连 last_caption 一起脱敏（与服务端 conversation 预览同口径）：撤回的图说文字不得残留在会话摘要里。
            if (![db executeUpdate:
                  @"UPDATE im_conversation_local SET last_recalled=1,last_caption='' WHERE owner_uid=? AND conv_id=? AND latest_conv_seq=?",
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
        if (*rollback) { return; }
        if (syncedConvSeq > 0 && ![db executeUpdate:
            @"UPDATE im_conversation_local SET synced_conv_seq=MAX(synced_conv_seq,?) WHERE owner_uid=? AND conv_id=?",
            @(syncedConvSeq), owner, convID]) {
            IMLogDatabase(@"消息操作与连续位置原子提交失败 owner=%@ conv=%@: %@", owner, convID, db.lastErrorMessage);
            *rollback = YES;
            return;
        }
        applied = YES;
    }];
    return applied;
}

- (BOOL)deleteLocalMessageForConv:(NSString *)convID
                          convSeq:(int64_t)convSeq
           advancingSyncedConvSeq:(int64_t)syncedConvSeq {
    if (convID.length == 0 || convSeq <= 0) { return NO; }
    NSString *owner = [self ownerUserID];
    // applied 表示「本次是否真的改动了持久状态」（删掉了 ≥1 条消息行，或推进了连续位点）。
    // 返回值用于让调用方决定是否广播刷新通知：目标行早已不存在时不发通知，避免
    //「列表 remove 通知 → onSocketMessage → reload → fetchHiddenCatchUp 重删已不存在的隐藏项 →
    // 又发 remove 通知」的自激刷新回路（会话列表 ~0.47s 空转刷新的根因）。
    __block BOOL applied = NO;
    [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if (![db executeUpdate:@"DELETE FROM im_message_local WHERE owner_uid=? AND conv_id=? AND conv_seq=?",
              owner, convID, @(convSeq)]) {
            IMLogDatabase(@"删除本地消息失败 owner=%@ conv=%@ seq=%lld: %@", owner, convID, convSeq, db.lastErrorMessage);
            *rollback = YES;
            return;
        }
        BOOL deletedRow = (db.changes > 0);
        if (syncedConvSeq > 0 && ![db executeUpdate:
            @"UPDATE im_conversation_local SET synced_conv_seq=MAX(synced_conv_seq,?) WHERE owner_uid=? AND conv_id=?",
            @(syncedConvSeq), owner, convID]) {
            IMLogDatabase(@"删除消息与连续位置原子提交失败 owner=%@ conv=%@: %@", owner, convID, db.lastErrorMessage);
            *rollback = YES;
            return;
        }
        applied = deletedRow || (syncedConvSeq > 0 && db.changes > 0);
    }];
    return applied;
}

- (NSInteger)totalUnreadExcludingConv:(nullable NSString *)excludeConvID {
    NSString *owner = [self ownerUserID];
    __block NSInteger total = 0;
    [_queue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs;
        if (excludeConvID.length > 0) {
            rs = [db executeQuery:@"SELECT COALESCE(SUM(unread),0) AS t FROM im_conversation_local WHERE owner_uid=? AND conv_id<>?",
                  owner, excludeConvID];
        } else {
            rs = [db executeQuery:@"SELECT COALESCE(SUM(unread),0) AS t FROM im_conversation_local WHERE owner_uid=?", owner];
        }
        if ([rs next]) { total = (NSInteger)[rs longForColumn:@"t"]; }
        [rs close];
    }];
    return total;
}

@end
