//  IMContactGroupCacheTests.m
//  任务5：好友/群组本地快照（断网离线首屏）落库与账号隔离回归。

#import <XCTest/XCTest.h>

#import "IMDatabase.h"
#import "IMDatabase+RosterCache.h"
#import "IMUserCard.h"
#import "IMGroupInfo.h"

@interface IMContactGroupCacheTests : XCTestCase
@end

@implementation IMContactGroupCacheTests

- (NSURL *)temporaryDatabaseURL {
    NSString *name = [NSString stringWithFormat:@"im-cg-test-%@.sqlite", NSUUID.UUID.UUIDString];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

- (IMUserCard *)friendWithID:(NSString *)uid nickname:(NSString *)nick {
    IMUserCard *c = [IMUserCard new];
    c.userID = uid;
    c.nickname = nick;
    c.avatarURL = [@"/avatars/" stringByAppendingString:uid];
    c.status = IMFriendStatusAccepted;
    c.blocked = NO;
    c.updatedAt = 123456;
    return c;
}

- (IMGroupInfo *)groupWithID:(NSString *)convID name:(NSString *)name owner:(NSString *)owner {
    IMGroupInfo *g = [IMGroupInfo new];
    g.convID = convID;
    g.name = name;
    g.avatarURL = [@"/avatars/" stringByAppendingString:convID];
    g.owner = owner;
    g.createdAt = 999;
    g.myRole = IMGroupRoleOwner;
    return g;
}

- (void)testFriendsPersistAcrossDatabaseInstances {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *writer = [[IMDatabase alloc] initWithFileURL:url];
    [writer useOwnerUserID:@"1001"];
    [writer replaceCachedFriends:@[[self friendWithID:@"1002" nickname:@"小二"],
                                   [self friendWithID:@"1003" nickname:@"小三"]]];

    IMDatabase *reader = [[IMDatabase alloc] initWithFileURL:url];
    [reader useOwnerUserID:@"1001"];
    NSArray<IMUserCard *> *loaded = reader.cachedFriends;

    XCTAssertEqual(loaded.count, 2);
    XCTAssertEqualObjects(loaded[0].userID, @"1002");      // 顺序保持（sort_order）
    XCTAssertEqualObjects(loaded[0].nickname, @"小二");
    XCTAssertEqual(loaded[0].status, IMFriendStatusAccepted);
    XCTAssertEqualObjects(loaded[1].userID, @"1003");
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

/// 通讯录据指纹决定「名单没变就不重写快照」。漏掉任何一列 = 那一列改了也判成没变 → 离线首屏永远是旧值。
- (void)testFriendsFingerprintIgnoresOrderButCatchesEveryPersistedColumn {
    IMUserCard *a = [self friendWithID:@"1002" nickname:@"小二"];
    IMUserCard *b = [self friendWithID:@"1003" nickname:@"小三"];
    NSDictionary *base = IMCachedFriendsFingerprint(@[a, b]);
    XCTAssertEqualObjects(IMCachedFriendsFingerprint(@[b, a]), base, @"顺序不参与（服务端同 updated_at 时顺序不稳定）");

    NSArray<NSString *> *columns = @[ @"nickname", @"avatarURL", @"status", @"blocked", @"updatedAt", @"remark" ];
    NSArray<void (^)(IMUserCard *)> *mutations = @[
        ^(IMUserCard *c) { c.nickname = @"改名"; },
        ^(IMUserCard *c) { c.avatarURL = @"/avatars/new"; },
        ^(IMUserCard *c) { c.status = IMFriendStatusBlocked; },
        ^(IMUserCard *c) { c.blocked = YES; },
        ^(IMUserCard *c) { c.updatedAt = 654321; },
        ^(IMUserCard *c) { c.remark = @"备注"; },
    ];
    [mutations enumerateObjectsUsingBlock:^(void (^mutate)(IMUserCard *), NSUInteger i, BOOL *stop) {
        IMUserCard *changed = [self friendWithID:@"1002" nickname:@"小二"];
        mutate(changed);
        XCTAssertNotEqualObjects(IMCachedFriendsFingerprint(@[changed, b]), base, @"改了 %@ 却判为没变", columns[i]);
    }];
    XCTAssertNotEqualObjects(IMCachedFriendsFingerprint(@[a]), base, @"少了一个人却判为没变");
    IMUserCard *noID = [self friendWithID:@"" nickname:@"没有 uid"];
    XCTAssertEqualObjects(IMCachedFriendsFingerprint(@[a, b, noID]), base, @"空 uid 本就不落库，不该让指纹变");
}

/// 冷启动的快照指纹来自读回的缓存：读回来的与写进去的必须指纹相同，否则每次启动后第一次刷新都会白写一遍。
- (void)testFriendsFingerprintSurvivesDatabaseRoundTrip {
    NSURL *url = [self temporaryDatabaseURL];
    IMUserCard *a = [self friendWithID:@"1002" nickname:@"小二"];
    a.remark = @"二哥";
    IMUserCard *b = [self friendWithID:@"1003" nickname:@"小三"];
    b.blocked = YES;
    IMDatabase *writer = [[IMDatabase alloc] initWithFileURL:url];
    [writer useOwnerUserID:@"1001"];
    BOOL written = [writer replaceCachedFriends:@[a, b]]; // 数组字面量的逗号不能直接进 XCTAssert 宏参数
    XCTAssertTrue(written, @"正常写入应报成功——调用方只在成功时记指纹");

    IMDatabase *reader = [[IMDatabase alloc] initWithFileURL:url];
    [reader useOwnerUserID:@"1001"];
    XCTAssertEqualObjects(IMCachedFriendsFingerprint(reader.cachedFriends), IMCachedFriendsFingerprint(@[a, b]));
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testGroupsPersistAcrossDatabaseInstances {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *writer = [[IMDatabase alloc] initWithFileURL:url];
    [writer useOwnerUserID:@"1001"];
    [writer replaceCachedGroups:@[[self groupWithID:@"g_a" name:@"1001群" owner:@"1001"]]];

    IMDatabase *reader = [[IMDatabase alloc] initWithFileURL:url];
    [reader useOwnerUserID:@"1001"];
    IMGroupInfo *loaded = reader.cachedGroups.firstObject;

    XCTAssertEqual(reader.cachedGroups.count, 1);
    XCTAssertEqualObjects(loaded.convID, @"g_a");
    XCTAssertEqualObjects(loaded.name, @"1001群");
    XCTAssertEqualObjects(loaded.owner, @"1001");
    XCTAssertEqual(loaded.myRole, IMGroupRoleOwner);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testFriendsAndGroupsAreOwnerIsolated {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];

    [database useOwnerUserID:@"1001"];
    [database replaceCachedFriends:@[[self friendWithID:@"1002" nickname:@"一号的好友"]]];
    [database replaceCachedGroups:@[[self groupWithID:@"g_1001" name:@"一号的群" owner:@"1001"]]];

    [database useOwnerUserID:@"2001"];
    XCTAssertEqual(database.cachedFriends.count, 0); // 另一账号看不到
    XCTAssertEqual(database.cachedGroups.count, 0);
    [database replaceCachedFriends:@[[self friendWithID:@"2002" nickname:@"二号的好友"]]];

    [database useOwnerUserID:@"1001"];
    XCTAssertEqualObjects(database.cachedFriends.firstObject.userID, @"1002");
    XCTAssertEqualObjects(database.cachedGroups.firstObject.convID, @"g_1001");
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

- (void)testAuthoritativeEmptySnapshotClearsOnlyCurrentOwner {
    NSURL *url = [self temporaryDatabaseURL];
    IMDatabase *database = [[IMDatabase alloc] initWithFileURL:url];
    [database useOwnerUserID:@"1001"];
    [database replaceCachedFriends:@[[self friendWithID:@"1002" nickname:@"小二"]]];
    [database replaceCachedGroups:@[[self groupWithID:@"g_a" name:@"群" owner:@"1001"]]];
    [database useOwnerUserID:@"2001"];
    [database replaceCachedFriends:@[[self friendWithID:@"2002" nickname:@"小二号"]]];

    // 权威空列表（账号删光好友/群）只清当前账号，不误伤其他账号缓存。
    [database replaceCachedFriends:@[]];
    [database replaceCachedGroups:@[]];
    XCTAssertEqual(database.cachedFriends.count, 0);

    [database useOwnerUserID:@"1001"];
    XCTAssertEqual(database.cachedFriends.count, 1);
    XCTAssertEqual(database.cachedGroups.count, 1);
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

@end
