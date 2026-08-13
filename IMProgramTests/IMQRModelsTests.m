//  IMQRModelsTests.m
//  二维码解析 + 扫码结果→动作映射的纯逻辑测试（QRCODE P0 + G3）。
//  app-hosted 测试，符号由宿主 App 提供；头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMQRModels.h"

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
    XCTAssertEqual(IMQRGroupActionForCard(nil), IMQRGroupActionDisabled);
    XCTAssertEqualObjects(IMQRGroupActionLabel(IMQRGroupActionApply), @"申请加入");
    XCTAssertNotNil(IMQRGroupActionNote([self groupCardJoined:NO joinable:NO reason:@"full"]));
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

@end
