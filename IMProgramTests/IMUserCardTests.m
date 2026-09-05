//  IMUserCardTests.m
//  通讯录模型解析单测：找人结果（含 tags）、好友项（status/updated_at）、状态字符串映射、脏数据安全。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMUserCard.h"

@interface IMUserCardTests : XCTestCase
@end

@implementation IMUserCardTests

#pragma mark - 状态字符串映射

- (void)testStatusFromString {
    XCTAssertEqual(IMFriendStatusFromString(@"requested"), IMFriendStatusRequested);
    XCTAssertEqual(IMFriendStatusFromString(@"pending"), IMFriendStatusPending);
    XCTAssertEqual(IMFriendStatusFromString(@"accepted"), IMFriendStatusAccepted);
    XCTAssertEqual(IMFriendStatusFromString(@"blocked"), IMFriendStatusBlocked);
    XCTAssertEqual(IMFriendStatusFromString(@"weird"), IMFriendStatusNone);
    XCTAssertEqual(IMFriendStatusFromString(nil), IMFriendStatusNone);
}

#pragma mark - 找人结果解析（含 tags、去 phone）

- (void)testParseSearchResultWithTags {
    NSArray *arr = @[ @{ @"user_id": @"1002", @"nickname": @"小明", @"avatar_url": @"http://a/x.png",
                         @"tags": @[ @"golang", @"ios" ], @"status": @"active" } ];
    NSArray<IMUserCard *> *cards = [IMUserCard cardsFromArray:arr];
    XCTAssertEqual(cards.count, 1);
    IMUserCard *c = cards.firstObject;
    XCTAssertEqualObjects(c.userID, @"1002");
    XCTAssertEqualObjects(c.nickname, @"小明");
    XCTAssertEqualObjects(c.displayName, @"小明");
    XCTAssertEqual(c.tags.count, 2);
    XCTAssertEqualObjects(c.tags.firstObject, @"golang");
    // 搜索结果的 status 是账号状态("active")，非好友关系字符串 → 映射为 None。
    XCTAssertEqual(c.status, IMFriendStatusNone);
}

#pragma mark - username / 显示名回退链

/// username 是公开句柄，与内部 ID 是两个字段——解析不能串。
- (void)testParseUsernameSeparateFromInternalID {
    NSArray *arr = @[ @{ @"user_id": @"4820571639", @"username": @"xiaoming", @"nickname": @"小明" } ];
    IMUserCard *c = [IMUserCard cardsFromArray:arr].firstObject;
    XCTAssertEqualObjects(c.userID, @"4820571639");
    XCTAssertEqualObjects(c.username, @"xiaoming");
    XCTAssertEqualObjects(c.displayName, @"小明");
}

/// 昵称空但有 username → 退到 @username，仍然不能露内部 ID。
- (void)testDisplayNameFallsBackToHandleNotInternalID {
    NSArray *arr = @[ @{ @"user_id": @"4820571639", @"username": @"xiaoming", @"nickname": @"" } ];
    IMUserCard *c = [IMUserCard cardsFromArray:arr].firstObject;
    XCTAssertEqualObjects(c.displayName, @"@xiaoming");
    XCTAssertNotEqualObjects(c.displayName, c.userID);
}

#pragma mark - 好友项解析（status + updated_at）

- (void)testParseFriendEntry {
    NSArray *arr = @[ @{ @"user_id": @"1004", @"nickname": @"", @"avatar_url": @"",
                         @"status": @"pending", @"updated_at": @(1781610297229) } ];
    IMUserCard *c = [IMUserCard cardsFromArray:arr].firstObject;
    XCTAssertEqualObjects(c.userID, @"1004");
    XCTAssertEqual(c.status, IMFriendStatusPending);
    XCTAssertEqual(c.updatedAt, 1781610297229);
    // 昵称为空 → **不得**回退到 userID（那是 10 位内部数字 ID，露出来对用户毫无意义）；
    // 无 username 时给出占位。见 IMServer/docs/ACCOUNT_IDENTITY_REDESIGN.md §5.2。
    XCTAssertEqualObjects(c.displayName, @"未命名用户");
    XCTAssertNotEqualObjects(c.displayName, c.userID);
    // 无 tags 字段 → 空数组而非 nil。
    XCTAssertNotNil(c.tags);
    XCTAssertEqual(c.tags.count, 0);
}

#pragma mark - 本人资料解析（含 phone）

- (void)testParseMyProfileWithPhone {
    NSArray *arr = @[ @{ @"user_id": @"1001", @"nickname": @"我是1001", @"avatar_url": @"",
                         @"phone": @"13900000001", @"tags": @[ @"tester", @"web" ], @"status": @"active" } ];
    IMUserCard *c = [IMUserCard cardsFromArray:arr].firstObject;
    XCTAssertEqualObjects(c.phone, @"13900000001");
    XCTAssertEqualObjects(c.nickname, @"我是1001");
    XCTAssertEqual(c.tags.count, 2);
    // phone 缺失（如他人名片/搜索结果）→ 空串而非 nil。
    IMUserCard *noPhone = [IMUserCard cardsFromArray:@[ @{ @"user_id": @"x" } ]].firstObject;
    XCTAssertEqualObjects(noPhone.phone, @"");
}

#pragma mark - 脏数据安全

// 好友申请的**验证消息**：解析出来才能在「新的朋友」里显示"他为什么加我"。
// 老服务端/老数据不带这个键 → 空串（端上按"没写理由"渲染），**不能是 nil**——
// 各处都直接 `.length` 判断，nil 虽然也 length==0，但混着 nil 与空串迟早写出一个 `isEqualToString:` 分支。
- (void)testParseHello {
    NSArray<IMUserCard *> *cards = [IMUserCard cardsFromArray:@[
        @{ @"user_id": @"u1", @"status": @"pending", @"hello": @"我是隔壁老王" },
        @{ @"user_id": @"u2", @"status": @"pending" },                 // 老数据无此键
        @{ @"user_id": @"u3", @"status": @"accepted", @"hello": @"" }, // 成为好友后服务端清空
    ]];
    XCTAssertEqual(cards.count, 3);
    XCTAssertEqualObjects(cards[0].hello, @"我是隔壁老王");
    XCTAssertEqualObjects(cards[1].hello, @"", @"缺键应为空串而不是 nil");
    XCTAssertEqualObjects(cards[2].hello, @"");
}

- (void)testDirtyDataSafe {
    XCTAssertEqual([IMUserCard cardsFromArray:nil].count, 0);
    XCTAssertEqual([IMUserCard cardsFromArray:(id)@"not-an-array"].count, 0);
    // 数组里混入非字典项被跳过；tags 里的非字符串/空串被过滤。
    NSArray *arr = @[ @"garbage",
                      @{ @"user_id": @"u1", @"tags": @[ @"ok", @"", @(123), @"good" ] } ];
    NSArray<IMUserCard *> *cards = [IMUserCard cardsFromArray:arr];
    XCTAssertEqual(cards.count, 1);
    IMUserCard *c = cards.firstObject;
    XCTAssertEqualObjects(c.userID, @"u1");
    XCTAssertEqual(c.tags.count, 2); // 只剩 "ok"/"good"
}

@end
