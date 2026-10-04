//  IMUserProfileCacheTests.m
//  uid → 名片的全局解析缓存（IMUserProfileCache）：账号隔离 / 负缓存 / 失败退避 / 淘汰 / 喂入口径。
//
//  错法全是**静默**的：换号后上一个账号的缓存漏进新账号（串号）、断网时以重绘频率打接口把 60 次/分的配额
//  烧光后一直 429（自己锁死自己）、一次抖动被记成十分钟的「查无此人」、群昵称漏到别的群气泡上。
//  所以按「会怎么错」钉，用例名就是那个错法。
//
//  不连网：只测 `peek`/`ingest`/私有的 `handleBatch:` 与 `flush`（无 token 分支）。单例跨用例共享：
//  每个用例用唯一账号 owner（换号即清空缓存，这也正是被测不变式）。app-hosted 测试。

#import <XCTest/XCTest.h>

#import "IMDatabase.h"
#import "IMDatabase+Ranges.h"
#import "IMGroupInfo.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Private.h"
#import "IMUserCard.h"
#import "IMUserProfileCache.h"

@interface IMUserProfileCache (TestHooks)
- (void)handleBatch:(NSArray<NSString *> *)batch owner:(NSString *)requestOwner users:(NSArray<IMUserCard *> *)users
            missing:(NSArray<NSString *> *)missing error:(NSError *)error;
- (void)flush;
@end

@interface IMUserProfileCacheTests : XCTestCase
@end

@implementation IMUserProfileCacheTests {
    IMUserProfileCache *_cache;
    NSString *_prevOwner;
    NSString *_owner;
    NSString *_savedToken;
}

- (void)setUp {
    [super setUp];
    _cache = IMUserProfileCache.sharedCache;
    // 宿主 App 若已登录（有 token），`cardForUserID:` 排队后 50ms 触发的 flush 会把测试用的假 uid 发给真服务端。
    // 置空 token：flush 走「没登录 → 清空队列」分支，不出网；tearDown 还原。
    _savedToken = IMHTTPService.sharedService.currentToken;
    IMHTTPService.sharedService.currentToken = nil;
    _prevOwner = IMDatabase.sharedDatabase.ownerUserID;
    _owner = [NSString stringWithFormat:@"upc_%@", NSUUID.UUID.UUIDString];
    [IMDatabase.sharedDatabase useOwnerUserID:_owner];
    [_cache peekCardForUserID:@"warm"]; // 触发一次 owner 同步，清掉上一个用例/宿主残留
}

- (void)tearDown {
    [IMDatabase.sharedDatabase useOwnerUserID:_prevOwner];
    [_cache peekCardForUserID:@"warm"];
    IMHTTPService.sharedService.currentToken = _savedToken;
    [super tearDown];
}

#pragma mark - 夹具

static IMUserCard *Card(NSString *uid, NSString *nick) {
    IMUserCard *c = [IMUserCard new];
    c.userID = uid; c.nickname = nick; c.username = @""; c.avatarURL = @"";
    return c;
}

- (NSMutableOrderedSet *)pending { return [_cache valueForKey:@"_pending"]; }
- (NSMutableDictionary *)missing { return [_cache valueForKey:@"_missing"]; }
- (NSMutableSet *)inflight { return [_cache valueForKey:@"_inflight"]; }

- (void)deliver:(NSArray<IMUserCard *> *)users missing:(NSArray<NSString *> *)missing error:(NSError *)error
          batch:(NSArray<NSString *> *)batch owner:(NSString *)owner {
    [_cache handleBatch:batch owner:owner users:users missing:missing error:error];
}

#pragma mark - 读 / 排队

/// peek 绝不发起请求（「有就锦上添花、没有也不值得联网」的地方用它）。
- (void)test_peek未命中不排队 {
    XCTAssertNil([_cache peekCardForUserID:@"u1"]);
    XCTAssertEqual([self pending].count, 0u);
}

/// 未命中排队一次（同 uid 反复问不重复入队）；空 uid / nil 不入队。
- (void)test_未命中排队且去重_空uid忽略 {
    XCTAssertNil([_cache cardForUserID:@"u1"]);
    XCTAssertNil([_cache cardForUserID:@"u1"]);
    XCTAssertNil([_cache cardForUserID:@""]);
    XCTAssertNil([_cache cardForUserID:nil]);
    XCTAssertEqualObjects([self pending].array, @[@"u1"]);
}

/// 命中返回缓存（后喂入的覆盖旧的：这些来源都比缓存新），且不再排队。
- (void)test_喂入后命中_后喂覆盖旧的 {
    [_cache ingestCards:@[Card(@"u1", @"旧")]];
    [_cache ingestCards:@[Card(@"u1", @"新")]];
    XCTAssertEqualObjects([_cache cardForUserID:@"u1"].nickname, @"新");
    XCTAssertEqual([self pending].count, 0u);
}

/// 喂入脏数据（nil 元素 / 非名片 / 空 uid）跳过，不崩。
- (void)test_喂入脏数据跳过 {
    NSArray *dirty = @[Card(@"", @"x"), (id)@"junk", Card(@"ok", @"好")];
    [_cache ingestCards:dirty];
    XCTAssertNotNil([_cache peekCardForUserID:@"ok"]);
    XCTAssertNil([_cache peekCardForUserID:@""]);
}

/// prefetch：只排未命中的；非字符串/空串跳过；已命中的不排。
- (void)test_prefetch只排未命中 {
    [_cache ingestCards:@[Card(@"hit", @"h")]];
    [_cache prefetchUserIDs:@[@"hit", @"miss1", @"", (id)@42, @"miss2", @"miss1"]];
    XCTAssertEqualObjects([self pending].array, (@[@"miss1", @"miss2"]));
}

#pragma mark - 群成员喂入：不能把群昵称漏到别的群

/// 缓存是跨会话的身份表：喂**全局昵称**，不喂群昵称——否则 A 群的群昵称会漏到 B 群的气泡上。
- (void)test_喂群成员用全局昵称不用群昵称 {
    IMGroupMember *m = [IMGroupMember new];
    m.userID = @"u1"; m.nickname = @"全局昵称"; m.groupNickname = @"A群里的叫法"; m.username = @"alice"; m.avatarURL = @"/a.png";
    [_cache ingestGroupMembers:@[m]];
    IMUserCard *c = [_cache peekCardForUserID:@"u1"];
    XCTAssertEqualObjects(c.nickname, @"全局昵称");
    XCTAssertEqualObjects(c.username, @"alice");
    XCTAssertEqualObjects(c.avatarURL, @"/a.png");
}

#pragma mark - 批量回来：负缓存与通知

/// 成功：命中的入缓存，查无此人的进负缓存；两者都通知（调用方据此停止转圈、落到兜底显示）。
- (void)test_批量成功_入缓存_负缓存_都通知 {
    XCTestExpectation *n = [self expectationForNotification:IMUserProfileCacheDidResolveNotification object:nil handler:^BOOL(NSNotification *note) {
        NSSet *ids = [NSSet setWithArray:note.userInfo[@"user_ids"]];
        return [ids isEqualToSet:[NSSet setWithArray:@[@"a", @"gone"]]];
    }];
    [self deliver:@[Card(@"a", @"甲")] missing:@[@"gone"] error:nil batch:@[@"a", @"gone"] owner:_owner];
    [self waitForExpectations:@[n] timeout:5];
    XCTAssertEqualObjects([_cache peekCardForUserID:@"a"].nickname, @"甲");
    XCTAssertNotNil([self missing][@"gone"]);
}

/// 负缓存有效期内再问：不排队（别每次滚动都重试一个已注销的人）。
- (void)test_负缓存期内不再排队 {
    [self deliver:@[] missing:@[@"gone"] error:nil batch:@[@"gone"] owner:_owner];
    XCTAssertNil([_cache cardForUserID:@"gone"]);
    XCTAssertEqual([self pending].count, 0u);
}

/// 负缓存过期（10 分钟）：允许再试一次，且过期记录被摘掉。
- (void)test_负缓存过期后允许重试 {
    [self deliver:@[] missing:@[@"gone"] error:nil batch:@[@"gone"] owner:_owner];
    [self missing][@"gone"] = [NSDate dateWithTimeIntervalSinceNow:-601];
    [_cache cardForUserID:@"gone"];
    XCTAssertEqualObjects([self pending].array, @[@"gone"]);
    XCTAssertNil([self missing][@"gone"]);
}

/// 之前判过「查无此人」、现在有人喂了名片：负缓存清掉，命中走缓存。
- (void)test_喂入后清负缓存 {
    [self deliver:@[] missing:@[@"x"] error:nil batch:@[@"x"] owner:_owner];
    [_cache ingestCards:@[Card(@"x", @"回来了")]];
    XCTAssertNil([self missing][@"x"]);
    XCTAssertEqualObjects([_cache peekCardForUserID:@"x"].nickname, @"回来了");
}

#pragma mark - 失败：不写负缓存，但要退避

/// 失败**不写负缓存**：一次网络抖动不能变成十分钟的「查无此人」。
- (void)test_失败不写负缓存 {
    NSError *err = [NSError errorWithDomain:@"net" code:-1 userInfo:nil];
    [self deliver:nil missing:nil error:err batch:@[@"u1"] owner:_owner];
    XCTAssertNil([self missing][@"u1"]);
}

/// 失败后进入退避：期间再问不排队（断网时 cellForRow 以重绘频率反复问，会把服务端配额烧光后一直 429）。
- (void)test_失败后退避期内不排队 {
    NSError *err = [NSError errorWithDomain:@"net" code:-1 userInfo:nil];
    [self deliver:nil missing:nil error:err batch:@[@"u1"] owner:_owner];
    XCTAssertNil([_cache cardForUserID:@"u2"]);
    XCTAssertEqual([self pending].count, 0u, @"退避中不排队");
}

/// 退避过了就能再问；一批成功立刻解除退避。
- (void)test_退避过去或成功后恢复排队 {
    NSError *err = [NSError errorWithDomain:@"net" code:-1 userInfo:nil];
    [self deliver:nil missing:nil error:err batch:@[@"u1"] owner:_owner];
    [_cache setValue:[NSDate dateWithTimeIntervalSinceNow:-1] forKey:@"_backoffUntil"];
    [_cache cardForUserID:@"u2"];
    XCTAssertEqualObjects([self pending].array, @[@"u2"]);

    [self deliver:nil missing:nil error:err batch:@[@"u3"] owner:_owner]; // 再失败一次 → 又在退避
    [self deliver:@[Card(@"u9", @"九")] missing:nil error:nil batch:@[@"u9"] owner:_owner]; // 成功 → 解除
    [_cache cardForUserID:@"u4"];
    XCTAssertTrue([[self pending] containsObject:@"u4"]);
}

/// 在途的 uid 不重复排队（已发出、未回来）；回来之后（无论成败）从在途里摘掉。
- (void)test_在途去重_回来后摘掉 {
    [[self inflight] addObject:@"u1"];
    XCTAssertNil([_cache cardForUserID:@"u1"]);
    XCTAssertEqual([self pending].count, 0u);
    [self deliver:@[Card(@"u1", @"一")] missing:nil error:nil batch:@[@"u1"] owner:_owner];
    XCTAssertFalse([[self inflight] containsObject:@"u1"]);
}

#pragma mark - 账号隔离（串号）

/// 换号清空一切：缓存、负缓存、待解析队列、在途、退避。上一个账号的东西一个都不能漏到新账号。
- (void)test_换号清空缓存_负缓存_队列_在途 {
    [_cache ingestCards:@[Card(@"a", @"甲")]];
    [self deliver:@[] missing:@[@"gone"] error:nil batch:@[@"gone"] owner:_owner];
    [_cache cardForUserID:@"queued"];
    [[self inflight] addObject:@"flying"];

    [IMDatabase.sharedDatabase useOwnerUserID:[_owner stringByAppendingString:@"_B"]];
    XCTAssertNil([_cache peekCardForUserID:@"a"]);
    XCTAssertEqual([self missing].count, 0u);
    XCTAssertEqual([self pending].count, 0u);
    XCTAssertEqual([self inflight].count, 0u, @"不清在途，新账号对同一批 uid 会永远排不进队");
    XCTAssertNil([_cache valueForKey:@"_backoffUntil"]);
}

/// 上一个账号发起的批次在换号后才回来：整批丢弃，不能写进新账号的缓存。
- (void)test_迟到的旧账号批次被丢弃 {
    NSString *oldOwner = _owner;
    [IMDatabase.sharedDatabase useOwnerUserID:[_owner stringByAppendingString:@"_B"]];
    XCTestExpectation *none = [self expectationForNotification:IMUserProfileCacheDidResolveNotification object:nil handler:nil];
    none.inverted = YES;
    [self deliver:@[Card(@"a", @"旧号的人")] missing:@[@"gone"] error:nil batch:@[@"a", @"gone"] owner:oldOwner];
    [self waitForExpectations:@[none] timeout:0.3];
    XCTAssertNil([_cache peekCardForUserID:@"a"]);
    XCTAssertNil([self missing][@"gone"]);
}

#pragma mark - 淘汰

/// 超 2000 条按插入序丢最老的：最老的没了、最新的在；总数不超上限。
- (void)test_超上限按插入序淘汰最老 {
    NSMutableArray *cards = [NSMutableArray array];
    for (int i = 0; i < 2005; i++) { [cards addObject:Card([NSString stringWithFormat:@"u%d", i], @"n")]; }
    [_cache ingestCards:cards];
    XCTAssertNil([_cache peekCardForUserID:@"u0"]);
    XCTAssertNil([_cache peekCardForUserID:@"u4"]);
    XCTAssertNotNil([_cache peekCardForUserID:@"u5"]);
    XCTAssertNotNil([_cache peekCardForUserID:@"u2004"]);
    XCTAssertEqual([[_cache valueForKey:@"_cards"] count], 2000u);
}

#pragma mark - flush

/// 没登录（无 token）：**清空待解析队列**，不发请求。留着会在登录后一次涌出一大批早已不在屏幕上的 uid。
- (void)test_无token时flush清空队列 {
    [_cache cardForUserID:@"u1"];
    XCTAssertEqual([self pending].count, 1u);
    [_cache flush];
    XCTAssertEqual([self pending].count, 0u);
}

@end
