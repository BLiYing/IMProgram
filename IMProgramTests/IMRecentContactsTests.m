//  IMRecentContactsTests.m
//  通讯录首页「最近联系」取数规则（设计 ../IMServer/docs/design/ORG_DIRECTORY_DESIGN.md §7.1；
//  对端同名用例：im-web `recentContacts.test.ts`、im-android `RecentContactsTest.kt`）。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Contacts/IMRecentContacts.h"
#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Common/IMAccountIdentity.h"

static NSString * const kSelfUID = @"1000000001";

@interface IMRecentContactsTests : XCTestCase
@end

@implementation IMRecentContactsTests

- (IMConversation *)singleWithID:(NSString *)convID peer:(NSString *)peer timestamp:(int64_t)timestamp {
    IMConversation *c = [IMConversation new];
    c.convID = convID;
    c.peer = peer;
    c.timestamp = timestamp;
    return c;
}

- (NSArray<NSString *> *)pickedIDs:(NSArray<IMConversation *> *)conversations {
    return [IMRecentContacts(conversations, kSelfUID, nil) valueForKey:@"convID"];
}

- (void)testOrdersByLastMessageTimeDescending {
    NSArray *convs = @[[self singleWithID:@"c-old" peer:@"u1" timestamp:100],
                       [self singleWithID:@"c-new" peer:@"u2" timestamp:300],
                       [self singleWithID:@"c-mid" peer:@"u3" timestamp:200]];
    XCTAssertEqualObjects([self pickedIDs:convs], (@[@"c-new", @"c-mid", @"c-old"]));
}

- (void)testGroupsAreExcluded {
    IMConversation *group = [self singleWithID:@"g1" peer:@"" timestamp:900];
    group.isGroup = YES;
    IMConversation *groupWithPeer = [self singleWithID:@"g2" peer:@"u9" timestamp:800]; // 脏数据：群带了 peer 也不进
    groupWithPeer.isGroup = YES;
    NSArray *convs = @[group, groupWithPeer, [self singleWithID:@"c1" peer:@"u1" timestamp:100]];
    XCTAssertEqualObjects([self pickedIDs:convs], (@[@"c1"]));
}

- (void)testSelfSystemAndDeletedPeersAreExcluded {
    IMConversation *deleted = [self singleWithID:@"c-deleted" peer:@"u-deleted" timestamp:700];
    deleted.peerDeleted = YES;
    NSArray *convs = @[[self singleWithID:@"c-self" peer:kSelfUID timestamp:900],
                       [self singleWithID:@"c-sys" peer:IMSystemUserID timestamp:800],
                       deleted,
                       [self singleWithID:@"c-nopeer" peer:@"" timestamp:600],
                       [self singleWithID:@"c1" peer:@"u1" timestamp:100]];
    XCTAssertEqualObjects([self pickedIDs:convs], (@[@"c1"]));
}

/// 会话行的 peerDeleted 不落本地库：冷启动读缓存时它是 NO，要靠调用方给的判定（IMRemarkStore 的登记）补上。
- (void)testDeletedPredicateExcludesPeersNotFlaggedOnTheRow {
    NSArray *convs = @[[self singleWithID:@"c-gone" peer:@"u-gone" timestamp:900],
                       [self singleWithID:@"c1" peer:@"u1" timestamp:100]];
    NSArray<IMConversation *> *picked = IMRecentContacts(convs, kSelfUID, ^BOOL(NSString *peerUID) {
        return [peerUID isEqualToString:@"u-gone"];
    });
    XCTAssertEqualObjects([picked valueForKey:@"convID"], (@[@"c1"]));
}

- (void)testConversationsWithoutAnyMessageAreExcluded {
    NSArray *convs = @[[self singleWithID:@"c-empty" peer:@"u1" timestamp:0],
                       [self singleWithID:@"c-negative" peer:@"u2" timestamp:-5],
                       [self singleWithID:@"c1" peer:@"u3" timestamp:1]];
    XCTAssertEqualObjects([self pickedIDs:convs], (@[@"c1"]));
}

- (void)testEqualTimestampsFallBackToConvIDAscendingRegardlessOfInputOrder {
    IMConversation *a = [self singleWithID:@"c-a" peer:@"u1" timestamp:500];
    IMConversation *b = [self singleWithID:@"c-b" peer:@"u2" timestamp:500];
    IMConversation *c = [self singleWithID:@"c-c" peer:@"u3" timestamp:500];
    XCTAssertEqualObjects([self pickedIDs:(@[c, a, b])], (@[@"c-a", @"c-b", @"c-c"]));
    XCTAssertEqualObjects([self pickedIDs:(@[b, c, a])], (@[@"c-a", @"c-b", @"c-c"]));
}

- (void)testTakesAtMostLimitAndFewerWhenNotEnough {
    NSMutableArray<IMConversation *> *convs = [NSMutableArray array];
    for (int64_t i = 1; i <= 8; i++) {
        [convs addObject:[self singleWithID:[NSString stringWithFormat:@"c%lld", i]
                                       peer:[NSString stringWithFormat:@"u%lld", i] timestamp:i * 10]];
    }
    XCTAssertEqual(kIMRecentContactsLimit, 5u);
    XCTAssertEqualObjects([self pickedIDs:convs], (@[@"c8", @"c7", @"c6", @"c5", @"c4"]));
    XCTAssertEqualObjects([self pickedIDs:[convs subarrayWithRange:NSMakeRange(0, 2)]], (@[@"c2", @"c1"]));
    XCTAssertEqualObjects([self pickedIDs:@[]], @[]);
    XCTAssertEqualObjects(IMRecentContacts(nil, kSelfUID, nil), @[]);
}

- (void)testPinnedUnreadAndMutedDoNotAffectOrder {
    IMConversation *pinnedOld = [self singleWithID:@"c-pinned" peer:@"u1" timestamp:100];
    pinnedOld.pinnedAt = 999999;
    pinnedOld.unread = 42;
    IMConversation *mutedNew = [self singleWithID:@"c-muted" peer:@"u2" timestamp:300];
    mutedNew.muted = YES;
    IMConversation *plain = [self singleWithID:@"c-plain" peer:@"u3" timestamp:200];
    XCTAssertEqualObjects([self pickedIDs:(@[pinnedOld, mutedNew, plain])], (@[@"c-muted", @"c-plain", @"c-pinned"]));
}

/// 同时间的次序键是会话 ID 的 **UTF-16 码元序**（三端都能逐字节复现），不是本地化 / 大小写不敏感序：
/// 码元序下 "B"(0x42) < "Z"(0x5A) < "a"(0x61) < "b"(0x62) < "á"(0xE1)；localizedCompare 会排成
/// a á B b Z 一类，大小写不敏感比较会让 B / b 并列或交换——任何一种都让本用例变红。
- (void)testEqualTimestampTieBreakIsCodeUnitOrderNotLocalized {
    NSArray<NSString *> *ids = @[@"b", @"\u00E1", @"Z", @"a", @"B"];
    NSMutableArray<IMConversation *> *convs = [NSMutableArray array];
    for (NSUInteger i = 0; i < ids.count; i++) {
        [convs addObject:[self singleWithID:ids[i] peer:[NSString stringWithFormat:@"u%lu", (unsigned long)i] timestamp:500]];
    }
    XCTAssertEqualObjects([self pickedIDs:convs], (@[@"B", @"Z", @"a", @"b", @"\u00E1"]));
}

/// 会话 ID 为空（脏数据 / 本地壳行）不进：没有它就既排不了序、也进不了聊天。
- (void)testEmptyConvIDIsExcluded {
    NSArray *convs = @[[self singleWithID:@"" peer:@"u1" timestamp:900],
                       [self singleWithID:nil peer:@"u2" timestamp:800],
                       [self singleWithID:@"c3" peer:@"u3" timestamp:100]];
    XCTAssertEqualObjects([self pickedIDs:convs], (@[@"c3"]));
}

@end
