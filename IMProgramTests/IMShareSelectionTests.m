//  IMShareSelectionTests.m
//  分享选择页选中集（SHARE_PICKER_UX_SKETCH ⑦）：按 conv_id 跨来源去重、合计上限、好友 conv_id 推导、
//  搜索分组去重；以及群邀请文本。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMShareSelection.h"
#import "../IMProgram/Common/IMContactShare.h"
#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Models/IMUserCard.h"
#import "../IMProgram/Models/IMGroupInfo.h"
#import "../IMProgram/Common/IMAccountIdentity.h"

@interface IMShareSelectionTests : XCTestCase
@end

@implementation IMShareSelectionTests

- (IMConversation *)conv:(NSString *)convID group:(BOOL)group peer:(NSString *)peer {
    IMConversation *c = [IMConversation new];
    c.convID = convID;
    c.isGroup = group;
    c.peer = peer ?: @"";
    return c;
}

- (IMUserCard *)friend:(NSString *)uid {
    IMUserCard *u = [IMUserCard new];
    u.userID = uid;
    u.nickname = [@"nick-" stringByAppendingString:uid];
    u.avatarURL = @"";
    return u;
}

/// 好友 conv_id 与协议推导一致（小的 uid 在前），无论谁是 self。
- (void)testFriendConvIDMatchesProtocolDerivation {
    IMConversation *a = [IMShareSelection conversationForFriend:[self friend:@"2002"] selfUID:@"1001"];
    IMConversation *b = [IMShareSelection conversationForFriend:[self friend:@"1001"] selfUID:@"2002"];
    XCTAssertEqualObjects(a.convID, @"u_1001_u_2002");
    XCTAssertEqualObjects(b.convID, @"u_1001_u_2002");
    XCTAssertFalse(a.isGroup);
    XCTAssertEqualObjects(a.peer, @"2002");
    XCTAssertEqualObjects(a.peerNickname, @"nick-2002");
    XCTAssertNil([IMShareSelection conversationForFriend:[self friend:@"2002"] selfUID:@""], @"无本人 uid 无法推导");
}

- (void)testGroupTarget {
    IMGroupInfo *g = [IMGroupInfo new];
    g.convID = @"g_abc";
    g.name = @"产品群";
    IMConversation *c = [IMShareSelection conversationForGroup:g];
    XCTAssertEqualObjects(c.convID, @"g_abc");
    XCTAssertTrue(c.isGroup);
    XCTAssertEqualObjects(c.peer, @"", @"群目标 toUser 必须为空串");
    XCTAssertEqualObjects(c.displayName, @"产品群");
    g.convID = @"";
    XCTAssertNil([IMShareSelection conversationForGroup:g]);
}

/// 在最近聊天勾的会话，与好友页合成的同一人目标是同一项：好友页看到已勾选，再点即取消。
- (void)testCrossSourceDedupeByConvID {
    IMShareSelection *sel = [[IMShareSelection alloc] initWithLimit:9];
    IMConversation *recent = [self conv:@"u_1001_u_2002" group:NO peer:@"2002"];
    XCTAssertEqual([sel toggle:recent], IMShareToggleAdded);
    IMConversation *fromFriends = [IMShareSelection conversationForFriend:[self friend:@"2002"] selfUID:@"1001"];
    XCTAssertTrue([sel containsConvID:fromFriends.convID]);
    XCTAssertEqual([sel toggle:fromFriends], IMShareToggleRemoved);
    XCTAssertEqual(sel.count, 0u);
}

/// 上限是合计：单聊 + 群 + 好友一起算；满了返回 Capped 且不加入；取消一项后又能加。
- (void)testTotalCapAcrossSources {
    IMShareSelection *sel = [[IMShareSelection alloc] initWithLimit:9];
    for (int i = 0; i < 5; i++) { [sel toggle:[self conv:[NSString stringWithFormat:@"g_%d", i] group:YES peer:nil]]; }
    for (int i = 0; i < 4; i++) {
        NSString *uid = [NSString stringWithFormat:@"30%02d", i];
        [sel toggle:[IMShareSelection conversationForFriend:[self friend:uid] selfUID:@"1001"]];
    }
    XCTAssertEqual(sel.count, 9u);
    IMConversation *tenth = [self conv:@"g_x" group:YES peer:nil];
    XCTAssertEqual([sel toggle:tenth], IMShareToggleCapped);
    XCTAssertFalse([sel containsConvID:@"g_x"]);
    XCTAssertEqual(sel.count, 9u);
    XCTAssertTrue([sel removeConvID:@"g_0"]);
    XCTAssertEqual([sel toggle:tenth], IMShareToggleAdded);
}

/// 保持勾选顺序；删中间项不打乱其余顺序；删不存在的返回 NO；空 conv_id 忽略。
- (void)testOrderAndRemove {
    IMShareSelection *sel = [[IMShareSelection alloc] initWithLimit:9];
    [sel toggle:[self conv:@"a" group:YES peer:nil]];
    [sel toggle:[self conv:@"b" group:YES peer:nil]];
    [sel toggle:[self conv:@"c" group:YES peer:nil]];
    XCTAssertTrue([sel removeConvID:@"b"]);
    XCTAssertFalse([sel removeConvID:@"zz"]);
    XCTAssertEqualObjects([sel.conversations valueForKey:@"convID"], (@[@"a", @"c"]));
    XCTAssertEqual([sel toggle:[self conv:@"" group:YES peer:nil]], IMShareToggleInvalid);
    XCTAssertEqual(sel.count, 2u);
}

/// 已拉黑 / 已注销 / 系统通知号不可作分享目标。
- (void)testShareableFriend {
    XCTAssertTrue([IMShareSelection isShareableFriend:[self friend:@"2002"]]);
    IMUserCard *blocked = [self friend:@"2003"]; blocked.blocked = YES;
    XCTAssertFalse([IMShareSelection isShareableFriend:blocked]);
    IMUserCard *deleted = [self friend:@"2004"]; deleted.deleted = YES;
    XCTAssertFalse([IMShareSelection isShareableFriend:deleted]);
    XCTAssertFalse([IMShareSelection isShareableFriend:[self friend:IMSystemUserID]]);
    XCTAssertFalse([IMShareSelection isShareableFriend:[self friend:@""]]);
}

/// 搜索分组去重：已在最近聊天命中的 conv_id 不在好友 / 群分组重复出现，顺序保持。
- (void)testExcludingConvIDs {
    NSArray *cands = @[[self conv:@"x" group:YES peer:nil], [self conv:@"y" group:YES peer:nil],
                       [self conv:@"z" group:YES peer:nil], [self conv:@"" group:YES peer:nil]];
    NSArray *out = [IMShareSelection conversations:cands excludingConvIDs:[NSSet setWithObject:@"y"]];
    XCTAssertEqualObjects([out valueForKey:@"convID"], (@[@"x", @"z"]));
}

- (void)testGroupInviteText {
    NSString *link = @"https://im.example/q/g/abc";
    NSString *t = [IMContactShare groupInviteTextWithGroupName:@" 产品群 " link:link];
    NSArray *lines = [t componentsSeparatedByString:@"\n"];
    XCTAssertEqual(lines.count, 2u);
    XCTAssertTrue([lines[0] containsString:@"产品群"], @"%@", lines[0]);
    XCTAssertFalse([lines[0] containsString:@" 产品群 "], @"群名两端空白应裁掉");
    XCTAssertEqualObjects(lines[1], link);
    NSString *unnamed = [IMContactShare groupInviteTextWithGroupName:@"" link:link];
    XCTAssertTrue([unnamed hasSuffix:link]);
    XCTAssertFalse([unnamed hasPrefix:@"\n"]);
}

@end
