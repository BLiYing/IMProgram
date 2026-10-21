//  IMAutoDeleteTests.m
//  自动删除消息：过期判定（读三端共用向量 IMServer/docs/conformance/auto_delete.json）+ 本机清理 / 入库闸 / 档位落库。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMAutoDelete.h"
#import "../IMProgram/Database/IMDatabase.h"
#import "../IMProgram/Database/IMDatabase+AutoDelete.h"
#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Models/IMMessageModel.h"
#import "../IMProgram/Network/IMHTTPService.h"
#import "../IMProgram/Network/IMProtocol.h"
#import "../IMProgram/Network/IMHTTPService+AutoDelete.h"

static NSString *const kADStubConv = @"ad-settings-stub-conv";

/// 只拦本测试专用会话的 PUT …/settings，记录 body 并回 ok。
@interface IMADSettingsStub : NSURLProtocol
@end
@implementation IMADSettingsStub
static NSMutableArray<NSDictionary *> *sADBodies;
+ (NSMutableArray<NSDictionary *> *)bodies { if (!sADBodies) { sADBodies = [NSMutableArray array]; } return sADBodies; }
+ (BOOL)canInitWithRequest:(NSURLRequest *)r { return [r.URL.path containsString:kADStubConv] && [r.URL.path hasSuffix:@"/settings"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    NSData *d = self.request.HTTPBody;
    if (!d && self.request.HTTPBodyStream) {
        NSInputStream *in = self.request.HTTPBodyStream; [in open];
        NSMutableData *m = [NSMutableData data]; uint8_t buf[1024]; NSInteger n;
        while ((n = [in read:buf maxLength:sizeof buf]) > 0) { [m appendBytes:buf length:(NSUInteger)n]; }
        [in close]; d = m;
    }
    id o = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    @synchronized (IMADSettingsStub.class) { [IMADSettingsStub.bodies addObject:[o isKindOfClass:NSDictionary.class] ? o : @{}]; }
    NSData *resp = [NSJSONSerialization dataWithJSONObject:@{ @"code": @0, @"message": @"ok", @"data": @{} } options:0 error:NULL];
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                     headerFields:@{ @"Content-Type": @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:resp];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static IMConversation *IMADConv(NSDictionary *d) { return [IMConversation conversationsFromArray:@[d]].firstObject; }

@interface IMAutoDeleteTests : XCTestCase
@end

@implementation IMAutoDeleteTests

- (NSDictionary *)vectors {
    NSString *repo = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString *path = [[repo stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"IMServer/docs/conformance/auto_delete.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"找不到共用向量 %@", path);
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : @{};
}

#pragma mark - 共用向量

- (void)testExpiredVectors {
    NSArray *cases = [self vectors][@"expired"];
    XCTAssertGreaterThanOrEqual(cases.count, 10u);
    for (NSDictionary *c in cases) {
        BOOL got = IMAutoDeleteExpired([c[@"ts"] longLongValue], [c[@"sec"] longLongValue], [c[@"now"] longLongValue]);
        XCTAssertEqual(got, [c[@"expect"] boolValue], @"%@", c[@"name"]);
    }
}

- (void)testFloorTsVectors {
    NSArray *cases = [self vectors][@"floor_ts"];
    XCTAssertGreaterThanOrEqual(cases.count, 3u);
    for (NSDictionary *c in cases) {
        XCTAssertEqual(IMAutoDeleteFloorTs([c[@"sec"] longLongValue], [c[@"now"] longLongValue]), [c[@"expect"] longLongValue]);
    }
}

- (void)testValidSecVectors {
    NSDictionary *v = [self vectors];
    for (NSNumber *n in v[@"valid_sec"]) { XCTAssertTrue(IMAutoDeleteIsValidSec(n.longLongValue), @"%@", n); }
    for (NSNumber *n in v[@"invalid_sec"]) { XCTAssertFalse(IMAutoDeleteIsValidSec(n.longLongValue), @"%@", n); }
    XCTAssertEqualObjects(IMAutoDeleteTiers(), (@[@0, @86400, @604800, @2592000]));
}

#pragma mark - 确认框触发 / JSON

- (void)testNeedsConfirm {
    XCTAssertTrue(IMAutoDeleteNeedsConfirm(0, 86400));              // 关 -> 开
    XCTAssertTrue(IMAutoDeleteNeedsConfirm(2592000, 604800));       // 缩短
    XCTAssertFalse(IMAutoDeleteNeedsConfirm(86400, 604800));        // 放宽
    XCTAssertFalse(IMAutoDeleteNeedsConfirm(86400, 0));             // 关闭
    XCTAssertFalse(IMAutoDeleteNeedsConfirm(86400, 86400));         // 不变
    XCTAssertFalse(IMAutoDeleteNeedsConfirm(0, 0));
}

- (void)testSecFromJSONAndConversationParse {
    XCTAssertEqual(IMAutoDeleteSecFromJSON(@604800), 604800);
    XCTAssertEqual(IMAutoDeleteSecFromJSON(@12345), 0);   // 非白名单当关
    XCTAssertEqual(IMAutoDeleteSecFromJSON(@"86400"), 0);  // 非数字当关
    XCTAssertEqual(IMAutoDeleteSecFromJSON(nil), 0);
    IMConversation *c = IMADConv(@{ @"conv_id": @"u_1_u_2", @"auto_delete_sec": @86400 });
    XCTAssertEqual(c.autoDeleteSec, 86400);
    XCTAssertEqual(IMADConv(@{ @"conv_id": @"u_1_u_2" }).autoDeleteSec, 0); // 老响应默认 0
}

#pragma mark - 库：档位落库 / 清理 / 入库闸

- (IMDatabase *)freshDB:(NSString *)owner {
    NSString *name = [NSString stringWithFormat:@"im-autodel-%@.sqlite", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:url];
    [db useOwnerUserID:owner];
    return db;
}

- (IMMessageModel *)msg:(NSString *)conv seq:(int64_t)seq from:(NSString *)from ts:(int64_t)ts content:(NSString *)content {
    IMMessageModel *m = [IMMessageModel new];
    m.convID = conv; m.from = from; m.to = [from isEqualToString:@"me"] ? @"bob" : @"me";
    m.contentType = @"text"; m.content = content; m.convSeq = seq; m.timestamp = ts;
    return m;
}

- (void)testSecPersistsAndSurvivesConversationSnapshotReplace {
    IMDatabase *db = [self freshDB:@"ad-owner-1"];
    XCTAssertEqual([db autoDeleteSecForConv:@"c1"], 0);
    XCTAssertTrue([db setAutoDeleteSec:86400 forConv:@"c1"]);
    XCTAssertFalse([db setAutoDeleteSec:86400 forConv:@"c1"], @"未变化应返回 NO");
    XCTAssertEqual([db autoDeleteSecForConv:@"c1"], 86400);
    XCTAssertEqualObjects([db autoDeleteActiveConvs], (@{ @"c1": @86400 }));
    // 整表快照：以服务端列表为准（档位被别的端改了 / 会话已不在列表）
    IMConversation *c = IMADConv(@{ @"conv_id": @"c2", @"auto_delete_sec": @604800 });
    [db replaceCachedConversations:@[c]];
    XCTAssertEqual([db autoDeleteSecForConv:@"c1"], 0);
    XCTAssertEqual([db autoDeleteSecForConv:@"c2"], 604800);
    XCTAssertFalse([db setAutoDeleteSec:777 forConv:@"c2"] && [db autoDeleteSecForConv:@"c2"] == 777, @"非白名单落成 0");
}

- (void)testSweepDeletesExpiredKeepsFreshAndRecomputesSummary {
    IMDatabase *db = [self freshDB:@"ad-owner-2"];
    NSString *conv = @"u_ad-owner-2_u_bob";
    int64_t now = 10 * 86400 * 1000LL, day = 86400 * 1000LL;
    IMConversation *c = IMADConv(@{ @"conv_id": conv, @"peer": @"bob", @"auto_delete_sec": @0,
        @"unread": @2, @"read_seq": @1, @"latest_conv_seq": @3 });
    [db replaceCachedConversations:@[c]];
    [db saveIncomingMessage:[self msg:conv seq:1 from:@"bob" ts:now - 3 * day content:@"老1"] advancingSyncedConvSeq:1];
    [db saveIncomingMessage:[self msg:conv seq:2 from:@"bob" ts:now - 2 * day content:@"老2"] advancingSyncedConvSeq:2];
    [db saveIncomingMessage:[self msg:conv seq:3 from:@"me" ts:now - 100 content:@"新3"] advancingSyncedConvSeq:3];

    [db setAutoDeleteSec:86400 forConv:conv]; // 消息先入库（入库时档位还没开），再开档位
    NSArray<NSNumber *> *removed = [db deleteExpiredMessagesForConv:conv floorTs:IMAutoDeleteFloorTs(86400, now)];
    XCTAssertEqualObjects(removed, (@[@1, @2]));
    NSArray<IMMessageModel *> *left = [db messagesForConv:conv];
    XCTAssertEqual(left.count, 1u);
    XCTAssertEqual(left.firstObject.convSeq, 3);
    XCTAssertEqual([db syncedConvSeqForConv:conv], 3, @"游标不动：清理后不能把已删段当缺口重拉");
    // 摘要指向的最后一条（seq3）没过期：预览不变
    XCTAssertEqual([db cachedConversationWithID:conv].unread, 1, @"read_seq=1：被删的 seq2 是未读（扣 1），seq1 已读不扣");
    // 再扫一次幂等
    XCTAssertEqual([db deleteExpiredMessagesForConv:conv floorTs:IMAutoDeleteFloorTs(86400, now)].count, 0u);
}

- (void)testAllExpiredLeavesRowWithEmptyPreview {
    IMDatabase *db = [self freshDB:@"ad-owner-3"];
    NSString *conv = @"u_ad-owner-3_u_bob";
    int64_t now = 5 * 86400 * 1000LL;
    IMConversation *c = IMADConv(@{ @"conv_id": conv, @"peer": @"bob", @"auto_delete_sec": @0,
        @"latest_conv_seq": @1 });
    c.lastContent = @"很久以前"; c.lastContentType = @"text"; c.timestamp = 1000; c.unread = 1;
    [db replaceCachedConversations:@[c]];
    [db saveIncomingMessage:[self msg:conv seq:1 from:@"bob" ts:1000 content:@"很久以前"] advancingSyncedConvSeq:1];
    [db setAutoDeleteSec:86400 forConv:conv];
    XCTAssertEqual([db deleteExpiredMessagesForConv:conv floorTs:IMAutoDeleteFloorTs(86400, now)].count, 1u);
    IMConversation *row = [db cachedConversationWithID:conv];
    XCTAssertNotNil(row, @"会话行保留");
    XCTAssertEqualObjects(row.lastContent ?: @"", @"", @"预览为空");
    XCTAssertEqual(row.unread, 0);
}

- (void)testIngestGateDropsExpiredButKeepsFreshAndPending {
    IMDatabase *db = [self freshDB:@"ad-owner-4"];
    NSString *conv = @"u_ad-owner-4_u_bob";
    [db replaceCachedConversations:@[IMADConv(@{ @"conv_id": conv, @"peer": @"bob", @"auto_delete_sec": @86400 })]];
    int64_t nowMs = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    IMMessageModel *old = [self msg:conv seq:1 from:@"bob" ts:nowMs - 2 * 86400000LL content:@"过期"];
    IMMessageModel *fresh = [self msg:conv seq:2 from:@"bob" ts:nowMs - 1000 content:@"新鲜"];
    XCTAssertTrue([db autoDeleteDropsIncoming:old]);
    XCTAssertFalse([db autoDeleteDropsIncoming:fresh]);
    NSArray *kept = [db messagesDroppingAutoDeleteExpired:@[old, fresh]];
    XCTAssertEqual(kept.count, 1u);
    // 落库闸：过期的不进库（返回 YES = 不是失败），新鲜的进库
    XCTAssertTrue([db saveIncomingMessage:old advancingSyncedConvSeq:1]);
    XCTAssertTrue([db saveIncomingMessage:fresh advancingSyncedConvSeq:2]);
    NSArray<IMMessageModel *> *stored = [db messagesForConv:conv];
    XCTAssertEqual(stored.count, 1u);
    XCTAssertEqualObjects(stored.firstObject.content, @"新鲜");
    // 关闭档位后同样的旧消息正常入库
    [db setAutoDeleteSec:0 forConv:conv];
    XCTAssertFalse([db autoDeleteDropsIncoming:old]);
}

/// msg_op 事件行不受过期闸影响（设计 §4）：即便时间戳已过期也照常放行，只有正文行被丢。
- (void)testEventRowsBypassExpiryGate {
    IMDatabase *db = [self freshDB:@"ad-owner-5"];
    NSString *conv = @"u_ad-owner-5_u_bob";
    [db replaceCachedConversations:@[IMADConv(@{ @"conv_id": conv, @"peer": @"bob", @"auto_delete_sec": @86400 })]];
    int64_t nowMs = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    IMMessageModel *body = [self msg:conv seq:1 from:@"bob" ts:nowMs - 2 * 86400000LL content:@"过期正文"];
    IMMessageModel *op = [self msg:conv seq:2 from:@"bob" ts:nowMs - 2 * 86400000LL content:@""];
    op.contentType = kIMTypeMsgOp;
    XCTAssertTrue([db autoDeleteDropsIncoming:body]);
    XCTAssertFalse([db autoDeleteDropsIncoming:op], @"事件行不能被过期闸吃掉");
    NSArray *kept = [db messagesDroppingAutoDeleteExpired:@[body, op]];
    XCTAssertEqual(kept.count, 1u);
    XCTAssertEqual(((IMMessageModel *)kept.firstObject).convSeq, 2);
}

#pragma mark - PUT settings 是否带 auto_delete_sec

- (NSDictionary *)putSettingsWithAutoDeleteSec:(NSNumber *)sec viaLegacyEntry:(BOOL)legacy {
    IMHTTPService *svc = IMHTTPService.sharedService;
    NSString *oldHost = svc.host;
    if (svc.host.length == 0) { svc.host = @"127.0.0.1:59391"; }
    @synchronized (IMADSettingsStub.class) { [IMADSettingsStub.bodies removeAllObjects]; }
    [NSURLProtocol registerClass:IMADSettingsStub.class];
    XCTestExpectation *e = [self expectationWithDescription:@"put"];
    void (^done)(NSError *) = ^(NSError *err) { XCTAssertNil(err); [e fulfill]; };
    if (legacy) {
        [svc updateConversationSettingsWithToken:@"t" convID:kADStubConv pinnedAt:123 muted:NO muteUntil:nil markedUnread:NO completion:done];
    } else {
        [svc updateConversationSettingsWithToken:@"t" convID:kADStubConv pinnedAt:0 muted:NO muteUntil:nil markedUnread:NO
                                   autoDeleteSec:sec completion:done];
    }
    [self waitForExpectationsWithTimeout:5 handler:nil];
    [NSURLProtocol unregisterClass:IMADSettingsStub.class];
    svc.host = oldHost;
    @synchronized (IMADSettingsStub.class) { return IMADSettingsStub.bodies.lastObject ?: @{}; }
}

/// 置顶 / 免打扰 / 标未读类 PUT 一律省略 auto_delete_sec（服务端保留原值，不拿本机可能过期的缓存盖掉别端刚设的档位）。
- (void)testPinStylePutOmitsAutoDeleteSec {
    // 本机库里即便有非零档位也不能被带出去
    [IMDatabase.sharedDatabase setAutoDeleteSec:IMAutoDeleteSecWeek forConv:kADStubConv];
    NSDictionary *body = [self putSettingsWithAutoDeleteSec:nil viaLegacyEntry:YES];
    XCTAssertEqualObjects(body[@"pinned_at"], @123);
    XCTAssertNil(body[@"auto_delete_sec"], @"%@", body);
    XCTAssertNil([self putSettingsWithAutoDeleteSec:nil viaLegacyEntry:NO][@"auto_delete_sec"]);
    [IMDatabase.sharedDatabase setAutoDeleteSec:0 forConv:kADStubConv];
}

- (void)testExplicitTierPutCarriesAutoDeleteSec {
    NSDictionary *body = [self putSettingsWithAutoDeleteSec:@(IMAutoDeleteSecDay) viaLegacyEntry:NO];
    XCTAssertEqualObjects(body[@"auto_delete_sec"], @(IMAutoDeleteSecDay));
    XCTAssertEqualObjects([self putSettingsWithAutoDeleteSec:@0 viaLegacyEntry:NO][@"auto_delete_sec"], @0); // 显式关闭也要带
}

@end
