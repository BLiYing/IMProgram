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


#pragma mark - 远端候选模式的排除集（超级群）

/// 超级群里「添加管理员」的候选来自服务端搜索，端上只能**排除**而不是**筛出**。
/// 排除集 = 群主 + 现有管理员 + 我，正好只需要治理集——而那恰恰是超级群资料里有的。
/// 少排一个的后果：把现任管理员再"设为管理员"，或把自己列进候选。
- (void)testAdminExclusionsCoversOwnerAdminsAndSelf {
    IMGroupMember *owner = [IMGroupMember new]; owner.userID = @"o"; owner.role = IMGroupRoleOwner;
    IMGroupMember *a1 = [IMGroupMember new]; a1.userID = @"a1"; a1.role = IMGroupRoleAdmin;
    IMGroupMember *me = [IMGroupMember new]; me.userID = @"me"; me.role = IMGroupRoleAdmin;
    IMGroupMember *plain = [IMGroupMember new]; plain.userID = @"p1"; plain.role = IMGroupRoleMember;

    NSSet<NSString *> *ex = [IMGroupAdminLogic adminExclusionsFromMembers:@[owner, a1, me, plain] myUserID:@"me"];
    XCTAssertTrue([ex containsObject:@"o"], @"群主必须排除");
    XCTAssertTrue([ex containsObject:@"a1"], @"现有管理员必须排除");
    XCTAssertTrue([ex containsObject:@"me"], @"我自己必须排除");
    XCTAssertFalse([ex containsObject:@"p1"], @"普通成员是候选，不该被排除");
}

/// 我还不是管理员时也要把自己排除（超级群资料里我那一行是 member，不在治理集内）。
- (void)testAdminExclusionsIncludesSelfWhenPlainMember {
    IMGroupMember *owner = [IMGroupMember new]; owner.userID = @"o"; owner.role = IMGroupRoleOwner;
    NSSet<NSString *> *ex = [IMGroupAdminLogic adminExclusionsFromMembers:@[owner] myUserID:@"me"];
    XCTAssertTrue([ex containsObject:@"me"]);
    XCTAssertEqual(ex.count, 2u);
}

/// 空/nil 输入不崩，且仍排除我自己。
- (void)testAdminExclusionsDegradesSafely {
    XCTAssertEqualObjects([IMGroupAdminLogic adminExclusionsFromMembers:nil myUserID:@"me"],
                          [NSSet setWithObject:@"me"]);
    XCTAssertEqual([IMGroupAdminLogic adminExclusionsFromMembers:nil myUserID:nil].count, 0u);
}

#pragma mark - 开关组读写与失败回滚

static NSArray<NSNumber *> *AllSettingFields(void) {
    return @[@(IMGroupSettingFieldJoinApproval), @(IMGroupSettingFieldPermInvite), @(IMGroupSettingFieldPermEditInfo),
             @(IMGroupSettingFieldPermPin), @(IMGroupSettingFieldHistoryVisible)];
}

/// 五个开关的当前值，按固定顺序。
static NSArray<NSNumber *> *Flags(IMGroupInfo *g) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *f in AllSettingFields()) {
        [out addObject:@([IMGroupAdminLogic valueOfField:(IMGroupSettingField)f.integerValue inGroup:g])];
    }
    return out;
}

/// 每个枚举值必须落在**对应**的那个属性上、且不碰其它四个（映射写串了 = 拨 A 开关改了 B 设置，界面照常）。
- (void)test_五个开关字段各自读写互不串 {
    for (NSNumber *f in AllSettingFields()) {
        IMGroupInfo *g = [IMGroupInfo new];
        [IMGroupAdminLogic setValue:YES forField:(IMGroupSettingField)f.integerValue inGroup:g];
        NSArray<NSNumber *> *flags = Flags(g);
        for (NSUInteger i = 0; i < flags.count; i++) {
            XCTAssertEqual(flags[i].boolValue, i == (NSUInteger)f.integerValue, @"设 %@ 后第 %lu 个字段不对", f, (unsigned long)i);
        }
    }
    IMGroupInfo *g = [IMGroupInfo new];
    [IMGroupAdminLogic setValue:YES forField:IMGroupSettingFieldJoinApproval inGroup:g];
    XCTAssertTrue(g.joinApproval);
    [IMGroupAdminLogic setValue:YES forField:IMGroupSettingFieldPermInvite inGroup:g];
    XCTAssertTrue(g.permInvite);
    [IMGroupAdminLogic setValue:YES forField:IMGroupSettingFieldPermEditInfo inGroup:g];
    XCTAssertTrue(g.permEditInfo);
    [IMGroupAdminLogic setValue:YES forField:IMGroupSettingFieldPermPin inGroup:g];
    XCTAssertTrue(g.permPin);
    [IMGroupAdminLogic setValue:YES forField:IMGroupSettingFieldHistoryVisible inGroup:g];
    XCTAssertTrue(g.historyVisible);
}

/// 提交失败的回滚：先记旧值、乐观改、失败写回旧值——五个字段必须与改之前**完全一致**。
/// 旧 bug：回滚去读已被乐观改过的 self.group，本地留着失败值，下一次任一开关提交会把它一并上报。
- (void)test_乐观更新失败后写回旧值_五个字段与改之前一致 {
    for (NSNumber *f in AllSettingFields()) {
        IMGroupSettingField field = (IMGroupSettingField)f.integerValue;
        IMGroupInfo *g = [IMGroupInfo new];
        g.permInvite = YES; g.historyVisible = YES; // 非全零的起点，才能看出「写回」写对了
        NSArray<NSNumber *> *before = Flags(g);

        BOOL oldValue = [IMGroupAdminLogic valueOfField:field inGroup:g];
        [IMGroupAdminLogic setValue:!oldValue forField:field inGroup:g]; // 乐观
        XCTAssertNotEqualObjects(Flags(g), before, @"乐观更新应当改了本地值");
        [IMGroupAdminLogic setValue:oldValue forField:field inGroup:g];  // 失败回滚
        XCTAssertEqualObjects(Flags(g), before, @"字段 %@ 回滚后应与改之前完全一致", f);
    }
}

#pragma mark - 成员管理权限矩阵

static const IMGroupMemberAction kRemoveBoth = IMGroupMemberActionRemove | IMGroupMemberActionRemoveAndBan;

/// 对自己：什么都没有，无论我是谁、是否被禁言。
- (void)test_对自己没有任何动作 {
    for (IMGroupRole me = IMGroupRoleMember; me <= IMGroupRoleOwner; me++) {
        for (NSNumber *muted in @[@NO, @YES]) {
            XCTAssertEqual(IMGroupMemberActionsFor(me, me, YES, muted.boolValue), IMGroupMemberActionNone);
        }
    }
}

/// 普通成员：对任何人都没有任何动作（含对管理员、对别的成员）。
- (void)test_普通成员没有任何动作 {
    for (IMGroupRole target = IMGroupRoleMember; target <= IMGroupRoleOwner; target++) {
        XCTAssertEqual(IMGroupMemberActionsFor(IMGroupRoleMember, target, NO, NO), IMGroupMemberActionNone);
        XCTAssertEqual(IMGroupMemberActionsFor(IMGroupRoleMember, target, NO, YES), IMGroupMemberActionNone);
    }
}

/// 管理员：**只能管普通成员**（禁言/解禁/移出两档），不能升撤管理员、不能转让；对管理员、群主一概没有。
- (void)test_管理员只能管普通成员 {
    XCTAssertEqual(IMGroupMemberActionsFor(IMGroupRoleAdmin, IMGroupRoleMember, NO, NO),
                   IMGroupMemberActionMute | kRemoveBoth);
    XCTAssertEqual(IMGroupMemberActionsFor(IMGroupRoleAdmin, IMGroupRoleMember, NO, YES),
                   IMGroupMemberActionUnmute | kRemoveBoth);
    XCTAssertEqual(IMGroupMemberActionsFor(IMGroupRoleAdmin, IMGroupRoleAdmin, NO, NO), IMGroupMemberActionNone,
                   @"管理员不能动另一位管理员（权限须严格高于对方）");
    XCTAssertEqual(IMGroupMemberActionsFor(IMGroupRoleAdmin, IMGroupRoleOwner, NO, NO), IMGroupMemberActionNone);
}

/// 群主对普通成员：设为管理员 + 转让 + 禁言/解禁 + 移出两档；**没有**撤销管理员（对方不是管理员）。
- (void)test_群主对普通成员 {
    XCTAssertEqual(IMGroupMemberActionsFor(IMGroupRoleOwner, IMGroupRoleMember, NO, NO),
                   IMGroupMemberActionMakeAdmin | IMGroupMemberActionTransfer | IMGroupMemberActionMute | kRemoveBoth);
    XCTAssertEqual(IMGroupMemberActionsFor(IMGroupRoleOwner, IMGroupRoleMember, NO, YES),
                   IMGroupMemberActionMakeAdmin | IMGroupMemberActionTransfer | IMGroupMemberActionUnmute | kRemoveBoth);
}

/// 群主对管理员：撤销管理员 + 转让 + 禁言/解禁 + 移出；**没有**「设为管理员」（已经是了）。
- (void)test_群主对管理员 {
    XCTAssertEqual(IMGroupMemberActionsFor(IMGroupRoleOwner, IMGroupRoleAdmin, NO, NO),
                   IMGroupMemberActionRevokeAdmin | IMGroupMemberActionTransfer | IMGroupMemberActionMute | kRemoveBoth);
}

/// 禁言与解禁**二选一**：任何组合下都不会同时出现。
- (void)test_禁言与解禁互斥 {
    for (IMGroupRole me = IMGroupRoleMember; me <= IMGroupRoleOwner; me++) {
        for (IMGroupRole target = IMGroupRoleMember; target <= IMGroupRoleOwner; target++) {
            for (NSNumber *muted in @[@NO, @YES]) {
                IMGroupMemberAction a = IMGroupMemberActionsFor(me, target, NO, muted.boolValue);
                BOOL both = (a & IMGroupMemberActionMute) && (a & IMGroupMemberActionUnmute);
                XCTAssertFalse(both, @"me=%ld target=%ld muted=%@", (long)me, (long)target, muted);
            }
        }
    }
}

/// 移出两档永远成对出现（有一个就有另一个）。
- (void)test_移出两档成对出现 {
    for (IMGroupRole me = IMGroupRoleMember; me <= IMGroupRoleOwner; me++) {
        for (IMGroupRole target = IMGroupRoleMember; target <= IMGroupRoleOwner; target++) {
            IMGroupMemberAction a = IMGroupMemberActionsFor(me, target, NO, NO);
            XCTAssertEqual((a & IMGroupMemberActionRemove) != 0, (a & IMGroupMemberActionRemoveAndBan) != 0);
        }
    }
}

@end
