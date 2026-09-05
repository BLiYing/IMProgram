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
