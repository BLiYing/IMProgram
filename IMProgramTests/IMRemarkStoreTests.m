#import <XCTest/XCTest.h>

#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMRemarkStore.h"
#import "IMUserCard.h"

/// 好友备注名（仅本人可见、多端同步）的显示口径与全局缓存行为。
/// 盯的是最容易错的那一半——**清除**：改一个名字大家都会写对，把备注清空后各页仍显旧名才是坑。
@interface IMRemarkStoreTests : XCTestCase
@end

@implementation IMRemarkStoreTests

- (void)setUp {
    [super setUp];
    // 单例跨用例共享：用"权威空全集"清表，保证每个用例从零开始。
    [IMRemarkStore.sharedStore ingestFriends:@[] authoritative:YES];
}

- (void)tearDown {
    [IMRemarkStore.sharedStore ingestFriends:@[] authoritative:YES];
    [super tearDown];
}

- (IMUserCard *)cardWithID:(NSString *)uid nickname:(NSString *)nickname remark:(NSString *)remark {
    IMUserCard *c = [IMUserCard new];
    c.userID = uid;
    c.nickname = nickname;
    c.remark = remark;
    c.status = IMFriendStatusAccepted;
    return c;
}

#pragma mark - 存取与归一化

- (void)testDisplayNameFallsBackFromRemarkToNicknameToUID {
    IMRemarkStore *store = IMRemarkStore.sharedStore;
    XCTAssertEqualObjects([store displayNameForUser:@"bob" fallback:@"鲍勃"], @"鲍勃", @"无备注应回退昵称");
    XCTAssertEqualObjects([store displayNameForUser:@"bob" fallback:@""], @"bob", @"无备注无昵称应回退 uid");

    [store applyRemark:@"老王" forUser:@"bob"];
    XCTAssertEqualObjects([store displayNameForUser:@"bob" fallback:@"鲍勃"], @"老王", @"备注优先于昵称");
    XCTAssertEqualObjects([store remarkForUser:@"bob"], @"老王");
}

- (void)testBlankRemarkIsTreatedAsCleared {
    IMRemarkStore *store = IMRemarkStore.sharedStore;
    [store applyRemark:@"老王" forUser:@"bob"];
    [store applyRemark:@"   " forUser:@"bob"]; // 纯空白 = 清除，不能留成名字叫"   "的好友
    XCTAssertNil([store remarkForUser:@"bob"]);
    XCTAssertEqualObjects([store displayNameForUser:@"bob" fallback:@"鲍勃"], @"鲍勃");

    [store applyRemark:@"  老王  " forUser:@"bob"]; // 两端空白应被裁掉
    XCTAssertEqualObjects([store remarkForUser:@"bob"], @"老王");
}

#pragma mark - 变更通知

- (void)testNotificationFiresOnlyWhenValueActuallyChanges {
    IMRemarkStore *store = IMRemarkStore.sharedStore;
    __block NSInteger hits = 0;
    __block NSString *lastPeer = nil;
    id token = [NSNotificationCenter.defaultCenter addObserverForName:IMRemarkStoreDidChangeNotification
                                                               object:nil queue:nil
                                                           usingBlock:^(NSNotification *note) {
        hits++;
        lastPeer = note.userInfo[kIMRemarkPeerIDKey];
    }];

    [store applyRemark:@"老王" forUser:@"bob"];
    XCTAssertEqual(hits, 1);
    XCTAssertEqualObjects(lastPeer, @"bob", @"单点变更应带上是谁变了，供各页只刷相关行");

    [store applyRemark:@"老王" forUser:@"bob"]; // 同值重复写（每次刷新列表都会发生）
    XCTAssertEqual(hits, 1, @"值没变不该发通知，否则每次列表刷新都会引发一轮全页重绘");

    [store applyRemark:@"" forUser:@"bob"];
    XCTAssertEqual(hits, 2, @"清除是一次真实变更");

    [NSNotificationCenter.defaultCenter removeObserver:token];
}

#pragma mark - 全集 / 子集喂入

- (void)testAuthoritativeIngestClearsRemarksMissingFromTheList {
    IMRemarkStore *store = IMRemarkStore.sharedStore;
    [store ingestFriends:@[[self cardWithID:@"bob" nickname:@"鲍勃" remark:@"老王"],
                           [self cardWithID:@"carol" nickname:@"卡罗" remark:@"同事"]]
           authoritative:YES];
    XCTAssertEqualObjects([store remarkForUser:@"bob"], @"老王");

    // 别处（其它设备/网页端）把 bob 的备注清空了：新的全集里 bob 备注为空 → 本地必须跟着清。
    [store ingestFriends:@[[self cardWithID:@"bob" nickname:@"鲍勃" remark:@""],
                           [self cardWithID:@"carol" nickname:@"卡罗" remark:@"同事"]]
           authoritative:YES];
    XCTAssertNil([store remarkForUser:@"bob"]);
    XCTAssertEqualObjects([store remarkForUser:@"carol"], @"同事", @"没被改的人不受影响");

    // carol 已不在全集里（被删好友）→ 备注一并清掉，不留幽灵。
    [store ingestFriends:@[[self cardWithID:@"bob" nickname:@"鲍勃" remark:@""]] authoritative:YES];
    XCTAssertNil([store remarkForUser:@"carol"]);
}

- (void)testNonAuthoritativeIngestNeverClearsOthers {
    IMRemarkStore *store = IMRemarkStore.sharedStore;
    [store ingestFriends:@[[self cardWithID:@"bob" nickname:@"鲍勃" remark:@"老王"],
                           [self cardWithID:@"carol" nickname:@"卡罗" remark:@"同事"]]
           authoritative:YES];

    // 黑名单/待处理等子集（GET /friends?status=blocked）不能当全集用，否则会误清其他人的备注。
    [store ingestFriends:@[[self cardWithID:@"dave" nickname:@"戴夫" remark:@"房东"]] authoritative:NO];
    XCTAssertEqualObjects([store remarkForUser:@"bob"], @"老王");
    XCTAssertEqualObjects([store remarkForUser:@"carol"], @"同事");
    XCTAssertEqualObjects([store remarkForUser:@"dave"], @"房东");
}

- (void)testConversationIngestOnlyCoversPeersItMentions {
    IMRemarkStore *store = IMRemarkStore.sharedStore;
    [store applyRemark:@"同事" forUser:@"carol"];

    IMConversation *c = [IMConversation new];
    c.convID = @"u_alice_bob"; c.peer = @"bob"; c.peerNickname = @"鲍勃"; c.peerRemark = @"老王";
    IMConversation *g = [IMConversation new];
    g.convID = @"g_1"; g.isGroup = YES; g.name = @"技术群";
    [store ingestConversations:@[c, g]];

    XCTAssertEqualObjects([store remarkForUser:@"bob"], @"老王");
    XCTAssertEqualObjects([store remarkForUser:@"carol"], @"同事",
                          @"会话列表只含有会话的对端，不是好友全集，不能清掉没出现的人");
}

#pragma mark - 各页显示名口径

- (void)testConversationDisplayNamePriority {
    IMRemarkStore *store = IMRemarkStore.sharedStore;
    IMConversation *c = [IMConversation new];
    c.convID = @"u_alice_bob"; c.peer = @"bob"; c.peerNickname = @"鲍勃";
    XCTAssertEqualObjects(c.displayName, @"鲍勃", @"无备注 → 昵称");

    [store applyRemark:@"老王" forUser:@"bob"];
    XCTAssertEqualObjects(c.displayName, @"老王", @"好友备注 > 昵称");

    c.remark = @"这个会话";
    XCTAssertEqualObjects(c.displayName, @"这个会话", @"会话备注（G1）比好友备注更就近，优先");

    c.remark = nil;
    [store applyRemark:@"" forUser:@"bob"];
    XCTAssertEqualObjects(c.displayName, @"鲍勃", @"清除备注后必须回落昵称，不能留旧备注");

    c.peerNickname = @"";
    XCTAssertEqualObjects(c.displayName, @"bob", @"昵称也没有 → uid");
}

- (void)testGroupConversationDisplayNameIgnoresFriendRemark {
    IMConversation *g = [IMConversation new];
    g.convID = @"g_1"; g.isGroup = YES; g.name = @"技术群";
    XCTAssertEqualObjects(g.displayName, @"技术群");
    g.remark = @"老同事群";
    XCTAssertEqualObjects(g.displayName, @"老同事群", @"群用会话备注");
    g.remark = nil; g.name = @"";
    XCTAssertEqualObjects(g.displayName, @"群聊");
}

- (void)testUserCardDisplayNameUsesLiveRemarkNotItsOwnStaleSnapshot {
    IMRemarkStore *store = IMRemarkStore.sharedStore;
    IMUserCard *card = [self cardWithID:@"bob" nickname:@"鲍勃" remark:@"老王"];
    [store ingestFriends:@[card] authoritative:YES];
    XCTAssertEqualObjects(card.displayName, @"老王");

    // 备注在别处被清空，手里的卡片对象还留着旧 remark 快照——显示名必须以 store 为准。
    [store applyRemark:@"" forUser:@"bob"];
    XCTAssertEqualObjects(card.displayName, @"鲍勃", @"卡片快照过期时不能显示旧备注");
}

#pragma mark - 本地缓存落地（冷启动首屏）

- (void)testRemarkSurvivesDatabaseRoundTrip {
    NSString *name = [NSString stringWithFormat:@"im-remark-%@.sqlite", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];

    IMDatabase *writer = [[IMDatabase alloc] initWithFileURL:url];
    [writer useOwnerUserID:@"alice"];
    IMConversation *c = [IMConversation new];
    c.convID = @"u_alice_bob"; c.peer = @"bob"; c.peerNickname = @"鲍勃"; c.peerRemark = @"老王";
    [writer replaceCachedConversations:@[c]];
    [writer replaceCachedFriends:@[[self cardWithID:@"bob" nickname:@"鲍勃" remark:@"老王"]]];

    IMDatabase *reader = [[IMDatabase alloc] initWithFileURL:url];
    [reader useOwnerUserID:@"alice"];
    XCTAssertEqualObjects(reader.cachedConversations.firstObject.peerRemark, @"老王");
    XCTAssertEqualObjects(reader.cachedFriends.firstObject.remark, @"老王");

    // 单点写（本端改备注 / 其它设备推来的 remark 帧）也要同时落到会话行与好友行。
    [writer applyCachedRemark:@"小王" forPeer:@"bob"];
    IMDatabase *readerA = [[IMDatabase alloc] initWithFileURL:url];
    [readerA useOwnerUserID:@"alice"];
    XCTAssertEqualObjects(readerA.cachedConversations.firstObject.peerRemark, @"小王");
    XCTAssertEqualObjects(readerA.cachedFriends.firstObject.remark, @"小王");

    // 改成清除后再读：空串落库，读出来不能还是"老王"。
    IMConversation *cleared = [IMConversation new];
    cleared.convID = @"u_alice_bob"; cleared.peer = @"bob"; cleared.peerNickname = @"鲍勃";
    [writer replaceCachedConversations:@[cleared]];
    IMDatabase *reader2 = [[IMDatabase alloc] initWithFileURL:url];
    [reader2 useOwnerUserID:@"alice"];
    XCTAssertEqualObjects(reader2.cachedConversations.firstObject.peerRemark, @"");

    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

@end
