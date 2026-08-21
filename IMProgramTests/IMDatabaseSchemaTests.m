#import <XCTest/XCTest.h>
#import <FMDB/FMDB.h>

#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMMessageModel.h"

/// 守 im_message_local 的**列清单单一来源**（IMDatabase +messageColumns 驱动建表+迁移）。
/// 核心防的是历史事故：CREATE 新增列却漏进迁移表 → 老库缺列 → INSERT 全失败、同步游标卡死。
@interface IMDatabaseSchemaTests : XCTestCase
@end

@implementation IMDatabaseSchemaTests

- (NSURL *)temporaryDatabaseURL {
    NSString *name = [NSString stringWithFormat:@"im-schema-test-%@.sqlite", NSUUID.UUID.UUIDString];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

/// 造一条**把每个新列都填上**的消息，用于验证建表/迁移/写入/读取四处列名一致、字段逐个回环。
- (IMMessageModel *)fullyPopulatedMessageInConv:(NSString *)convID {
    IMMessageModel *m = [IMMessageModel new];
    m.convID       = convID;
    m.from         = @"alice";
    m.to           = @"bob";
    m.contentType  = @"image";
    m.content      = @"/uploads/pic.jpg";
    m.fileName     = @"原图.jpg";
    m.fileSize     = 204800;
    m.convSeq      = 42;
    m.timestamp    = 1700000000000;
    m.status       = 1;
    m.note         = @"对方拒收";
    m.fromNickname = @"爱丽丝";
    m.fromRole     = @"admin";
    m.recalledAt   = 1700000001000;
    m.recalledBy   = @"alice";
    m.editedAt     = 1700000002000;
    m.pinnedAt     = 1700000003000;
    m.replyToConvSeq = 7;
    m.replySnapshot  = @"被引用的话";
    m.replyToFrom    = @"carol";
    m.forwardFrom  = @"dave";
    m.groupID      = @"album-1";
    m.poster       = @"/uploads/poster.jpg";
    m.mediaW       = 1080;
    m.mediaH       = 1920;
    m.duration     = 15000;
    m.thumb        = @"data:image/jpeg;base64,AAAA";
    m.caption      = @"周末爬山拍的";      // 图说随附文本（2026-08-19）
    m.mentions     = @[@"bob", @"carol"]; // 配文 @（JSON TEXT 列，转发重发用）
    m.mentionAll   = YES;
    return m;
}

- (void)seedConversation:(NSString *)convID inDatabase:(IMDatabase *)db {
    IMConversation *c = [IMConversation new];
    c.convID = convID;
    c.peer = @"bob";
    c.peerNickname = @"鲍勃";
    c.lastContent = @"seed";
    c.lastContentType = @"text";
    c.latestConvSeq = 1;
    c.timestamp = 1;
    [db replaceCachedConversations:@[c]];
}

- (void)assertMessage:(IMMessageModel *)m matchesFullyPopulated:(NSString *)convID {
    XCTAssertNotNil(m);
    // 覆盖 fullyPopulated 的**每一个**字段：读路径（messagesForConv 的 SELECT 逐列映射）漏改
    // 任何一列都要在这里翻红——这是列清单"新增字段四处"里的第④处守卫。
    XCTAssertEqualObjects(m.convID, convID);
    XCTAssertEqualObjects(m.from, @"alice");
    XCTAssertEqualObjects(m.to, @"bob");
    XCTAssertEqual(m.convSeq, 42);
    XCTAssertEqual(m.timestamp, 1700000000000);
    XCTAssertEqual(m.status, 1);
    XCTAssertEqual(m.editedAt, 1700000002000);
    XCTAssertEqualObjects(m.recalledBy, @"alice");
    XCTAssertEqual(m.replyToConvSeq, 7);
    XCTAssertEqualObjects(m.replyToFrom, @"carol");
    XCTAssertEqualObjects(m.contentType, @"image");
    XCTAssertEqualObjects(m.content, @"/uploads/pic.jpg");
    XCTAssertEqualObjects(m.fileName, @"原图.jpg");
    XCTAssertEqual(m.fileSize, 204800);
    XCTAssertEqualObjects(m.note, @"对方拒收");
    XCTAssertEqualObjects(m.fromNickname, @"爱丽丝");
    XCTAssertEqualObjects(m.fromRole, @"admin");
    XCTAssertEqual(m.pinnedAt, 1700000003000);
    XCTAssertEqual(m.recalledAt, 1700000001000);
    XCTAssertEqualObjects(m.replySnapshot, @"被引用的话");
    XCTAssertEqualObjects(m.forwardFrom, @"dave");
    XCTAssertEqualObjects(m.groupID, @"album-1");
    XCTAssertEqualObjects(m.poster, @"/uploads/poster.jpg");
    XCTAssertEqual(m.mediaW, 1080);
    XCTAssertEqual(m.mediaH, 1920);
    XCTAssertEqual(m.duration, 15000);
    XCTAssertEqualObjects(m.thumb, @"data:image/jpeg;base64,AAAA");
    XCTAssertEqualObjects(m.caption, @"周末爬山拍的");
    XCTAssertEqualObjects(m.mentions, (@[@"bob", @"carol"]));
    XCTAssertTrue(m.mentionAll);
}

/// 全新库：建表由 +messageColumns 生成，每个字段都能写入并读回 → 证明列清单完整、无漏列。
- (void)testAllMessageColumnsRoundTripOnFreshDatabase {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:url];
    [db useOwnerUserID:@"alice"];
    [self seedConversation:@"conv-fresh" inDatabase:db];

    [db saveMessage:[self fullyPopulatedMessageInConv:@"conv-fresh"]];
    IMMessageModel *loaded = [db messagesForConv:@"conv-fresh"].lastObject;
    [self assertMessage:loaded matchesFullyPopulated:@"conv-fresh"];

    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

/// 老库场景（复刻 2.2 万条失败事故）：预置一张**只有最初列**的 im_message_local，
/// 打开 IMDatabase 触发迁移补齐后，仍能写入并读回所有新字段 → 证明建表与迁移同源、永不漂移。
- (void)testLegacyDatabaseMissingColumnsIsMigratedThenSavesFullMessage {
    NSURL *url = [self temporaryDatabaseURL];

    // 1) 用裸 FMDatabase 造一张缺列的老表：无 file_name/file_size/note/thumb 及所有 M4 派生列。
    FMDatabase *legacy = [FMDatabase databaseWithPath:url.path];
    XCTAssertTrue([legacy open]);
    XCTAssertTrue([legacy executeUpdate:
        @"CREATE TABLE im_message_local ("
         "row_id INTEGER PRIMARY KEY AUTOINCREMENT,"
         "owner_uid TEXT NOT NULL DEFAULT '',"
         "client_msg_id TEXT, server_msg_id TEXT, conv_id TEXT NOT NULL,"
         "sender TEXT, recipient TEXT, content_type TEXT, content TEXT,"
         "conv_seq INTEGER, timestamp INTEGER, status INTEGER)"]);
    XCTAssertFalse([legacy columnExists:@"thumb" inTableWithName:@"im_message_local"]);
    XCTAssertFalse([legacy columnExists:@"file_name" inTableWithName:@"im_message_local"]);
    [legacy close];

    // 2) 打开 IMDatabase → createTables 走迁移补齐缺列。
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:url];
    [db useOwnerUserID:@"alice"];
    [self seedConversation:@"conv-legacy" inDatabase:db];

    // 3) 迁移后写满字段的消息应成功落库并完整读回（老库缺列时这一步曾整条 INSERT 失败）。
    [db saveMessage:[self fullyPopulatedMessageInConv:@"conv-legacy"]];
    NSArray<IMMessageModel *> *rows = [db messagesForConv:@"conv-legacy"];
    XCTAssertEqual(rows.count, 1, @"迁移后消息应成功落库（历史事故：缺列导致 INSERT 全失败、0 条）");
    [self assertMessage:rows.lastObject matchesFullyPopulated:@"conv-legacy"];

    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

#pragma mark - 会话内 / 全局本地搜索（searchMessagesMatching:inConv:limit:）

- (IMMessageModel *)textMessage:(NSString *)content conv:(NSString *)conv seq:(int64_t)seq ts:(int64_t)ts {
    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = [NSString stringWithFormat:@"c-%@-%lld", conv, seq];
    m.convID = conv; m.from = @"alice"; m.to = @"bob";
    m.contentType = @"text"; m.content = content;
    m.convSeq = seq; m.timestamp = ts; m.status = 1;
    return m;
}

/// 命中口径：text 的 content 或任意消息的 caption 子串（大小写不敏感）；排除撤回；媒体 URL 不匹配。
- (void)testSearchMatchesTextAndCaptionExcludesRecalledAndMediaURL {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:url];
    [db useOwnerUserID:@"alice"];
    [self seedConversation:@"conv-s" inDatabase:db];

    [db saveMessage:[self textMessage:@"Q3 预算终稿已发你邮箱" conv:@"conv-s" seq:1 ts:1000]];
    IMMessageModel *img = [self textMessage:@"/uploads/yusuan-report.jpg" conv:@"conv-s" seq:2 ts:2000];
    img.contentType = @"image"; img.caption = @"本月预算表整理好了";   // caption 命中
    [db saveMessage:img];
    [db saveMessage:[self textMessage:@"今天天气不错" conv:@"conv-s" seq:3 ts:3000]];
    IMMessageModel *recalled = [self textMessage:@"预算复盘会取消" conv:@"conv-s" seq:4 ts:4000];
    recalled.recalledAt = 4500;                                       // 撤回 → 排除
    [db saveMessage:recalled];

    NSArray<IMMessageModel *> *hits = [db searchMessagesMatching:@"预算" inConv:@"conv-s" limit:0];
    XCTAssertEqual(hits.count, 2, @"应命中 text 正文 + 媒体 caption，排除撤回与媒体 URL");
    // 时间倒序：新在前（caption 那条 ts=2000 在 text ts=1000 之前？text ts=1000 更旧 → caption 在前）
    XCTAssertEqual(hits[0].convSeq, 2);
    XCTAssertEqual(hits[1].convSeq, 1);
    XCTAssertEqualObjects(hits[0].caption, @"本月预算表整理好了");

    // 大小写不敏感
    XCTAssertEqual([db searchMessagesMatching:@"q3" inConv:@"conv-s" limit:0].count, 1);
    // 空关键词 → 空
    XCTAssertEqual([db searchMessagesMatching:@"   " inConv:@"conv-s" limit:0].count, 0);

    // 文件名命中（P2）：file 消息按 file_name 命中，其 content(URL) 仍不参与。
    // 关键词用只在文件名里的 "xlsx"（正文/图说都不含），隔离验证；"deadbeef" 只在 URL 里。
    IMMessageModel *file = [self textMessage:@"/uploads/deadbeef.bin" conv:@"conv-s" seq:5 ts:5000];
    file.contentType = @"file"; file.fileName = @"季度汇报.xlsx"; file.fileSize = 2048;
    [db saveMessage:file];
    XCTAssertEqual([db searchMessagesMatching:@"xlsx" inConv:@"conv-s" limit:0].count, 1, @"文件名命中");
    XCTAssertEqual([db searchMessagesMatching:@"deadbeef" inConv:@"conv-s" limit:0].count, 0, @"文件 content(URL) 不参与");

    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

/// convID=nil 跨全部会话；LIKE 通配符 % 被转义为字面量。
- (void)testSearchGlobalScopeAndLikeWildcardEscaped {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:url];
    [db useOwnerUserID:@"alice"];
    [self seedConversation:@"conv-a" inDatabase:db];
    [self seedConversation:@"conv-b" inDatabase:db];

    [db saveMessage:[self textMessage:@"季度增长 50% 达标" conv:@"conv-a" seq:1 ts:1000]];
    [db saveMessage:[self textMessage:@"预算在 conv-b" conv:@"conv-b" seq:1 ts:2000]];
    [db saveMessage:[self textMessage:@"利润率 5 成" conv:@"conv-b" seq:2 ts:3000]];   // 不含字面 "50%"

    // 全局：两会话都搜
    XCTAssertEqual([db searchMessagesMatching:@"预算" inConv:nil limit:0].count, 1);
    // 会话内限定
    XCTAssertEqual([db searchMessagesMatching:@"预算" inConv:@"conv-a" limit:0].count, 0);
    // % 当字面量：仅精确含 "50%" 的那条命中，"利润率 5 成" 不命中
    NSArray<IMMessageModel *> *pct = [db searchMessagesMatching:@"50%" inConv:nil limit:0];
    XCTAssertEqual(pct.count, 1);
    XCTAssertEqual(pct[0].convSeq, 1);

    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

@end
