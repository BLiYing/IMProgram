//  IMDatabaseMsgOpTests.m
//  IMDatabase 里几个小而致命的方法：临时键改写 / 本地删除的返回语义 / 消息操作联动会话摘要 /
//  整体已读 / 本地设置与备注 / 未读总数。
//
//  错法全是**静默**的：媒体发送键迁移失败 → 重复气泡；删除返回值错 → 自激刷新回路（会话列表空转闪烁）；
//  撤回/编辑没联动摘要 → 列表预览还显示撤回前的正文；设置落库时清掉定时免打扰；已读后「@我」红字残留。
//  所以按「会怎么错」钉，用例名就是那个错法。每用例独立临时库（同 IMClearFloorTests）。

#import <XCTest/XCTest.h>

#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMMessageModel.h"

@interface IMDatabaseMsgOpTests : XCTestCase
@end

@implementation IMDatabaseMsgOpTests {
    IMDatabase *_db;
    NSURL *_url;
}

static NSString * const kConv = @"u_a_u_b";
static NSString * const kOther = @"u_a_u_c";

- (void)setUp {
    [super setUp];
    NSString *name = [NSString stringWithFormat:@"im-msgop-test-%@.sqlite", NSUUID.UUID.UUIDString];
    _url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    _db = [[IMDatabase alloc] initWithFileURL:_url];
    [_db useOwnerUserID:@"a"];
}

- (void)tearDown {
    [NSFileManager.defaultManager removeItemAtURL:_url error:NULL];
    [super tearDown];
}

#pragma mark - 夹具

- (IMMessageModel *)incoming:(int64_t)seq conv:(NSString *)conv content:(NSString *)content type:(NSString *)type {
    return [IMMessageModel receivedMessageWithNewMsgData:@{
        @"server_msg_id": [NSString stringWithFormat:@"%@-s%lld", conv, seq], @"conv_id": conv, @"from": @"peer",
        @"content": content, @"content_type": type, @"conv_seq": @(seq), @"timestamp": @(1788000000000 + seq) }];
}

- (void)put:(int64_t)seq content:(NSString *)c { [_db saveIncomingMessage:[self incoming:seq conv:kConv content:c type:@"text"] advancingSyncedConvSeq:seq]; }

- (IMConversation *)conv:(NSString *)c { return [_db cachedConversationWithID:c]; }

- (IMMessageModel *)row:(int64_t)seq {
    for (IMMessageModel *m in [_db messagesForConv:kConv]) { if (m.convSeq == seq) { return m; } }
    return nil;
}

- (IMMessageModel *)pendingText:(NSString *)cid {
    IMMessageModel *m = [[IMMessageModel alloc] init];
    m.clientMsgID = cid; m.convID = kConv; m.to = @"u_b"; m.from = @"a"; m.content = @"hello"; m.contentType = @"text";
    m.status = IMMessageStatusSending; m.timestamp = 1788000009000;
    return m;
}

#pragma mark - replaceClientMsgID

/// 乐观发送的临时键换成真实键后，用真实键再保存（带上 conv_seq）必须**落到同一行**——
/// 不改键直接以新 ID 保存会插出重复行，留下一条永远失败的孤儿气泡。
- (void)test_改键后再保存不产生重复行 {
    [_db saveMessage:[self pendingText:@"tmp-1"]];
    [_db replaceClientMsgID:@"tmp-1" withClientMsgID:@"real-1" inConv:kConv];
    IMMessageModel *acked = [self pendingText:@"real-1"];
    acked.convSeq = 5; acked.status = IMMessageStatusSent;
    [_db saveMessage:acked];
    NSArray<IMMessageModel *> *rows = [_db messagesForConv:kConv];
    XCTAssertEqual(rows.count, 1u);
    XCTAssertEqualObjects(rows[0].clientMsgID, @"real-1");
    XCTAssertEqual(rows[0].convSeq, 5);
}

/// 只改本会话：别的会话里恰好同名的临时键不能被误改。
- (void)test_改键只动本会话 {
    [_db saveMessage:[self pendingText:@"tmp-1"]];
    IMMessageModel *other = [self pendingText:@"tmp-1"]; other.convID = kOther;
    [_db saveMessage:other];
    [_db replaceClientMsgID:@"tmp-1" withClientMsgID:@"real-1" inConv:kConv];
    XCTAssertEqualObjects([_db messagesForConv:kOther].firstObject.clientMsgID, @"tmp-1");
    XCTAssertEqualObjects([_db messagesForConv:kConv].firstObject.clientMsgID, @"real-1");
}

/// 空参数 / 新旧相同 / 旧键不存在：安静无操作，不崩、不动其它行。
- (void)test_改键的无效入参无操作 {
    [_db saveMessage:[self pendingText:@"tmp-1"]];
    [_db replaceClientMsgID:@"" withClientMsgID:@"x" inConv:kConv];
    [_db replaceClientMsgID:@"tmp-1" withClientMsgID:@"" inConv:kConv];
    [_db replaceClientMsgID:@"tmp-1" withClientMsgID:@"x" inConv:@""];
    [_db replaceClientMsgID:@"tmp-1" withClientMsgID:@"tmp-1" inConv:kConv];
    [_db replaceClientMsgID:@"nope" withClientMsgID:@"x" inConv:kConv];
    NSArray *rows = [_db messagesForConv:kConv];
    XCTAssertEqual(rows.count, 1u);
    XCTAssertEqualObjects([rows[0] clientMsgID], @"tmp-1");
}

#pragma mark - deleteLocalMessageForConv 返回值

/// 删到行：YES，行没了。
- (void)test_删到行返回YES {
    [self put:1 content:@"a"]; [self put:2 content:@"b"];
    XCTAssertTrue([_db deleteLocalMessageForConv:kConv convSeq:2 advancingSyncedConvSeq:0]);
    XCTAssertNil([self row:2]);
    XCTAssertNotNil([self row:1]);
}

/// 目标行早已不存在且不推进位点：NO——调用方据此**不发刷新通知**，否则「列表 remove 通知 → reload →
/// 登录 catch-up 重删已不存在的隐藏项 → 又发 remove 通知」自激回路（会话列表持续闪烁的根因）。
- (void)test_行不存在且不推进位点返回NO {
    [self put:1 content:@"a"];
    XCTAssertFalse([_db deleteLocalMessageForConv:kConv convSeq:99 advancingSyncedConvSeq:0]);
    XCTAssertFalse([_db deleteLocalMessageForConv:@"" convSeq:1 advancingSyncedConvSeq:0]);
    XCTAssertFalse([_db deleteLocalMessageForConv:kConv convSeq:0 advancingSyncedConvSeq:0]);
    XCTAssertNotNil([self row:1]);
}

/// 行不存在但推进了连续位点：位点确实动了 → YES，且位点真的前进。
- (void)test_行不存在但推进了位点返回YES {
    [self put:1 content:@"a"];
    XCTAssertTrue([_db deleteLocalMessageForConv:kConv convSeq:99 advancingSyncedConvSeq:50]);
    XCTAssertEqual([self->_db syncedConvSeqForConv:kConv], 50);
}

/// 位点只增不减：传一个更小的位点不能把它拉回去（否则同一批 sync 会被重新拉回来）。
- (void)test_位点只增不减 {
    [self put:1 content:@"a"];
    [_db deleteLocalMessageForConv:kConv convSeq:99 advancingSyncedConvSeq:50];
    [_db deleteLocalMessageForConv:kConv convSeq:98 advancingSyncedConvSeq:10];
    XCTAssertEqual([self->_db syncedConvSeqForConv:kConv], 50);
}

/// 行不存在、传入位点又不高于当前位点（什么都没变）：按头文件语义应当 NO（没有改动持久状态 → 不发刷新通知）。
- (void)test_行不存在且位点没前进也返回NO {
    [self put:1 content:@"a"];
    [_db deleteLocalMessageForConv:kConv convSeq:99 advancingSyncedConvSeq:50];
    XCTAssertEqual([_db syncedConvSeqForConv:kConv], 50);
    BOOL again = [_db deleteLocalMessageForConv:kConv convSeq:99 advancingSyncedConvSeq:10];
    XCTAssertFalse(again, @"位点没前进、行也不存在：不该报告「有改动」，否则调用方会白发一次刷新通知");
}

#pragma mark - applyMsgOp 联动会话摘要

/// 撤回的恰是会话列表当前指着的那条：摘要翻 last_recalled，并**把图说一并抹掉**（撤回的图说文字不得残留在预览里）。
- (void)test_撤回最新一条联动摘要且抹掉图说 {
    IMMessageModel *img = [self incoming:1 conv:kConv content:@"/img.jpg" type:@"image"];
    img.caption = @"私密图说";
    [_db saveIncomingMessage:img advancingSyncedConvSeq:1];
    XCTAssertEqualObjects([self conv:kConv].lastCaption, @"私密图说");
    XCTAssertTrue([_db applyMsgOpForConv:kConv targetConvSeq:1 recalledAt:2000 recalledBy:@"peer" editedAt:0 pinnedAt:0
                              newContent:nil advancingSyncedConvSeq:0]);
    IMConversation *c = [self conv:kConv];
    XCTAssertTrue(c.lastRecalled);
    XCTAssertTrue(c.lastCaption.length == 0);
    XCTAssertEqual([self row:1].recalledAt, 2000);
    XCTAssertEqualObjects([self row:1].recalledBy, @"peer");
}

/// 撤回的不是最新一条：摘要不能动（否则列表预览会变成「撤回了一条消息」，而最新一条其实好好的）。
- (void)test_撤回非最新一条不动摘要 {
    [self put:1 content:@"old"]; [self put:2 content:@"new"];
    [_db applyMsgOpForConv:kConv targetConvSeq:1 recalledAt:2000 recalledBy:@"peer" editedAt:0 pinnedAt:0
                newContent:nil advancingSyncedConvSeq:0];
    XCTAssertFalse([self conv:kConv].lastRecalled);
    XCTAssertEqualObjects([self conv:kConv].lastContent, @"new");
    XCTAssertEqual([self row:1].recalledAt, 2000);
}

/// 编辑最新一条：摘要正文同步；编辑非最新一条：摘要不动。
- (void)test_编辑联动摘要仅限最新一条 {
    [self put:1 content:@"old"]; [self put:2 content:@"new"];
    [_db applyMsgOpForConv:kConv targetConvSeq:1 recalledAt:0 recalledBy:nil editedAt:3000 pinnedAt:0
                newContent:@"old-edited" advancingSyncedConvSeq:0];
    XCTAssertEqualObjects([self conv:kConv].lastContent, @"new");
    [_db applyMsgOpForConv:kConv targetConvSeq:2 recalledAt:0 recalledBy:nil editedAt:3001 pinnedAt:0
                newContent:@"new-edited" advancingSyncedConvSeq:0];
    XCTAssertEqualObjects([self conv:kConv].lastContent, @"new-edited");
    XCTAssertEqualObjects([self row:2].content, @"new-edited");
    XCTAssertEqual([self row:2].editedAt, 3001);
}

/// 编辑必须同时清掉 mention_spans：偏移相对原文，正文一改全错位；只清内存不清库，重启后旧片段会回来
/// 配上新正文，新正文碰巧同偏移有 `@` 就会高亮并点进另一个人的资料页。
- (void)test_编辑清掉库里的mentionSpans {
    IMMessageModel *m = [self incoming:1 conv:kConv content:@"hi @bob" type:@"text"];
    IMMentionSpan *s = [[IMMentionSpan alloc] init]; s.range = NSMakeRange(3, 4); s.uid = @"bob";
    m.mentionSpans = @[s];
    [_db saveIncomingMessage:m advancingSyncedConvSeq:1];
    XCTAssertEqual([self row:1].mentionSpans.count, 1u);
    [_db applyMsgOpForConv:kConv targetConvSeq:1 recalledAt:0 recalledBy:nil editedAt:3000 pinnedAt:0
                newContent:@"yo @eve" advancingSyncedConvSeq:0];
    XCTAssertTrue([self row:1].mentionSpans.count == 0, @"重新读库后片段必须已清空");
}

/// 置顶：>0 置顶，<0 取消（写回 0），0 不改。取消置顶与置顶共用 op，若沿用「0=不改」就永远落不了地。
- (void)test_置顶三态 {
    [self put:1 content:@"a"];
    [_db applyMsgOpForConv:kConv targetConvSeq:1 recalledAt:0 recalledBy:nil editedAt:0 pinnedAt:7000 newContent:nil advancingSyncedConvSeq:0];
    XCTAssertEqual([self row:1].pinnedAt, 7000);
    // 0 = 不改，且因为没有任何字段要改，整个操作 NO（不推进位点）。
    XCTAssertFalse([_db applyMsgOpForConv:kConv targetConvSeq:1 recalledAt:0 recalledBy:nil editedAt:0 pinnedAt:0 newContent:nil advancingSyncedConvSeq:0]);
    XCTAssertEqual([self row:1].pinnedAt, 7000);
    XCTAssertTrue([_db applyMsgOpForConv:kConv targetConvSeq:1 recalledAt:0 recalledBy:nil editedAt:0 pinnedAt:-1 newContent:nil advancingSyncedConvSeq:0]);
    XCTAssertEqual([self row:1].pinnedAt, 0);
}

/// 无效入参 NO；带位点时与状态同事务推进（取较大值）。
- (void)test_消息操作的入参与位点推进 {
    [self put:1 content:@"a"];
    XCTAssertFalse([_db applyMsgOpForConv:@"" targetConvSeq:1 recalledAt:1 recalledBy:nil editedAt:0 pinnedAt:0 newContent:nil advancingSyncedConvSeq:0]);
    XCTAssertFalse([_db applyMsgOpForConv:kConv targetConvSeq:0 recalledAt:1 recalledBy:nil editedAt:0 pinnedAt:0 newContent:nil advancingSyncedConvSeq:0]);
    XCTAssertTrue([_db applyMsgOpForConv:kConv targetConvSeq:1 recalledAt:2000 recalledBy:@"p" editedAt:0 pinnedAt:0 newContent:nil advancingSyncedConvSeq:40]);
    XCTAssertEqual([self->_db syncedConvSeqForConv:kConv], 40);
    [_db applyMsgOpForConv:kConv targetConvSeq:1 recalledAt:2001 recalledBy:@"p" editedAt:0 pinnedAt:0 newContent:nil advancingSyncedConvSeq:5];
    XCTAssertEqual([self->_db syncedConvSeqForConv:kConv], 40, @"位点只增不减");
}

#pragma mark - 整体已读 / 设置 / 备注 / 未读总数

/// 用户显式「设为已读」：未读与「@我」红字一并清零，读位点只增不减。
- (void)test_整体已读清未读与at我_位点只增不减 {
    IMConversation *c = [IMConversation new];
    c.convID = kConv; c.isGroup = NO; c.peer = @"u_b"; c.peerNickname = @"b";
    c.lastContent = @"@你"; c.lastContentType = @"text"; c.latestConvSeq = 3; c.unread = 3; c.mentionUnread = YES;
    [_db replaceCachedConversations:@[c]];
    XCTAssertEqual([self conv:kConv].unread, 3);
    XCTAssertTrue([self conv:kConv].mentionUnread, @"夹具：先确认「@我」确实亮着，下面的断言才不是空转");
    [_db markConversationFullyRead:kConv upToConvSeq:3];
    XCTAssertEqual([self conv:kConv].unread, 0);
    XCTAssertFalse([self conv:kConv].mentionUnread);
    XCTAssertEqual([self conv:kConv].readSeq, 3);
    [_db markConversationFullyRead:kConv upToConvSeq:1];
    XCTAssertEqual([self conv:kConv].readSeq, 3);
    [_db markConversationFullyRead:kConv upToConvSeq:0]; // 无效：无操作
    XCTAssertEqual([self conv:kConv].readSeq, 3);
}

/// 本地设置四项一起写；**备注不受影响**（备注与三开关解耦，反之亦然）。
- (void)test_本地设置与备注互不影响 {
    [self put:1 content:@"x"];
    [_db applyCachedRemarkForConversation:kConv remark:@"老板"];
    [_db applyCachedSettingsForConversation:kConv pinnedAt:9000 muted:YES muteUntil:123456 markedUnread:YES];
    IMConversation *c = [self conv:kConv];
    XCTAssertEqual(c.pinnedAt, 9000);
    XCTAssertTrue(c.muted);
    XCTAssertEqual(c.muteUntil, 123456);
    XCTAssertTrue(c.markedUnread);
    XCTAssertEqualObjects(c.remark, @"老板", @"改设置不能清掉备注");
    [_db applyCachedRemarkForConversation:kConv remark:nil];
    c = [self conv:kConv];
    XCTAssertTrue(c.remark.length == 0);
    XCTAssertEqual(c.pinnedAt, 9000, @"改备注不能动设置");
    XCTAssertEqual(c.muteUntil, 123456);
}

/// 会话不存在时设置/备注/整体已读都**不凭空建行**（等下一次权威列表补齐）。
- (void)test_会话不存在时不凭空建行 {
    [_db applyCachedSettingsForConversation:@"ghost" pinnedAt:1 muted:YES muteUntil:2 markedUnread:YES];
    [_db applyCachedRemarkForConversation:@"ghost" remark:@"x"];
    [_db markConversationFullyRead:@"ghost" upToConvSeq:5];
    XCTAssertNil([self conv:@"ghost"]);
}

/// 未读总数：各会话之和；排除某会话；排除参数为空等于不排除。
- (void)test_未读总数 {
    [self put:1 content:@"x"]; [self put:2 content:@"y"];
    [_db saveIncomingMessage:[self incoming:1 conv:kOther content:@"z" type:@"text"] advancingSyncedConvSeq:1];
    XCTAssertEqual([_db totalUnreadExcludingConv:nil], 3);
    XCTAssertEqual([_db totalUnreadExcludingConv:@""], 3);
    XCTAssertEqual([_db totalUnreadExcludingConv:kConv], 1);
    XCTAssertEqual([_db totalUnreadExcludingConv:@"nope"], 3);
}

@end
