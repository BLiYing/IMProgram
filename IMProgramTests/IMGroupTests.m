//  IMGroupTests.m
//  群聊模型单测（M3-5）：IMGroupInfo/IMGroupMember 解析（角色映射/脏数据）、
//  IMConversation 群字段解析、IMMessageModel from_nickname 解析与落库往返。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMGroupInfo.h"
#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Models/IMMessageModel.h"

@interface IMGroupTests : XCTestCase
@end

@implementation IMGroupTests

#pragma mark - 角色映射

- (void)testRoleFromString {
    XCTAssertEqual(IMGroupRoleFromString(@"owner"), IMGroupRoleOwner);
    XCTAssertEqual(IMGroupRoleFromString(@"admin"), IMGroupRoleAdmin);
    XCTAssertEqual(IMGroupRoleFromString(@"member"), IMGroupRoleMember);
    XCTAssertEqual(IMGroupRoleFromString(@"weird"), IMGroupRoleMember, @"未知角色按普通成员兜底");
    XCTAssertEqual(IMGroupRoleFromString(nil), IMGroupRoleMember);
}

#pragma mark - 群资料解析

- (void)testParseGroupInfo {
    NSDictionary *dict = @{
        @"conv_id": @"g_abc", @"name": @"开发群", @"owner": @"1001",
        @"avatar_url": @"", @"created_at": @1000, @"my_role": @"owner",
        @"members": @[
            @{ @"user_id": @"1001", @"nickname": @"队长", @"avatar_url": @"", @"role": @"owner", @"joined_at": @1 },
            @{ @"user_id": @"1002", @"nickname": @"小明", @"avatar_url": @"", @"role": @"admin", @"joined_at": @2 },
            @{ @"user_id": @"1003", @"nickname": @"", @"avatar_url": @"", @"role": @"member", @"joined_at": @3 },
        ],
    };
    IMGroupInfo *g = [IMGroupInfo groupFromDictionary:dict];
    XCTAssertNotNil(g);
    XCTAssertEqualObjects(g.convID, @"g_abc");
    XCTAssertEqualObjects(g.name, @"开发群");
    XCTAssertEqualObjects(g.owner, @"1001");
    XCTAssertEqual(g.myRole, IMGroupRoleOwner);
    XCTAssertEqual(g.members.count, 3u);
    XCTAssertEqual(g.members[0].role, IMGroupRoleOwner);
    XCTAssertEqual(g.members[1].role, IMGroupRoleAdmin);
    // displayName：有昵称用昵称；**末级不再回退 uid**——账号重构后 user_id 是 10 位随机数字
    // 内部 ID，露出来毫无意义（docs/UI.md「用户标识」）。无昵称无句柄 → 占位。
    XCTAssertEqualObjects(g.members[1].displayName, @"小明");
    XCTAssertEqualObjects(g.members[2].displayName, @"未命名用户");
    XCTAssertNotEqualObjects(g.members[2].displayName, g.members[2].userID);
    // nicknameOfMember：查昵称（气泡回退）。
    XCTAssertEqualObjects([g nicknameOfMember:@"1002"], @"小明");
    XCTAssertNil([g nicknameOfMember:@"1003"], @"无昵称成员返回 nil（回退 uid 由调用方做）");
    XCTAssertNil([g nicknameOfMember:@"ghost"]);
}

- (void)testParseGroupInfoDirtyData {
    // 缺 conv_id → nil；members 混入脏元素 → 跳过。
    XCTAssertNil([IMGroupInfo groupFromDictionary:@{ @"name": @"x" }]);
    XCTAssertNil([IMGroupInfo groupFromDictionary:nil]);
    IMGroupInfo *g = [IMGroupInfo groupFromDictionary:@{
        @"conv_id": @"g_x", @"members": @[ @"garbage", @{ @"nickname": @"没有uid" }, @{ @"user_id": @"ok" } ],
    }];
    XCTAssertEqual(g.members.count, 1u, @"脏成员被跳过");
    XCTAssertEqualObjects(g.members.firstObject.userID, @"ok");
}

- (void)testParseGroupsList {
    NSArray *arr = @[
        @{ @"conv_id": @"g_1", @"name": @"一群", @"owner": @"a", @"created_at": @2 },
        @{ @"conv_id": @"g_2", @"name": @"二群", @"owner": @"b", @"created_at": @1 },
        @"garbage",
    ];
    NSArray<IMGroupInfo *> *groups = [IMGroupInfo groupsFromArray:arr];
    XCTAssertEqual(groups.count, 2u);
    XCTAssertEqualObjects(groups[0].convID, @"g_1");
    XCTAssertEqual(groups[0].members.count, 0u, @"列表项不含成员明细");
    XCTAssertEqual([IMGroupInfo groupsFromArray:nil].count, 0u);
}

#pragma mark - 会话列表群项解析

- (void)testParseGroupConversation {
    NSArray *arr = @[ @{
        @"conv_id": @"g_abc", @"is_group": @YES, @"name": @"开发群", @"avatar_url": @"data:image/png;base64,GG",
        @"member_count": @3, @"peer": @"",
        @"last_message": @{ @"content": @"早", @"from": @"1002", @"from_nickname": @"小明", @"timestamp": @500 },
        @"latest_conv_seq": @1, @"read_seq": @0, @"unread": @1,
    } ];
    NSArray<IMConversation *> *convs = [IMConversation conversationsFromArray:arr];
    XCTAssertEqual(convs.count, 1u);
    IMConversation *c = convs.firstObject;
    XCTAssertTrue(c.isGroup);
    XCTAssertEqualObjects(c.name, @"开发群");
    XCTAssertEqual(c.memberCount, 3);
    XCTAssertEqualObjects(c.lastFromNickname, @"小明");
    XCTAssertEqualObjects(c.lastContent, @"早");
}

- (void)testParseP2PConversationHasNoGroupFields {
    NSArray *arr = @[ @{ @"conv_id": @"u_a_u_b", @"is_group": @NO, @"peer": @"b",
                         @"last_message": @{ @"content": @"hi", @"from": @"b", @"timestamp": @1 } } ];
    IMConversation *c = [IMConversation conversationsFromArray:arr].firstObject;
    XCTAssertFalse(c.isGroup);
    XCTAssertEqualObjects(c.peer, @"b");
    XCTAssertEqualObjects(c.lastFromNickname, @"", @"单聊无 from_nickname（空串）");
}

#pragma mark - 消息 from_nickname

- (void)testNewMsgParsesFromNickname {
    IMMessageModel *m = [IMMessageModel receivedMessageWithNewMsgData:@{
        @"server_msg_id": @"s1", @"conv_id": @"g_abc", @"from": @"1002", @"from_nickname": @"小明",
        @"content_type": @"text", @"content": @"早", @"conv_seq": @1, @"timestamp": @500,
    }];
    XCTAssertEqualObjects(m.fromNickname, @"小明");
    // 单聊消息无该字段 → nil。
    IMMessageModel *p = [IMMessageModel receivedMessageWithNewMsgData:@{
        @"server_msg_id": @"s2", @"conv_id": @"u_a_u_b", @"from": @"b",
        @"content_type": @"text", @"content": @"hi", @"conv_seq": @1, @"timestamp": @1,
    }];
    XCTAssertNil(p.fromNickname);
}

- (void)testMessageDictionaryRoundTripKeepsNickname {
    IMMessageModel *m = [IMMessageModel new];
    m.convID = @"g_abc";
    m.from = @"1002";
    m.fromNickname = @"小明";
    m.content = @"早";
    m.contentType = @"text";
    m.convSeq = 1;
    m.timestamp = 500;
    m.status = IMMessageStatusReceived;
    IMMessageModel *back = [IMMessageModel messageFromDictionary:m.dictionaryRepresentation];
    XCTAssertEqualObjects(back.fromNickname, @"小明");
    XCTAssertEqualObjects(back.convID, @"g_abc");
}

@end

@interface IMGroupMemberUsernameTests : XCTestCase
@end

@implementation IMGroupMemberUsernameTests

/// 成员解析要带 username（成员行副标题显示 @xxx），且 displayName 的末级**不落 userID**——
/// 账号重构后那是 10 位随机数字内部 ID（见 IMServer/docs/UI.md「用户标识」）。
/// 成员解析入口是私有的，故经公开的 groupFromDictionary: 间接构造。
- (void)testMemberParsesUsernameAndDisplayNameNeverFallsBackToInternalID {
    IMGroupInfo *g = [IMGroupInfo groupFromDictionary:@{
        @"conv_id": @"g_x", @"name": @"群", @"owner": @"1000000001", @"my_role": @"member",
        @"members": @[
            @{ @"user_id": @"4820571639", @"username": @"xiaoming", @"nickname": @"小明", @"role": @"member" },
            @{ @"user_id": @"1937284650", @"username": @"nonick", @"nickname": @"", @"role": @"member" },
            @{ @"user_id": @"5555555555", @"nickname": @"", @"role": @"member" },
        ],
    }];
    XCTAssertEqual(g.members.count, 3);

    IMGroupMember *full = g.members[0];
    XCTAssertEqualObjects(full.userID, @"4820571639");
    XCTAssertEqualObjects(full.username, @"xiaoming");
    XCTAssertEqualObjects(full.displayName, @"小明");

    // 昵称为空 → 退到 @username，**绝不退到内部 ID**。
    IMGroupMember *noNick = g.members[1];
    XCTAssertEqualObjects(noNick.displayName, @"@nonick");
    XCTAssertNotEqualObjects(noNick.displayName, noNick.userID);

    // 昵称与句柄都空 → 占位，仍然不是内部 ID。
    IMGroupMember *bare = g.members[2];
    XCTAssertEqualObjects(bare.displayName, @"未命名用户");
    XCTAssertNotEqualObjects(bare.displayName, bare.userID);
}

@end
