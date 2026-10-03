//  IMQRModelsTests.m
//  二维码解析 + 扫码结果→动作映射的纯逻辑测试（QRCODE P0 + G3）。
//  app-hosted 测试，符号由宿主 App 提供；头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMQRModels.h"
#import "../IMProgram/Common/IMLocalization.h"

@interface IMQRModelsTests : XCTestCase
@end

@implementation IMQRModelsTests

#pragma mark - resolve 解析

- (void)testResolveUser {
    IMQRResolved *r = [IMQRResolved fromDictionary:@{
        @"kind": @"user",
        @"data": @{ @"user_id": @"1001", @"nickname": @"小明", @"avatar_url": @"a", @"relation": @"friend" },
    }];
    XCTAssertEqual(r.kind, IMQRKindUser);
    XCTAssertEqualObjects(r.user.userID, @"1001");
    XCTAssertEqualObjects(r.user.nickname, @"小明");
    XCTAssertEqualObjects(r.user.relation, @"friend");
    XCTAssertNil(r.group);
}

- (void)testResolveGroup {
    IMQRResolved *r = [IMQRResolved fromDictionary:@{
        @"kind": @"group",
        @"data": @{ @"group_id": @"g1", @"name": @"群", @"member_count": @128,
                    @"inviter_nickname": @"群主", @"joined": @NO, @"joinable": @YES, @"reason": @"" },
    }];
    XCTAssertEqual(r.kind, IMQRKindGroup);
    XCTAssertEqualObjects(r.group.groupID, @"g1");
    XCTAssertEqual(r.group.memberCount, 128);
    XCTAssertTrue(r.group.joinable);
    XCTAssertFalse(r.group.joined);
}

- (void)testResolveUnknownAndDirty {
    IMQRResolved *r = [IMQRResolved fromDictionary:@{ @"kind": @"unknown", @"data": @{ @"text": @"https://x.cn/p" } }];
    XCTAssertEqual(r.kind, IMQRKindUnknown);
    XCTAssertEqualObjects(r.unknownText, @"https://x.cn/p");
    // 脏数据/空字典不崩，回 unknown。
    XCTAssertEqual([IMQRResolved fromDictionary:nil].kind, IMQRKindUnknown);
    XCTAssertEqual([IMQRResolved fromDictionary:@{}].kind, IMQRKindUnknown);
}

#pragma mark - 名片码动作映射

- (void)testUserActionMapping {
    XCTAssertEqual(IMQRUserActionForRelation(@"stranger"), IMQRUserActionAdd);
    XCTAssertEqual(IMQRUserActionForRelation(@"friend"), IMQRUserActionMessage);
    XCTAssertEqual(IMQRUserActionForRelation(@"self"), IMQRUserActionSelf);
    XCTAssertEqual(IMQRUserActionForRelation(@"blocked"), IMQRUserActionBlocked);
    XCTAssertEqual(IMQRUserActionForRelation(nil), IMQRUserActionAdd); // 未知按陌生人
    XCTAssertEqualObjects(IMQRUserActionLabel(IMQRUserActionMessage), @"发消息");
}

#pragma mark - 群码动作映射

- (IMQRGroupCard *)groupCardJoined:(BOOL)joined joinable:(BOOL)joinable reason:(NSString *)reason {
    return [IMQRGroupCard fromDictionary:@{ @"group_id": @"g", @"name": @"n", @"member_count": @3,
                                            @"joined": @(joined), @"joinable": @(joinable), @"reason": reason }];
}

- (void)testGroupActionMapping {
    XCTAssertEqual(IMQRGroupActionForCard([self groupCardJoined:YES joinable:NO reason:@"joined"]), IMQRGroupActionEnter);
    XCTAssertEqual(IMQRGroupActionForCard([self groupCardJoined:NO joinable:YES reason:@""]), IMQRGroupActionJoin);
    XCTAssertEqual(IMQRGroupActionForCard([self groupCardJoined:NO joinable:YES reason:@"approval"]), IMQRGroupActionApply);
    XCTAssertEqual(IMQRGroupActionForCard([self groupCardJoined:NO joinable:NO reason:@"full"]), IMQRGroupActionDisabled);
    XCTAssertEqual(IMQRGroupActionForCard([self groupCardJoined:NO joinable:NO reason:@"banned"]), IMQRGroupActionDisabled);
    XCTAssertEqual(IMQRGroupActionForCard([self groupCardJoined:NO joinable:NO reason:@"invite_revoked"]), IMQRGroupActionDisabled);
    XCTAssertEqual(IMQRGroupActionForCard(nil), IMQRGroupActionDisabled);
    XCTAssertEqualObjects(IMQRGroupActionLabel(IMQRGroupActionApply), @"申请加入");
    XCTAssertNotNil(IMQRGroupActionNote([self groupCardJoined:NO joinable:NO reason:@"full"]));
    XCTAssertNotNil(IMQRGroupActionNote([self groupCardJoined:NO joinable:NO reason:@"invite_revoked"]));
    XCTAssertNotNil(IMQRGroupActionNote([self groupCardJoined:NO joinable:YES reason:@"approval"]));
    XCTAssertNil(IMQRGroupActionNote([self groupCardJoined:NO joinable:YES reason:@""]));
}

#pragma mark - 外来码域名

- (void)testUnknownDomain {
    XCTAssertEqualObjects(IMQRUnknownDomain(@"https://shop.unknown-site.cn/pay?o=1"), @"shop.unknown-site.cn");
    XCTAssertEqualObjects(IMQRUnknownDomain(@"  http://a.com/x  "), @"a.com");
    XCTAssertNil(IMQRUnknownDomain(@"just text"));
    XCTAssertNil(IMQRUnknownDomain(nil));
}

#pragma mark - 入群申请解析

- (void)testJoinRequestParse {
    NSArray *arr = @[
        @{ @"user_id": @"u1", @"nickname": @"甲", @"hello": @"求带", @"status": @"pending", @"created_at": @100 },
        @{ @"nickname": @"无id" }, // 缺 user_id → 丢弃
        @{ @"user_id": @"u2" },
    ];
    NSArray<IMJoinRequest *> *reqs = [IMJoinRequest fromArray:arr];
    XCTAssertEqual(reqs.count, 2u);
    XCTAssertEqualObjects(reqs[0].userID, @"u1");
    XCTAssertEqualObjects(reqs[0].hello, @"求带");
    XCTAssertEqual(reqs[0].createdAt, 100);
    XCTAssertEqualObjects(reqs[1].userID, @"u2");
    XCTAssertEqualObjects([IMJoinRequest fromArray:nil], @[]);
}

#pragma mark - 入群申请分组 / 展示（对齐 Android JoinRequestsScreen）

- (void)testJoinRequestPendingAndHelloAndResultLabel {
    NSArray<IMJoinRequest *> *reqs = [IMJoinRequest fromArray:@[
        @{ @"user_id": @"a", @"status": @"pending", @"hello": @"  \n " },
        @{ @"user_id": @"b", @"status": @"approved", @"hello": @" 求带 " },
        @{ @"user_id": @"c", @"status": @"rejected" },
        @{ @"user_id": @"d", @"status": @"expired" },
    ]];
    XCTAssertTrue(reqs[0].isPending);
    XCTAssertFalse(reqs[1].isPending);
    XCTAssertFalse(reqs[3].isPending); // 未知终态归「已处理」，不留在待处理
    XCTAssertNil(reqs[0].visibleHello); // 空白验证消息整行不显，不写默认文案
    XCTAssertNil(reqs[2].visibleHello);
    XCTAssertEqualObjects(reqs[1].visibleHello, @"求带");
    XCTAssertEqualObjects(reqs[1].resultLabel, IMLocalized(@"qr.join_req.approved"));
    XCTAssertEqualObjects(reqs[2].resultLabel, IMLocalized(@"qr.join_req.rejected"));
    XCTAssertEqualObjects(reqs[3].resultLabel, @""); // 不冒充「已拒绝」
}

- (void)testJoinRequestInviterReplacesHelloLine {
    NSArray<IMJoinRequest *> *reqs = [IMJoinRequest fromArray:@[
        @{ @"user_id": @"a", @"status": @"pending", @"hello": @"求带", @"inviter_nickname": @"小明" },
        @{ @"user_id": @"b", @"status": @"pending", @"hello": @"求带", @"inviter_nickname": @"  " },
        @{ @"user_id": @"c", @"status": @"pending" },
    ]];
    XCTAssertEqualObjects(reqs[0].inviterNickname, @"小明");
    NSString *line = reqs[0].detailLine;
    XCTAssertTrue([line containsString:@"小明"]);
    XCTAssertFalse([line containsString:@"求带"]); // 取代附言行
    XCTAssertFalse([line containsString:@"%"]);
    XCTAssertEqualObjects(reqs[1].detailLine, @"求带"); // 空白邀请人 → 回落附言
    XCTAssertNil(reqs[2].detailLine);
}

- (void)testInviteResultToast {
    XCTAssertEqualObjects(IMInviteResultToast(2, 0, 2), IMLocalized(@"group.invite.pending_toast"));
    XCTAssertEqualObjects(IMInviteResultToast(2, 1, 1), IMLocalized(@"group.invite.pending_toast"));
    XCTAssertEqualObjects(IMInviteResultToast(2, 0, 0), IMLocalized(@"group.info.invite_all_in"));
    XCTAssertNil(IMInviteResultToast(2, 2, 0));
    XCTAssertNotNil(IMInviteResultToast(3, 2, 0)); // 部分已在群里
}

@end
