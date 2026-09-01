//  IMMentionTests.m
//  群 @提及 + 会话 mention_unread 的纯逻辑测试（M4-8）。
//  app-hosted 测试，符号由宿主 App 提供；头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Models/IMGroupInfo.h"
#import "../IMProgram/Models/IMMessageModel.h"

// 聊天消息的文件级纯逻辑（@提及 token 判定 / 未读口径），符号由宿主 App 提供。
#import "../IMProgram/Modules/Chat/IMChatMessageLogic.h"

@interface IMMentionTests : XCTestCase
@end

@implementation IMMentionTests

#pragma mark - 会话快照解析

/// mention_unread 随会话列表下发，缺省/脏值一律按 NO（老服务端不带该键时不能误报红字）。
- (void)testParsesMentionUnread {
    NSArray<IMConversation *> *list = [IMConversation conversationsFromArray:@[
        @{ @"conv_id": @"g_1", @"is_group": @YES, @"mention_unread": @YES },
        @{ @"conv_id": @"g_2", @"is_group": @YES, @"mention_unread": @NO },
        @{ @"conv_id": @"g_3", @"is_group": @YES
        },                                                              // 缺该键（老服务端）
        @{ @"conv_id": @"g_4", @"is_group": @YES, @"mention_unread": @"yes" }, // 脏类型
    ]];
    XCTAssertEqual(list.count, 4u);
    XCTAssertTrue(list[0].mentionUnread);
    XCTAssertFalse(list[1].mentionUnread);
    XCTAssertFalse(list[2].mentionUnread, @"缺 mention_unread 键应按 NO，不能误显红字");
    XCTAssertFalse(list[3].mentionUnread, @"字符串脏值不应被当作 YES");
}

#pragma mark - 免打扰破例

/// 会话列表未读徽标取色规则（与 IMConversationListViewController 一致）：
/// 免打扰置灰，但**被 @ 时破例回到高亮**——免打扰只压普通消息，不压 @我。
static BOOL badgeIsMuted(IMConversation *c) { return c.muted && !c.mentionUnread; }

- (void)testMentionBreaksThroughMute {
    IMConversation *plain = [IMConversation new];
    plain.muted = NO; plain.mentionUnread = NO;
    XCTAssertFalse(badgeIsMuted(plain), @"普通会话：高亮");

    IMConversation *muted = [IMConversation new];
    muted.muted = YES; muted.mentionUnread = NO;
    XCTAssertTrue(badgeIsMuted(muted), @"免打扰且无 @：置灰");

    IMConversation *mutedMentioned = [IMConversation new];
    mutedMentioned.muted = YES; mutedMentioned.mentionUnread = YES;
    XCTAssertFalse(badgeIsMuted(mutedMentioned), @"免打扰但被 @：必须破例回到高亮");
}

#pragma mark - @所有人权限

/// 「@所有人」仅群主/管理员可见可点（普通成员整行不渲染）。
/// 与 IMMentionPickerViewController 的 _canMentionAll 同一判据。
static BOOL canMentionAll(IMGroupRole role) {
    return role == IMGroupRoleOwner || role == IMGroupRoleAdmin;
}

- (void)testMentionAllVisibleOnlyToAdmins {
    XCTAssertTrue(canMentionAll(IMGroupRoleOwner));
    XCTAssertTrue(canMentionAll(IMGroupRoleAdmin));
    XCTAssertFalse(canMentionAll(IMGroupRoleMember), @"普通成员不该看到 @所有人");
}

/// 角色字符串解析（脏数据按 member 兜底）——决定 @所有人 是否出现，错判会造成越权 UI。
- (void)testGroupRoleParsing {
    XCTAssertEqual(IMGroupRoleFromString(@"owner"), IMGroupRoleOwner);
    XCTAssertEqual(IMGroupRoleFromString(@"admin"), IMGroupRoleAdmin);
    XCTAssertEqual(IMGroupRoleFromString(@"member"), IMGroupRoleMember);
    XCTAssertEqual(IMGroupRoleFromString(@"root"), IMGroupRoleMember, @"未知角色必须按最小权限兜底");
    XCTAssertEqual(IMGroupRoleFromString(nil), IMGroupRoleMember);
}

#pragma mark - @token 边界（防前缀误命中）

/// 必须按 token 边界判定：昵称互为前缀时，裸子串会把没被 @ 的人也算进 mentions，
/// 让他收到一条穿透免打扰的错误强提醒。与 Web containsMentionToken 逐条对齐。
- (void)testMentionTokenRequiresBoundary {
    XCTAssertTrue(IMChatTextContainsMentionToken(@"@小美 在吗", @"小美"));
    XCTAssertTrue(IMChatTextContainsMentionToken(@"在吗 @小美", @"小美"), @"到字符串结尾也算完整 token");
    XCTAssertTrue(IMChatTextContainsMentionToken(@"@小美\n换行", @"小美"));

    XCTAssertFalse(IMChatTextContainsMentionToken(@"@小美丽 开会", @"小美"),
                   @"回归：@小美丽 不得把小美也算成被提及");
    XCTAssertTrue(IMChatTextContainsMentionToken(@"@小美丽 开会", @"小美丽"));
    XCTAssertTrue(IMChatTextContainsMentionToken(@"@小美丽 和 @小美 都来", @"小美"),
                  @"长名在前时短名仍应命中自己的 token");

    XCTAssertFalse(IMChatTextContainsMentionToken(@"", @"小美"));
    XCTAssertFalse(IMChatTextContainsMentionToken(@"@小美", @""));
    XCTAssertFalse(IMChatTextContainsMentionToken(nil, @"小美"));
}

/// @所有人 同样按边界判定（「@所有人们」不应触发全员强提醒）。
- (void)testMentionAllTokenBoundary {
    XCTAssertTrue(IMChatTextContainsMentionToken(@"@所有人 开会", @"所有人"));
    XCTAssertFalse(IMChatTextContainsMentionToken(@"@所有人们 好", @"所有人"));
}

#pragma mark - 未读口径

/// 未读分割线的定位必须与服务端 unreadCount 同口径，否则分割线会落在不计数的行上。
- (void)testContentTypeCountsAsUnread {
    XCTAssertFalse(IMContentTypeCountsAsUnread(@"system"), @"群系统消息不计未读");
    XCTAssertFalse(IMContentTypeCountsAsUnread(@"msg_op"), @"撤回/编辑/置顶事件行不计未读");
    XCTAssertTrue(IMContentTypeCountsAsUnread(@"text"));
    XCTAssertTrue(IMContentTypeCountsAsUnread(@"image"));
    XCTAssertTrue(IMContentTypeCountsAsUnread(nil), @"类型未知按普通消息处理（宁可多算，不漏红点）");
}

#pragma mark - @ 片段（mention_spans）

// 这套的全部意义是**收端不必有群成员表**（超级群不下发），所以测的重点是：
// 偏移口径对不对（emoji！）、片段对不上时会不会安全跳过。与 Web mention.test.ts 逐条对齐。

/// 发送侧扫描：偏移能被原样切回来，且 NSRange 直接可用（NSString 天生 UTF-16）。
- (void)testScanMentionSpansRoundTrip {
    NSString *text = @"@小明 和 @小红 明天开会";
    NSArray<IMMentionSpan *> *spans = IMChatScanMentionSpans(text, @{ @"小明": @"u1", @"小红": @"u2" });
    XCTAssertEqual(spans.count, 2u);
    XCTAssertEqualObjects([text substringWithRange:spans[0].range], @"@小明");
    XCTAssertEqualObjects(spans[0].uid, @"u1");
    XCTAssertEqualObjects([text substringWithRange:spans[1].range], @"@小红");
    XCTAssertEqualObjects(spans[1].uid, @"u2");
}

/// **偏移单位是 UTF-16 码元**：emoji 在前也不错位。
/// 🎉 占 2 个码元；若哪天有人"为了直观"改成码点，这条会红。
- (void)testScanMentionSpansOffsetsAreUTF16 {
    NSString *text = @"🎉@小明 你好";
    NSArray<IMMentionSpan *> *spans = IMChatScanMentionSpans(text, @{ @"小明": @"u1" });
    XCTAssertEqual(spans.count, 1u);
    XCTAssertEqual(spans[0].range.location, 2u, @"UTF-16 偏移应为 2（码点口径会算成 1）");
    XCTAssertEqualObjects([text substringWithRange:spans[0].range], @"@小明");
}

/// token 边界与 IMChatTextContainsMentionToken 同规则：@小美 不误命中 @小美丽（长名优先）。
- (void)testScanMentionSpansLongestNameWins {
    NSArray<IMMentionSpan *> *spans = IMChatScanMentionSpans(@"@小美丽 你好", @{ @"小美": @"u1", @"小美丽": @"u2" });
    XCTAssertEqual(spans.count, 1u);
    XCTAssertEqualObjects(spans[0].uid, @"u2");
}

/// @所有人 的 uid 为 nil（只高亮不可点，与服务端「空 uid 要求 mention_all」对齐）。
- (void)testScanMentionSpansMentionAllHasNoUID {
    NSArray<IMMentionSpan *> *spans = IMChatScanMentionSpans(@"@所有人 集合", @{ @"所有人": @"" });
    XCTAssertEqual(spans.count, 1u);
    XCTAssertNil(spans[0].uid);
}

/// 渲染侧校验：与本文对不上的片段一律跳过——编辑过的老消息、越界、位置不是 @、重叠。
/// 全跳完调用方就回落到按昵称扫文本的老路，**绝不能拿错位的偏移去切字符串**（会切出乱码或崩）。
- (void)testValidMentionSpansRejectsMismatch {
    NSString *edited = @"改成完全不同的一句话";
    IMMentionSpan *stale = [IMMentionSpan new];
    stale.range = NSMakeRange(0, 3); stale.uid = @"u1";
    XCTAssertEqual(IMChatValidMentionSpans(edited, @[stale]).count, 0u, @"位置不是 @ → 跳过");

    IMMentionSpan *oob = [IMMentionSpan new];
    oob.range = NSMakeRange(0, 999); oob.uid = @"u1";
    XCTAssertEqual(IMChatValidMentionSpans(@"@小明", @[oob]).count, 0u, @"越界 → 跳过");

    IMMentionSpan *a = [IMMentionSpan new]; a.range = NSMakeRange(0, 5); a.uid = @"u1";
    IMMentionSpan *b = [IMMentionSpan new]; b.range = NSMakeRange(2, 3); b.uid = @"u2";
    NSArray<IMMentionSpan *> *kept = IMChatValidMentionSpans(@"@小明小红 开会", @[a, b]);
    XCTAssertEqual(kept.count, 1u, @"重叠只留先到的");
    XCTAssertEqualObjects(kept[0].uid, @"u1");
}

/// 折叠截断（气泡里只显前缀）后，落在前缀里的片段仍然有效——这是 iOS 折叠渲染必须成立的前提。
- (void)testValidMentionSpansSurvivePrefixTruncation {
    NSString *full = [@"@小明 " stringByPaddingToLength:60 withString:@"字" startingAtIndex:0];
    NSArray<IMMentionSpan *> *spans = IMChatScanMentionSpans(full, @{ @"小明": @"u1" });
    NSString *shown = [full substringToIndex:10];
    XCTAssertEqual(IMChatValidMentionSpans(shown, spans).count, 1u);
}

/// 解析/序列化往返（协议 ↔ 模型 ↔ SQLite 共用同一对）。脏数据一律丢弃该项。
- (void)testMentionSpanCodec {
    NSArray<IMMentionSpan *> *spans = [IMMentionSpan spansFromArray:@[
        @{ @"offset": @2, @"length": @3, @"user_id": @"u1" },
        @{ @"offset": @9, @"length": @4 },                    // @所有人：无 user_id
        @{ @"offset": @(-1), @"length": @3 },                  // 脏：负偏移
        @{ @"offset": @0, @"length": @0 },                     // 脏：零长
        @"不是字典",
    ]];
    XCTAssertEqual(spans.count, 2u);
    XCTAssertTrue(NSEqualRanges(spans[0].range, NSMakeRange(2, 3)));
    XCTAssertEqualObjects(spans[0].uid, @"u1");
    XCTAssertNil(spans[1].uid);
    NSArray<NSDictionary *> *back = [IMMentionSpan arrayFromSpans:spans];
    XCTAssertEqualObjects(back[0], (@{ @"offset": @2, @"length": @3, @"user_id": @"u1" }));
    XCTAssertEqualObjects(back[1], (@{ @"offset": @9, @"length": @4 }));
    XCTAssertNil([IMMentionSpan spansFromArray:@[]], @"空数组 → nil（按「无片段」处理，回落老路）");
}

@end
