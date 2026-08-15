//  IMMentionTests.m
//  群 @提及 + 会话 mention_unread 的纯逻辑测试（M4-8）。
//  app-hosted 测试，符号由宿主 App 提供；头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Models/IMGroupInfo.h"

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

@end
