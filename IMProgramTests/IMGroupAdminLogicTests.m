//  IMGroupAdminLogicTests.m
//  群管理页「管理员 / 转让群组」的纯逻辑单测：计数口径 / 候选过滤 / 批量截断 / 错误与批量文案 /
//  选人页行模型不落内部 ID。对应 IMServer/docs/design/GROUP_ADMIN_TRANSFER_DESIGN.md §9 测试点 4~6、19~21。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Detail/IMGroupAdminLogic.h"
#import "../IMProgram/Models/IMGroupInfo.h"
#import "../IMProgram/Models/IMUserCard.h"

@interface IMGroupAdminLogicTests : XCTestCase
@end

@implementation IMGroupAdminLogicTests

/// 造一个成员（uid 用 10 位数字，与线上内部 ID 同形态）。
static IMGroupMember *MakeMember(NSString *uid, NSString *nick, NSString *username,
                                 IMGroupRole role, int64_t joinedAt) {
    IMGroupMember *m = [IMGroupMember new];
    m.userID = uid;
    m.nickname = nick;
    m.username = username;
    m.avatarURL = @"";
    m.role = role;
    m.joinedAt = joinedAt;
    return m;
}

/// 群主 1000000001（我）+ 管理员两位 + 普通成员两位。
- (NSArray<IMGroupMember *> *)sampleMembers {
    return @[
        MakeMember(@"1000000001", @"老王", @"laowang", IMGroupRoleOwner, 1),
        MakeMember(@"4820571639", @"小明", @"xiaoming", IMGroupRoleAdmin, 30),
        MakeMember(@"4820571640", @"小红", @"xiaohong", IMGroupRoleAdmin, 20),
        MakeMember(@"4820571641", @"小丽", @"xiaoli", IMGroupRoleMember, 40),
        MakeMember(@"4820571642", @"阿刚", @"agang", IMGroupRoleMember, 50),
    ];
}

#pragma mark - 群主 / 管理员派生

- (void)testOwnerAndAdmins {
    NSArray<IMGroupMember *> *ms = [self sampleMembers];
    XCTAssertEqualObjects([IMGroupAdminLogic ownerFromMembers:ms].userID, @"1000000001");
    XCTAssertNil([IMGroupAdminLogic ownerFromMembers:@[]]);

    NSArray<IMGroupMember *> *admins = [IMGroupAdminLogic adminsFromMembers:ms];
    XCTAssertEqual(admins.count, 2u);
    // joinedAt 升序（与详情页成员表同口径）：小红(20) 在 小明(30) 前。
    XCTAssertEqualObjects(admins[0].userID, @"4820571640");
    XCTAssertEqualObjects(admins[1].userID, @"4820571639");
}

- (void)testAdminCountText {
    XCTAssertEqualObjects([IMGroupAdminLogic adminCountTextForMembers:[self sampleMembers]], @"2 人");
    XCTAssertEqualObjects([IMGroupAdminLogic adminCountTextForMembers:@[]], @"未设置");
    // 只有群主一人时也是「未设置」——群主不算管理员。
    NSArray *ownerOnly = @[MakeMember(@"1000000001", @"老王", @"laowang", IMGroupRoleOwner, 1)];
    XCTAssertEqualObjects([IMGroupAdminLogic adminCountTextForMembers:ownerOnly], @"未设置");
}

#pragma mark - 候选过滤

- (void)testAdminCandidatesExcludeOwnerAdminsAndSelf {
    NSArray<IMGroupMember *> *c = [IMGroupAdminLogic adminCandidatesFromMembers:[self sampleMembers]
                                                                       myUserID:@"1000000001"];
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (IMGroupMember *m in c) { [ids addObject:m.userID]; }
    XCTAssertEqualObjects(ids, (@[@"4820571641", @"4820571642"]), @"只剩普通成员");
}

- (void)testAdminCandidatesExcludeSelfEvenIfPlainMember {
    // 边界：万一以普通成员身份进到这条路径（服务端仍是闸门），也不该把自己列出来。
    NSArray<IMGroupMember *> *c = [IMGroupAdminLogic adminCandidatesFromMembers:[self sampleMembers]
                                                                       myUserID:@"4820571641"];
    XCTAssertEqual(c.count, 1u);
    XCTAssertEqualObjects(c.firstObject.userID, @"4820571642");
}

- (void)testTransferCandidatesAreEveryoneButMe {
    NSArray<IMGroupMember *> *c = [IMGroupAdminLogic transferCandidatesFromMembers:[self sampleMembers]
                                                                          myUserID:@"1000000001"];
    XCTAssertEqual(c.count, 4u, @"管理员也可以被选为新群主（后端不限）");
    for (IMGroupMember *m in c) { XCTAssertNotEqualObjects(m.userID, @"1000000001"); }
}

- (void)testTransferCandidatesEmptyWhenAloneInGroup {
    NSArray *ownerOnly = @[MakeMember(@"1000000001", @"老王", @"laowang", IMGroupRoleOwner, 1)];
    XCTAssertEqual([IMGroupAdminLogic transferCandidatesFromMembers:ownerOnly myUserID:@"1000000001"].count, 0u,
                   @"群里只有我一人 → 选人页走空态，不是白屏");
}

#pragma mark - 选人页行模型（身份体系 §1.3）

- (void)testPickerCardsNeverFallBackToInternalID {
    NSArray<IMGroupMember *> *ms = @[
        MakeMember(@"4820571641", @"小丽", @"xiaoli", IMGroupRoleMember, 40),
        MakeMember(@"4820571643", @"", @"pangzi", IMGroupRoleMember, 60),   // 脏数据：昵称空
        MakeMember(@"4820571644", @"", nil, IMGroupRoleMember, 70),          // 脏数据：昵称与句柄都空
    ];
    NSArray<IMUserCard *> *cards = [IMGroupAdminLogic pickerCardsFromMembers:ms];
    XCTAssertEqual(cards.count, 3u);
    XCTAssertEqualObjects(cards[0].displayName, @"小丽");
    XCTAssertEqualObjects(cards[1].displayName, @"@pangzi", @"昵称空 → 回退 @username");
    XCTAssertEqualObjects(cards[2].displayName, @"未命名用户", @"两者皆空也**绝不**回退 10 位内部 ID");
    for (IMUserCard *c in cards) {
        XCTAssertFalse([c.displayName containsString:c.userID], @"显示名里不得出现内部 ID");
    }
}

- (void)testPickerCardsPreferGroupNickname {
    IMGroupMember *m = MakeMember(@"4820571645", @"大雷", @"dalei", IMGroupRoleMember, 80);
    m.groupNickname = @"运维";
    IMUserCard *c = [IMGroupAdminLogic pickerCardsFromMembers:@[m]].firstObject;
    XCTAssertEqualObjects(c.displayName, @"运维", @"群昵称优先于全局昵称");
    XCTAssertEqualObjects(c.username, @"dalei", @"@句柄仍带上，供副行与搜索用");
}

#pragma mark - 批量上限与文案

- (void)testClampBatchSelection {
    XCTAssertEqual(IMGroupAdminMaxBatch, 5u);
    NSArray *six = @[@"a", @"b", @"c", @"d", @"e", @"f"];
    XCTAssertEqualObjects([IMGroupAdminLogic clampBatchSelection:six], (@[@"a", @"b", @"c", @"d", @"e"]));
    XCTAssertEqualObjects([IMGroupAdminLogic clampBatchSelection:@[@"a"]], (@[@"a"]));
    XCTAssertEqualObjects([IMGroupAdminLogic clampBatchSelection:nil], @[]);
}

- (void)testBatchToast {
    XCTAssertEqualObjects([IMGroupAdminLogic batchToastWithSucceeded:3 failed:0 firstError:nil],
                          @"已添加 3 位管理员");
    XCTAssertEqualObjects([IMGroupAdminLogic batchToastWithSucceeded:2 failed:1 firstError:@"TA 已不在群里"],
                          @"2 位已添加，1 位失败：TA 已不在群里");
    XCTAssertEqualObjects([IMGroupAdminLogic batchToastWithSucceeded:0 failed:2 firstError:@"只有群主可以进行此操作"],
                          @"只有群主可以进行此操作", @"全失败只报第一条错误");
}

#pragma mark - 错误码映射（§4.4）

- (void)testToastForError {
    NSError *(^err)(NSInteger, NSString *) = ^NSError *(NSInteger code, NSString *msg) {
        return [NSError errorWithDomain:@"IMHTTP" code:code userInfo:@{ NSLocalizedDescriptionKey: msg }];
    };
    XCTAssertEqualObjects([IMGroupAdminLogic toastForError:err(300201, @"group not found")], @"该群已被解散");
    XCTAssertEqualObjects([IMGroupAdminLogic toastForError:err(300203, @"not a group member")], @"你已不在该群");
    XCTAssertEqualObjects([IMGroupAdminLogic toastForError:err(300204, @"no group permission")], @"只有群主可以进行此操作");
    // 100001 一个码复用三种语义，**不 parse 英文串**分支：统一给一句可操作的中文。
    XCTAssertEqualObjects([IMGroupAdminLogic toastForError:err(100001, @"target not in group")], @"操作失败，请刷新后重试");
    XCTAssertEqualObjects([IMGroupAdminLogic toastForError:err(100001, @"already the owner")], @"操作失败，请刷新后重试");
    // 未收录的码回退服务端原文（网络层错误也走这一支）。
    XCTAssertEqualObjects([IMGroupAdminLogic toastForError:err(-1009, @"网络未连接，请检查网络")], @"网络未连接，请检查网络");
}

@end
