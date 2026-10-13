#import <XCTest/XCTest.h>

#import "IMAccountIdentity.h"
#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMDatabase+Ranges.h"
#import "IMGroupInfo.h"
#import "IMLocalization.h"
#import "IMMessageModel.h"
#import "IMRemarkStore.h"

/// 系统消息结构化分段：解析 / 落库往返 / 隐私口径。
/// 分段来自服务端，必须脏数据安全——解析不出就回退整句（= 历史系统消息的老样子），
/// 绝不能因为一条脏消息把消息列表读不出来。与 Web `src/sysSegments.ts` 同语义。
@interface IMSysSegmentTests : XCTestCase
@end

@implementation IMSysSegmentTests {
    NSMutableArray<NSURL *> *_tempDBURLs; // freshDatabaseForOwner: 建的临时库，tearDown 删掉
}

- (void)tearDown {
    [IMLocalization.shared setPreference:IMLanguagePrefZhHans]; // 还原 bootstrap 默认
    for (NSURL *url in _tempDBURLs) {
        for (NSString *suffix in @[@"", @"-wal", @"-shm"]) {
            NSURL *f = [NSURL fileURLWithPath:[url.path stringByAppendingString:suffix]];
            [NSFileManager.defaultManager removeItemAtURL:f error:NULL];
        }
    }
    [_tempDBURLs removeAllObjects];
    [super tearDown];
}

- (IMDatabase *)freshDatabaseForOwner:(NSString *)owner {
    NSString *name = [NSString stringWithFormat:@"im-friendsys-%@.sqlite", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    if (!_tempDBURLs) { _tempDBURLs = [NSMutableArray array]; }
    [_tempDBURLs addObject:url];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:url];
    [db useOwnerUserID:owner];
    return db;
}

/// 单聊 friend_accepted：sender 为空、无分段。会话行预览按 sys_event 随 App 语言本地化，不落到 lastContent 中文兜底。
- (void)testConversationPreviewRendersFriendAcceptedLocalized {
    IMConversation *c = [IMConversation new];
    c.convID = @"u_1001_u_1002"; c.isGroup = NO;
    c.lastContentType = @"system";
    c.lastFrom = @"";
    c.lastSysEvent = @"friend_accepted";
    c.lastContent = @"你们已成为好友，现在可以开始聊天了";
    XCTAssertEqualObjects([c lastPreviewTextForSelfUID:@"1001"], @"你们已成为好友，现在可以开始聊天了");
    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    XCTAssertEqualObjects([c lastPreviewTextForSelfUID:@"1001"], @"You are now friends. You can start chatting.");
    c.lastSysEvent = @"some_future_event";
    XCTAssertEqualObjects([c lastPreviewTextForSelfUID:@"1001"], c.lastContent, @"未知事件回退 content");
}

/// 会话列表里原本没有该会话、new_msg 先到：本地创建壳行（peer 由 convID 推出）、置为最新、不计未读；
/// 之后对方真消息照常 +1，标已读时不会被系统消息多扣。
- (void)testEmptySenderFriendAcceptedCreatesConversationWithoutUnread {
    IMDatabase *db = [self freshDatabaseForOwner:@"1001"];
    IMMessageModel *sys = [IMMessageModel new];
    sys.convID = @"u_1001_u_1002";
    sys.serverMsgID = @"sys-friend-1";
    sys.contentType = @"system";
    sys.from = @"";
    sys.content = @"你们已成为好友，现在可以开始聊天了";
    sys.sysEvent = @"friend_accepted";
    sys.convSeq = 1;
    sys.timestamp = 1000;
    XCTAssertTrue([db saveIncomingMessage:sys advancingSyncedConvSeq:0]);

    IMConversation *c = [db cachedConversationWithID:@"u_1001_u_1002"];
    XCTAssertNotNil(c, @"会话行必须被创建，才会出现在列表");
    XCTAssertFalse(c.isGroup);
    XCTAssertEqualObjects(c.peer, @"1002", @"peer 由 convID 推出，不能依赖 sender");
    XCTAssertEqual(c.unread, 0, @"系统消息不计未读");
    XCTAssertEqualObjects(c.lastSysEvent, @"friend_accepted");
    XCTAssertEqual(c.timestamp, 1000);
    XCTAssertEqual([db countIncomingInConv:@"u_1001_u_1002" afterConvSeq:0], 0, @"↓N 不把系统消息当对方消息");

    IMMessageModel *text = [IMMessageModel new];
    text.convID = @"u_1001_u_1002"; text.serverMsgID = @"m-2"; text.contentType = @"text";
    text.from = @"1002"; text.to = @"1001"; text.content = @"hi"; text.convSeq = 2; text.timestamp = 2000;
    XCTAssertTrue([db saveIncomingMessage:text advancingSyncedConvSeq:0]);
    XCTAssertEqual([db cachedConversationWithID:@"u_1001_u_1002"].unread, 1);

    // 读到 seq=2：系统消息(seq=1)与真消息(seq=2)都在区间内，只应扣 1。
    [db markConversation:@"u_1001_u_1002" readUpToConvSeq:2];
    XCTAssertEqual([db cachedConversationWithID:@"u_1001_u_1002"].unread, 0);
}

/// 已有未读时标已读到系统消息之后：区间里的系统消息不能多扣（否则吃掉区间之外的真未读）。
- (void)testMarkReadDoesNotOverDecrementForSystemMessage {
    IMDatabase *db = [self freshDatabaseForOwner:@"1001"];
    NSString *conv = @"u_1001_u_1002";
    void (^put)(NSString *, NSString *, NSString *, int64_t) = ^(NSString *sid, NSString *type, NSString *from, int64_t seq) {
        IMMessageModel *m = [IMMessageModel new];
        m.convID = conv; m.serverMsgID = sid; m.contentType = type; m.from = from; m.to = @"1001";
        m.content = @"x"; m.convSeq = seq; m.timestamp = seq * 100;
        if ([type isEqualToString:@"system"]) { m.sysEvent = @"friend_accepted"; }
        XCTAssertTrue([db saveIncomingMessage:m advancingSyncedConvSeq:0]);
    };
    put(@"a", @"text", @"1002", 1);
    put(@"s", @"system", @"", 2);
    put(@"b", @"text", @"1002", 3);
    XCTAssertEqual([db cachedConversationWithID:conv].unread, 2);
    [db markConversation:conv readUpToConvSeq:2]; // 区间 (0,2]：1 条真消息 + 1 条系统消息
    XCTAssertEqual([db cachedConversationWithID:conv].unread, 1, @"seq=3 仍未读");
}

- (void)testParsesNamedAndPlainSegments {
    NSArray<IMSysSegment *> *segs = [IMSysSegment segmentsFromArray:@[
        @{ @"uid": @"1001", @"text": @"张三" }, @{ @"text": @" 邀请 " },
        @{ @"uid": @"1002", @"text": @"李四" }, @{ @"text": @" 加入群聊" },
    ]];
    XCTAssertEqual(segs.count, 4u);
    XCTAssertEqualObjects(segs[0].uid, @"1001");
    XCTAssertEqualObjects(segs[0].text, @"张三");
    XCTAssertNil(segs[1].uid, @"固定文案段不该带 uid（不会挂点击）");
    XCTAssertEqualObjects(segs[3].text, @" 加入群聊");
}

- (void)testDirtyInputDegradesToNoSegments {
    XCTAssertNil([IMSysSegment segmentsFromArray:nil]);
    XCTAssertNil([IMSysSegment segmentsFromArray:@[]]);
    XCTAssertNil([IMSysSegment segmentsFromArray:(NSArray *)@"张三 邀请 李四"], @"非数组不该崩");
    // 注意：数组字面量里的逗号会被预处理器当作宏参数分隔符，故先落到局部变量再断言。
    NSArray *allDirty = @[@42, @{ @"uid": @"x" }, @{ @"text": @"" }];
    XCTAssertNil([IMSysSegment segmentsFromArray:allDirty], @"一段都解析不出应回退整句渲染");
    // uid 非字符串/空串 → 退化成不可点的固定文案段（不会挂错跳转）。
    NSArray *badUIDs = @[@{ @"uid": @42, @"text": @"张三" }, @{ @"uid": @"", @"text": @"李四" }];
    NSArray<IMSysSegment *> *segs = [IMSysSegment segmentsFromArray:badUIDs];
    XCTAssertEqual(segs.count, 2u);
    XCTAssertNil(segs[0].uid);
    XCTAssertNil(segs[1].uid);
}

/// 分段必须落库：否则重进会话/冷启动读本地库时分段丢失，系统消息退回"显真实昵称、名字不可点"，
/// 与刚收到那一刻不一致（同一条消息两副面孔）。
- (void)testSegmentsSurviveDatabaseRoundTrip {
    NSString *name = [NSString stringWithFormat:@"im-sysseg-%@.sqlite", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];

    IMDatabase *writer = [[IMDatabase alloc] initWithFileURL:url];
    [writer useOwnerUserID:@"alice"];
    IMMessageModel *m = [IMMessageModel new];
    m.convID = @"g_1";
    m.serverMsgID = @"sys-1";
    m.contentType = @"system";
    m.content = @"张三 邀请 李四 加入群聊";
    m.convSeq = 7;
    m.timestamp = 123456789;
    m.sysSegments = [IMSysSegment segmentsFromArray:@[
        @{ @"uid": @"1001", @"text": @"张三" }, @{ @"text": @" 邀请 " },
        @{ @"uid": @"1002", @"text": @"李四" }, @{ @"text": @" 加入群聊" },
    ]];
    [writer saveMessage:m];

    IMDatabase *reader = [[IMDatabase alloc] initWithFileURL:url];
    [reader useOwnerUserID:@"alice"];
    IMMessageModel *loaded = [reader messagesForConv:@"g_1"].firstObject;
    XCTAssertEqualObjects(loaded.content, @"张三 邀请 李四 加入群聊");
    XCTAssertEqual(loaded.sysSegments.count, 4u);
    XCTAssertEqualObjects(loaded.sysSegments[0].uid, @"1001");
    XCTAssertEqualObjects(loaded.sysSegments[2].text, @"李四");
    XCTAssertNil(loaded.sysSegments[1].uid);

    // 无分段的历史消息：读回也是空，渲染回退 content 整句。
    IMMessageModel *old = [IMMessageModel new];
    old.convID = @"g_1"; old.serverMsgID = @"sys-0"; old.contentType = @"system";
    old.content = @"李四 加入了群聊"; old.convSeq = 6; old.timestamp = 1;
    [writer saveMessage:old];
    IMDatabase *reader2 = [[IMDatabase alloc] initWithFileURL:url];
    [reader2 useOwnerUserID:@"alice"];
    for (IMMessageModel *x in [reader2 messagesForConv:@"g_1"]) {
        if ([x.serverMsgID isEqualToString:@"sys-0"]) { XCTAssertNil(x.sysSegments); }
    }

    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

/// 分段里的字面是**公开昵称**——这条消息全群都收得到。备注只在收端按 uid 重解析时才出现。
- (void)testSegmentTextIsPublicNameNotRemark {
    [IMRemarkStore.sharedStore applyRemark:@"老王" forUser:@"1002"];
    NSArray<IMSysSegment *> *segs = [IMSysSegment segmentsFromArray:@[@{ @"uid": @"1002", @"text": @"李四" }]];
    XCTAssertEqualObjects(segs[0].text, @"李四", @"服务端下发的字面不该受本机备注影响");
    // 本机渲染时才换成备注（IMSystemCell 用 uid 走 IMRemarkStore 这一步）。
    XCTAssertEqualObjects([IMRemarkStore.sharedStore displayNameForUser:segs[0].uid fallback:segs[0].text], @"老王");
    [IMRemarkStore.sharedStore applyRemark:@"" forUser:@"1002"];
}

/// 会话列表预览也要按本机显示名渲染系统消息里的名字——否则列表显真名、点进会话显备注，
/// 同一句话两副面孔（用户实测反馈的正是这条）。
- (void)testConversationPreviewLocalizesSystemMessageNames {
    [IMRemarkStore.sharedStore applyRemark:@"二两肉" forUser:@"1002"];

    IMConversation *c = [IMConversation new];
    c.convID = @"g_1"; c.isGroup = YES; c.name = @"技术群";
    c.lastContentType = @"system";
    c.lastContent = @"张三 将 李四 取消管理员身份"; // 服务端拼好的整句（公开昵称）
    c.lastSysSegments = [IMSysSegment segmentsFromArray:@[
        @{ @"uid": @"1001", @"text": @"张三" }, @{ @"text": @" 将 " },
        @{ @"uid": @"1002", @"text": @"李四" }, @{ @"text": @" 取消管理员身份" },
    ]];
    XCTAssertEqualObjects(c.lastPreviewText, @"张三 将 二两肉 取消管理员身份");

    // 历史系统消息（无分段）→ 回退整句，名字保持服务端当时的昵称。
    c.lastSysSegments = nil;
    XCTAssertEqualObjects(c.lastPreviewText, @"张三 将 李四 取消管理员身份");

    [IMRemarkStore.sharedStore applyRemark:@"" forUser:@"1002"];
}

/// 「我」是这套渲染里唯一的硬规则，且**聊天页系统行与会话列表预览共用**——漂了就会一处显「我」、
/// 一处显自己的昵称，同一句话两副面孔（用户 2026-08-30 反馈：自己被显示成「用户1002」）。
- (void)testSelfSegmentRendersAsWo {
    XCTAssertEqualObjects([IMSysSegment localNameForUID:@"1002" selfUID:@"1002" groupNickname:@"群里的我" fallback:@"用户1002"],
                          @"我", @"是我自己就显「我」，群昵称/备注都不该盖过它");
    XCTAssertEqualObjects([IMSysSegment localNameForUID:@"3001" selfUID:@"1002" groupNickname:@"小三" fallback:@"用户3001"],
                          @"小三", @"别人：群昵称优先于服务端字面");
    XCTAssertEqualObjects([IMSysSegment localNameForUID:@"3001" selfUID:@"1002" groupNickname:nil fallback:@"用户3001"],
                          @"用户3001");
    XCTAssertEqualObjects([IMSysSegment localNameForUID:@"1002" selfUID:nil groupNickname:nil fallback:@"用户1002"],
                          @"用户1002", @"拿不到当前账号时不做替换，宁可显真名也不能把别人显示成「我」");

    // 备注优先于群昵称与字面（但仍在「我」之下）。
    [IMRemarkStore.sharedStore applyRemark:@"二两肉" forUser:@"3001"];
    XCTAssertEqualObjects([IMSysSegment localNameForUID:@"3001" selfUID:@"1002" groupNickname:@"小三" fallback:@"用户3001"],
                          @"二两肉");
    [IMRemarkStore.sharedStore applyRemark:@"" forUser:@"3001"];
}

/// 会话列表预览走同一口径：我自己那段显「我」。
- (void)testConversationPreviewRendersSelfAsWo {
    IMConversation *c = [IMConversation new];
    c.convID = @"g_1"; c.isGroup = YES; c.name = @"技术群";
    c.lastContentType = @"system";
    c.lastContent = @"用户1002 将 用户3001 移出群聊";
    c.lastSysSegments = [IMSysSegment segmentsFromArray:@[
        @{ @"uid": @"1002", @"text": @"用户1002" }, @{ @"text": @" 将 " },
        @{ @"uid": @"3001", @"text": @"用户3001" }, @{ @"text": @" 移出群聊" },
    ]];
    XCTAssertEqualObjects([c lastPreviewTextForSelfUID:@"1002"], @"我 将 用户3001 移出群聊");
    XCTAssertEqualObjects(c.lastPreviewText, @"用户1002 将 用户3001 移出群聊", @"不传 selfUID 即不替换（老口径）");
}

/// 系统通知单聊（sender=777000）的会话列表预览：走结构化 sys_event，取聊天页气泡正文
/// （IMTextForNoticeSysEvent）的首行摘要，不落到 lastContent（服务端落库时按发送方
/// 当时语言冻结的整句）——聊天页内气泡本身已修过，此前只有会话列表这一行残留。2026-09-22 补。
- (void)testConversationPreviewRendersSystemNoticeFirstLine {
    IMConversation *c = [IMConversation new];
    c.convID = @"u_1002_777000"; c.isGroup = NO;
    c.lastContentType = @"text";
    c.lastFrom = IMSystemUserID;
    c.lastSysEvent = @"password_changed";
    c.lastSysArgs = @{ @"at": @"2026-09-22T10:30:00Z" };
    c.lastContent = @"（老服务端落库整句，本测试验证走的是新分支而非这里）";
    NSString *preview = [c lastPreviewTextForSelfUID:@"1002"];
    XCTAssertTrue([preview hasPrefix:@"你的账号密码已于"], @"取的是通知正文首行，不是 lastContent 兜底");
    XCTAssertTrue([preview hasSuffix:@"修改成功。"]);
    XCTAssertFalse([preview containsString:@"\n"], @"会话列表只显首行摘要，不带完整多行正文");
}

/// 未识别 / 空 sys_event（存量老消息，服务端当时没存结构化字段）回退 lastContent，行为不变。
- (void)testConversationPreviewSystemNoticeFallsBackToContentWhenUnrecognized {
    IMConversation *c = [IMConversation new];
    c.convID = @"u_1002_777000"; c.isGroup = NO;
    c.lastContentType = @"text";
    c.lastFrom = IMSystemUserID;
    c.lastSysEvent = nil;
    c.lastContent = @"你的账号密码已修改";
    XCTAssertEqualObjects([c lastPreviewTextForSelfUID:@"1002"], @"你的账号密码已修改");
}

/// 群成员的两个名字必须泾渭分明：displayName=群内公开名（会进 @token 等发出去的内容），
/// localDisplayName=本机显示名（备注优先）。写反就是把私房名发出去。
- (void)testGroupMemberPublicVsLocalName {
    IMGroupMember *m = [IMGroupMember new];
    m.userID = @"1002";
    m.nickname = @"李四";
    m.groupNickname = @"群里的李四";
    XCTAssertEqualObjects(m.displayName, @"群里的李四", @"公开名：群昵称优先，与备注无关");
    XCTAssertEqualObjects(m.localDisplayName, @"群里的李四", @"没设备注时两者一致");

    [IMRemarkStore.sharedStore applyRemark:@"二两肉" forUser:@"1002"];
    XCTAssertEqualObjects(m.displayName, @"群里的李四", @"设了备注**也不能**影响公开名");
    XCTAssertEqualObjects(m.localDisplayName, @"二两肉", @"本机显示名走备注");
    [IMRemarkStore.sharedStore applyRemark:@"" forUser:@"1002"];
    XCTAssertEqualObjects(m.localDisplayName, @"群里的李四", @"清除备注后回落公开名");
}

@end
