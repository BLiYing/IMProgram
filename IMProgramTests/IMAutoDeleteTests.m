//  IMAutoDeleteTests.m
//  自动删除消息 v2（会话级共享、不追溯）：过期判定（读三端共用向量 IMServer/docs/conformance/auto_delete.json）+ 本机清理 / 入库闸 / 设置落库 / 迁移。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMAutoDelete.h"
#import "../IMProgram/Common/IMLocalization.h"
#import "../IMProgram/Database/IMDatabase.h"
#import "../IMProgram/Database/IMDatabase+AutoDelete.h"
#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Models/IMMessageModel.h"
#import "../IMProgram/Network/IMHTTPService.h"
#import "../IMProgram/Network/IMProtocol.h"
#import "../IMProgram/Network/IMHTTPService+AutoDelete.h"
#import "../IMProgram/Network/IMSocketManager+AutoDelete.h"
#import "../IMProgram/Modules/Me/IMAutoDeleteTierViewController.h"
#import <FMDB/FMDB.h>

static NSString *const kADStubConv = @"ad-settings-stub-conv";

/// 只拦本测试专用会话的 PUT …/settings，记录 body 并回 ok。
@interface IMADSettingsStub : NSURLProtocol
@end
@implementation IMADSettingsStub
static NSMutableArray<NSDictionary *> *sADBodies;
static NSDictionary *IMADStubReply; // 非 nil 时按它回包（测 300204 / 回包带 sec+from）
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
    NSDictionary *reply = IMADStubReply ?: @{ @"code": @0, @"message": @"ok", @"data": @{} };
    NSData *resp = [NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL];
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
    XCTAssertGreaterThanOrEqual(cases.count, 20u);
    for (NSDictionary *c in cases) {
        XCTAssertNotNil(c[@"from"], @"v2 向量每条带 from: %@", c[@"name"]);
        BOOL got = IMAutoDeleteExpired([c[@"ts"] longLongValue], [c[@"sec"] longLongValue], [c[@"from"] longLongValue], [c[@"now"] longLongValue]);
        XCTAssertEqual(got, [c[@"expect"] boolValue], @"%@", c[@"name"]);
        // 配置对象与纯函数同口径
        IMAutoDeleteConfig *cfg = [IMAutoDeleteConfig configWithSec:[c[@"sec"] longLongValue] from:[c[@"from"] longLongValue]];
        if ([c[@"sec"] longLongValue] > 0) {
            XCTAssertEqual([cfg isExpiredTimestamp:[c[@"ts"] longLongValue] now:[c[@"now"] longLongValue]], [c[@"expect"] boolValue], @"cfg %@", c[@"name"]);
        }
    }
}

- (void)testWindowVectors {
    NSArray *cases = [self vectors][@"window"];
    XCTAssertGreaterThanOrEqual(cases.count, 5u);
    XCTAssertNil([self vectors][@"floor_ts"], @"v1 的 floor_ts 已从向量删除");
    for (NSDictionary *c in cases) {
        int64_t lo = -1, hi = -1;
        BOOL has = IMAutoDeleteWindow([c[@"sec"] longLongValue], [c[@"from"] longLongValue], [c[@"now"] longLongValue], &lo, &hi);
        id expect = c[@"expect"];
        if ([expect isKindOfClass:NSNull.class]) { XCTAssertFalse(has, @"%@", c[@"name"]); continue; }
        XCTAssertTrue(has, @"%@", c[@"name"]);
        XCTAssertEqual(lo, [expect[@"lo"] longLongValue], @"%@", c[@"name"]);
        XCTAssertEqual(hi, [expect[@"hi"] longLongValue], @"%@", c[@"name"]);
    }
}

- (void)testFromAfterSystemMessageVectors {
    NSArray *cases = [self vectors][@"from_after_system_message"];
    XCTAssertGreaterThanOrEqual(cases.count, 3u);
    for (NSDictionary *c in cases) {
        XCTAssertEqual(IMAutoDeleteFromAfterSystemMessage([c[@"sys_ts"] longLongValue], [c[@"sec"] longLongValue]), [c[@"expect_from"] longLongValue]);
    }
}

- (void)testValidSecVectors {
    NSDictionary *v = [self vectors];
    for (NSNumber *n in v[@"valid_sec"]) { XCTAssertTrue(IMAutoDeleteIsValidSec(n.longLongValue), @"%@", n); }
    for (NSNumber *n in v[@"invalid_sec"]) { XCTAssertFalse(IMAutoDeleteIsValidSec(n.longLongValue), @"%@", n); }
    XCTAssertEqualObjects(IMAutoDeleteTiers(), (@[@0, @120, @86400, @604800, @2592000]));
    // 18 档弹窗列表 == 向量 valid_sec 去掉 0（同序升序）
    NSMutableArray *validNoZero = [v[@"valid_sec"] mutableCopy];
    [validNoZero removeObject:@0];
    XCTAssertEqualObjects(IMAutoDeleteCustomTiers(), validNoZero);
    XCTAssertEqual(IMAutoDeleteCustomTiers().count, 18u);
}

#pragma mark - 时长文案折算 / 自定义行选中态

- (void)testDurationTextConversionZh {
    IMLocalization *loc = IMLocalization.shared;
    NSString *saved = loc.preference;
    [loc setPreference:@"zh-Hans"];
    NSDictionary<NSNumber *, NSString *> *want = @{
        @120: @"2 分钟", @3600: @"1 小时", @86400: @"1 天", @172800: @"2 天", @518400: @"6 天",
        @604800: @"1 周", @1209600: @"2 周", @1814400: @"3 周",
        @2592000: @"1 个月", @5184000: @"2 个月", @15552000: @"6 个月", @31536000: @"1 年",
        @180: @"3 分钟", @7200: @"2 小时",
        @(365 * 86400 * 2): @"2 年", @(30 * 86400 * 12): @"12 个月", // 360 天不整除 365，12 个月
    };
    for (NSNumber *k in want) { XCTAssertEqualObjects(IMAutoDeleteDurationText(k.longLongValue), want[k], @"%@", k); }
    // 优先级：30 天是 1 个月不是 4 周；7 天是 1 周不是 7 天；365 天是 1 年
    XCTAssertEqualObjects(IMAutoDeleteDurationText(30 * 86400), @"1 个月");
    XCTAssertEqualObjects(IMAutoDeleteDurationText(7 * 86400), @"1 周");
    XCTAssertEqualObjects(IMAutoDeleteDurationText(365 * 86400), @"1 年");
    XCTAssertEqualObjects(IMAutoDeleteDurationText(0), @"");
    XCTAssertEqualObjects(IMAutoDeleteTierTitle(0), IMLocalized(@"common.off"));
    XCTAssertEqualObjects(IMAutoDeleteTierTitle(12345), IMLocalized(@"common.off"), @"非法档位按关闭");
    XCTAssertEqualObjects(IMAutoDeletePeriodWord(12345), @"");
    [loc setPreference:@"en"];
    XCTAssertEqualObjects(IMAutoDeleteDurationText(120), @"2 minutes");
    XCTAssertEqualObjects(IMAutoDeleteDurationText(3600), @"1 hour");
    XCTAssertEqualObjects(IMAutoDeleteDurationText(86400), @"1 day");
    XCTAssertEqualObjects(IMAutoDeleteDurationText(3 * 86400), @"3 days");
    [loc setPreference:saved];
}

/// ✓ 打在哪一行：固定 5 档（含 0）归各自行，其余合法档位归「自定义」行；非法值不归任何自定义。
- (void)testCustomRowSelectionJudgement {
    for (NSNumber *n in IMAutoDeleteTiers()) { XCTAssertFalse(IMAutoDeleteIsCustomSelection(n.longLongValue), @"%@", n); }
    for (NSNumber *n in @[@3600, @172800, @259200, @518400, @1209600, @1814400, @5184000, @15552000, @31536000]) {
        XCTAssertTrue(IMAutoDeleteIsCustomSelection(n.longLongValue), @"%@", n);
    }
    XCTAssertFalse(IMAutoDeleteIsCustomSelection(12345));
    XCTAssertFalse(IMAutoDeleteIsCustomSelection(-1));
    // 任一档位都能被会话模型 / JSON 收下（不是只认旧 3 档）
    XCTAssertEqual(IMAutoDeleteSecFromJSON(@120), 120);
    XCTAssertEqual(IMAutoDeleteSecFromJSON(@31536000), 31536000);
    XCTAssertEqual(IMAutoDeleteSecFromJSON(@691200), 0);
}

/// v2：新>0 且 ≠ 当前才弹一次说明框（任何开启 / 改档位，含放宽、缩短）；关闭、不变不弹。
- (void)testNeedsConfirm {
    XCTAssertTrue(IMAutoDeleteNeedsConfirm(0, 86400));              // 关 -> 开
    XCTAssertTrue(IMAutoDeleteNeedsConfirm(2592000, 604800));       // 缩短
    XCTAssertTrue(IMAutoDeleteNeedsConfirm(86400, 604800));         // 放宽也弹（v1 不弹）
    XCTAssertTrue(IMAutoDeleteNeedsConfirm(120, 3600));
    XCTAssertFalse(IMAutoDeleteNeedsConfirm(86400, 0));             // 关闭
    XCTAssertFalse(IMAutoDeleteNeedsConfirm(86400, 86400));         // 不变
    XCTAssertFalse(IMAutoDeleteNeedsConfirm(0, 0));
}

#pragma mark - JSON / 模型（sec+from 成对）

- (void)testSecFromJSONAndConversationParse {
    XCTAssertEqual(IMAutoDeleteSecFromJSON(@604800), 604800);
    XCTAssertEqual(IMAutoDeleteSecFromJSON(@12345), 0);   // 非白名单当关
    XCTAssertEqual(IMAutoDeleteSecFromJSON(@"86400"), 0);  // 非数字当关
    XCTAssertEqual(IMAutoDeleteSecFromJSON(nil), 0);
    IMConversation *c = IMADConv(@{ @"conv_id": @"u_1_u_2", @"auto_delete_sec": @86400, @"auto_delete_from": @1700000000001 });
    XCTAssertEqual(c.autoDeleteSec, 86400);
    XCTAssertEqual(c.autoDeleteFrom, 1700000000001);
    XCTAssertEqual(IMADConv(@{ @"conv_id": @"u_1_u_2" }).autoDeleteSec, 0); // 老响应默认 0
    // 老服务端（v1 个人档位，没有 from）：sec>0 缺 from 当关闭——from=0 会追溯清掉整段历史
    IMConversation *old = IMADConv(@{ @"conv_id": @"u_1_u_2", @"auto_delete_sec": @86400 });
    XCTAssertEqual(old.autoDeleteSec, 0);
    XCTAssertEqual(old.autoDeleteFrom, 0);
    IMAutoDeleteConfig *cfg = IMAutoDeleteConfigFromJSON(@120, @500);
    XCTAssertEqual(cfg.sec, 120); XCTAssertEqual(cfg.from, 500);
    XCTAssertEqual(IMAutoDeleteConfigFromJSON(@0, @500).from, 0, @"关闭时 from 归零");
    XCTAssertEqual(IMAutoDeleteConfigFromJSON(@777, @500).sec, 0, @"非白名单当关");
    XCTAssertEqual(IMAutoDeleteConfigFromJSON(@120, @0).sec, 0, @"from<=0 且 sec>0 是脏数据，当关");
    XCTAssertEqual(IMAutoDeleteConfigFromJSON(@120, @(-5)).sec, 0, @"from 负数同理");
}

#pragma mark - 库：设置落库 / 迁移 / 清理 / 入库闸

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

- (void)testConfigPersistsAndSurvivesConversationSnapshotReplace {
    IMDatabase *db = [self freshDB:@"ad-owner-1"];
    XCTAssertFalse([db autoDeleteConfigForConv:@"c1"].active);
    XCTAssertTrue([db setAutoDeleteSec:86400 from:1000 forConv:@"c1"]);
    XCTAssertFalse([db setAutoDeleteSec:86400 from:1000 forConv:@"c1"], @"sec+from 都没变应返回 NO");
    XCTAssertTrue([db setAutoDeleteSec:86400 from:2000 forConv:@"c1"], @"只 from 变了（重新开启同档位）也算变，要触发扫描");
    IMAutoDeleteConfig *cfg = [db autoDeleteConfigForConv:@"c1"];
    XCTAssertEqual(cfg.sec, 86400); XCTAssertEqual(cfg.from, 2000);
    XCTAssertEqual(db.autoDeleteActiveConvs[@"c1"].from, 2000);
    // 整表快照：以服务端列表为准（档位被别的成员 / 设备改了 / 会话已不在列表）
    IMConversation *c = IMADConv(@{ @"conv_id": @"c2", @"auto_delete_sec": @604800, @"auto_delete_from": @3000 });
    [db replaceCachedConversations:@[c]];
    XCTAssertFalse([db autoDeleteConfigForConv:@"c1"].active);
    XCTAssertEqual([db autoDeleteConfigForConv:@"c2"].sec, 604800);
    XCTAssertEqual([db autoDeleteConfigForConv:@"c2"].from, 3000);
    [db setAutoDeleteSec:777 from:5 forConv:@"c2"]; // 非白名单落成关
    XCTAssertEqual([db autoDeleteSecForConv:@"c2"], 0);
}

/// v1 库（个人档位表只有 sec 列）升级：补 from_ms 列，旧个人档位不迁移（整表清掉，否则 from=0 会追溯清历史）。
- (void)testMigrationFromV1DropsPersonalTiersAndAddsFromColumn {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"im-autodel-v1-%@.sqlite", NSUUID.UUID.UUIDString]];
    FMDatabase *raw = [FMDatabase databaseWithPath:path];
    XCTAssertTrue([raw open]);
    XCTAssertTrue([raw executeUpdate:@"CREATE TABLE im_conv_auto_delete_local (owner_uid TEXT NOT NULL, conv_id TEXT NOT NULL, sec INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(owner_uid,conv_id))"]);
    XCTAssertTrue([raw executeUpdate:@"INSERT INTO im_conv_auto_delete_local VALUES ('ad-owner-m','c1',86400)"]);
    [raw close];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:[NSURL fileURLWithPath:path]];
    [db useOwnerUserID:@"ad-owner-m"];
    XCTAssertFalse([db autoDeleteConfigForConv:@"c1"].active, @"v1 个人档位不迁移");
    XCTAssertTrue([db setAutoDeleteSec:604800 from:42 forConv:@"c1"]);
    XCTAssertEqual([db autoDeleteConfigForConv:@"c1"].from, 42, @"from_ms 列已补");
    // 再开一次（幂等迁移）不丢 v2 数据
    IMDatabase *again = [[IMDatabase alloc] initWithFileURL:[NSURL fileURLWithPath:path]];
    [again useOwnerUserID:@"ad-owner-m"];
    XCTAssertEqual([again autoDeleteConfigForConv:@"c1"].sec, 604800);
}

/// 不追溯：窗口 [from, now-sec*1000]。from 之前的老消息（哪怕早已满期）保留；窗口内的删；窗口后的保留。
- (void)testSweepDeletesOnlyWindowKeepsBeforeFromAndFresh {
    IMDatabase *db = [self freshDB:@"ad-owner-2"];
    NSString *conv = @"u_ad-owner-2_u_bob";
    int64_t day = 86400 * 1000LL, now = 20 * day, from = now - 5 * day;
    IMConversation *c = IMADConv(@{ @"conv_id": conv, @"peer": @"bob", @"unread": @3, @"read_seq": @1, @"latest_conv_seq": @5 });
    [db replaceCachedConversations:@[c]];
    [db saveIncomingMessage:[self msg:conv seq:1 from:@"bob" ts:from - 10 * day content:@"开启前很久"] advancingSyncedConvSeq:1];
    [db saveIncomingMessage:[self msg:conv seq:2 from:@"bob" ts:from - 1 content:@"开启前一刻"] advancingSyncedConvSeq:2];
    [db saveIncomingMessage:[self msg:conv seq:3 from:@"bob" ts:from + 1000 content:@"开启后已满期"] advancingSyncedConvSeq:3];
    [db saveIncomingMessage:[self msg:conv seq:4 from:@"ad-owner-2" ts:from + 2000 content:@"开启后已满期2"] advancingSyncedConvSeq:4];
    [db saveIncomingMessage:[self msg:conv seq:5 from:@"ad-owner-2" ts:now - 100 content:@"新"] advancingSyncedConvSeq:5];

    IMAutoDeleteConfig *cfg = [IMAutoDeleteConfig configWithSec:86400 from:from];
    [db setAutoDeleteConfig:cfg forConv:conv]; // 消息先入库（入库时还没开），再开档位
    NSArray<NSNumber *> *removed = [db deleteExpiredMessagesForConv:conv config:cfg nowMs:now];
    XCTAssertEqualObjects(removed, (@[@3, @4]));
    NSArray<NSNumber *> *left = [[db messagesForConv:conv] valueForKey:@"convSeq"];
    XCTAssertEqualObjects([left sortedArrayUsingSelector:@selector(compare:)], (@[@1, @2, @5]), @"from 之前的永不过期");
    XCTAssertEqual([db syncedConvSeqForConv:conv], 5, @"游标不动：清理后不能把已删段当缺口重拉");
    XCTAssertEqual([db cachedConversationWithID:conv].unread, 2, @"read_seq=1：被删的 seq3 是未读（扣 1）；seq4 是自己发的不扣");
    XCTAssertEqual([db deleteExpiredMessagesForConv:conv config:cfg nowMs:now].count, 0u, @"幂等");
    // 关闭 / 窗口为空：什么都不删
    XCTAssertEqual([db deleteExpiredMessagesForConv:conv config:[IMAutoDeleteConfig configWithSec:0 from:0] nowMs:now].count, 0u);
    XCTAssertEqual([db deleteExpiredMessagesForConv:conv config:[IMAutoDeleteConfig configWithSec:86400 from:now] nowMs:now].count, 0u, @"from>=now-sec：窗口为空");
}

/// 过期集合是窗口：最后一条消息过期后，预览取**最后一条未过期**的可见消息——越过窗口取 from 之前的（如开启通知本身）。
- (void)testPreviewCrossesWindowToMessageBeforeFrom {
    IMDatabase *db = [self freshDB:@"ad-owner-3"];
    NSString *conv = @"u_ad-owner-3_u_bob";
    int64_t day = 86400 * 1000LL, now = 20 * day, from = now - 5 * day;
    IMConversation *c = IMADConv(@{ @"conv_id": conv, @"peer": @"bob", @"latest_conv_seq": @3 });
    c.lastContent = @"最后一条（将过期）"; c.lastContentType = @"text"; c.lastFrom = @"bob"; c.timestamp = from + 5000; c.unread = 2;
    [db replaceCachedConversations:@[c]];
    [db saveIncomingMessage:[self msg:conv seq:1 from:@"bob" ts:from - 3 * day content:@"开启前"] advancingSyncedConvSeq:1];
    IMMessageModel *sys = [self msg:conv seq:2 from:@"" ts:from - 1 content:@"A 开启了自动删除"];
    sys.contentType = @"system"; sys.sysEvent = @"auto_delete"; sys.sysArgs = @{ @"sec": @"86400" };
    [db saveIncomingMessage:sys advancingSyncedConvSeq:2];
    [db saveIncomingMessage:[self msg:conv seq:3 from:@"bob" ts:from + 5000 content:@"最后一条（将过期）"] advancingSyncedConvSeq:3];
    IMAutoDeleteConfig *cfg = [IMAutoDeleteConfig configWithSec:86400 from:from];
    [db setAutoDeleteConfig:cfg forConv:conv];
    XCTAssertEqualObjects([db deleteExpiredMessagesForConv:conv config:cfg nowMs:now], (@[@3]));
    IMConversation *row = [db cachedConversationWithID:conv];
    XCTAssertNotNil(row, @"会话行保留");
    XCTAssertEqualObjects(row.lastSysEvent, @"auto_delete", @"预览越过窗口取 from 之前的最后一条可见消息");
    XCTAssertEqualObjects(row.lastContent, @"A 开启了自动删除");
    XCTAssertEqual(row.unread, 1, @"窗口外 from 之前那条本机未读(seq1>read_seq=0)仍在；不是一刀清零");
    XCTAssertEqual(row.timestamp, from + 5000, @"timestamp 不清零：排序位置不变");
}

- (void)testAllExpiredLeavesRowWithEmptyPreviewAndKeepsSortTimestamp {
    IMDatabase *db = [self freshDB:@"ad-owner-4"];
    NSString *conv = @"u_ad-owner-4_u_bob";
    int64_t now = 5 * 86400 * 1000LL;
    IMConversation *c = IMADConv(@{ @"conv_id": conv, @"peer": @"bob", @"latest_conv_seq": @1 });
    c.lastContent = @"很久以前"; c.lastContentType = @"text"; c.timestamp = 1000; c.unread = 1;
    [db replaceCachedConversations:@[c]];
    [db saveIncomingMessage:[self msg:conv seq:1 from:@"bob" ts:1000 content:@"很久以前"] advancingSyncedConvSeq:1];
    IMAutoDeleteConfig *cfg = [IMAutoDeleteConfig configWithSec:86400 from:500];
    [db setAutoDeleteConfig:cfg forConv:conv];
    XCTAssertEqual([db deleteExpiredMessagesForConv:conv config:cfg nowMs:now].count, 1u);
    IMConversation *row = [db cachedConversationWithID:conv];
    XCTAssertEqualObjects(row.lastContent ?: @"", @"", @"预览为空");
    XCTAssertEqual(row.unread, 0);
    XCTAssertEqual(row.timestamp, 1000, @"timestamp 不清零");
}

/// 本机没有消息行（杀进程重启后只剩会话列表缓存 / 离线积压未下载）：删不到行，会话行的预览与未读也必须跟着清。
- (void)testSummaryRecomputedEvenWithoutLocalMessageRows {
    IMDatabase *db = [self freshDB:@"ad-owner-6"];
    NSString *conv = @"u_ad-owner-6_u_bob";
    int64_t now = 5 * 86400 * 1000LL;
    IMAutoDeleteConfig *cfg = [IMAutoDeleteConfig configWithSec:86400 from:1000];
    IMConversation *c = IMADConv(@{ @"conv_id": conv, @"peer": @"bob", @"latest_conv_seq": @9 });
    c.lastContent = @"缓存里的预览"; c.lastContentType = @"text"; c.lastFrom = @"bob"; c.timestamp = 2000; c.unread = 4;
    [db replaceCachedConversations:@[c]];
    [db setAutoDeleteConfig:cfg forConv:conv];
    XCTAssertEqual([db deleteExpiredMessagesForConv:conv config:cfg nowMs:now].count, 0u, @"没有本地行可删");
    XCTAssertFalse([db refreshAutoDeleteSummaryForConv:conv config:cfg nowMs:now], @"刚被服务端列表写过摘要：让路，避免 落库->清空->通知->重拉 循环");
    XCTAssertEqualObjects([db cachedConversationWithID:conv].lastContent, @"缓存里的预览");
    [db resetServerSyncedSummaryMarks]; // 模拟冷启动：只剩缓存
    XCTAssertTrue([db refreshAutoDeleteSummaryForConv:conv config:cfg nowMs:now], @"会话行变了，要通知列表刷新");
    IMConversation *row = [db cachedConversationWithID:conv];
    XCTAssertEqualObjects(row.lastContent ?: @"", @"");
    XCTAssertEqual(row.unread, 0);
    XCTAssertEqual(row.timestamp, 2000);
    XCTAssertFalse([db refreshAutoDeleteSummaryForConv:conv config:cfg nowMs:now], @"幂等：第二次无变化，不重复通知");
    // 摘要那条在 from 之前（不追溯，永不过期）/ 在窗口之后（没满期）：不动
    IMConversation *before = IMADConv(@{ @"conv_id": @"u_ad-owner-6_u_amy", @"peer": @"amy", @"latest_conv_seq": @1 });
    before.lastContent = @"开启前"; before.timestamp = 500; before.unread = 1;
    IMConversation *fresh = IMADConv(@{ @"conv_id": @"u_ad-owner-6_u_cat", @"peer": @"cat", @"latest_conv_seq": @1 });
    fresh.lastContent = @"新"; fresh.timestamp = now - 10; fresh.unread = 1;
    [db replaceCachedConversations:@[c, before, fresh]];
    [db resetServerSyncedSummaryMarks];
    XCTAssertFalse([db refreshAutoDeleteSummaryForConv:@"u_ad-owner-6_u_amy" config:cfg nowMs:now]);
    XCTAssertFalse([db refreshAutoDeleteSummaryForConv:@"u_ad-owner-6_u_cat" config:cfg nowMs:now]);
    XCTAssertEqualObjects([db cachedConversationWithID:@"u_ad-owner-6_u_amy"].lastContent, @"开启前");
    XCTAssertEqualObjects([db cachedConversationWithID:@"u_ad-owner-6_u_cat"].lastContent, @"新");
}

/// 入库闸 / 实时过滤 / sync 整页过滤同一公式：from 之前的老消息正常入库，from 之后已满期的不进库。
- (void)testIncomingGateHonoursFrom {
    IMDatabase *db = [self freshDB:@"ad-owner-7"];
    NSString *conv = @"u_ad-owner-7_u_bob";
    int64_t now = (int64_t)([NSDate date].timeIntervalSince1970 * 1000), day = 86400 * 1000LL;
    int64_t from = now - 5 * day;
    [db setAutoDeleteSec:86400 from:from forConv:conv];
    IMMessageModel *old = [self msg:conv seq:1 from:@"bob" ts:from - 3 * day content:@"开启前"];
    IMMessageModel *expired = [self msg:conv seq:2 from:@"bob" ts:from + day content:@"开启后已满期"];
    IMMessageModel *fresh = [self msg:conv seq:3 from:@"bob" ts:now - 1000 content:@"新"];
    XCTAssertFalse([db autoDeleteDropsIncoming:old], @"from 之前永不过期，新设备首次同步不丢");
    XCTAssertTrue([db autoDeleteDropsIncoming:expired]);
    XCTAssertFalse([db autoDeleteDropsIncoming:fresh]);
    XCTAssertEqual(([db messagesDroppingAutoDeleteExpired:@[old, expired, fresh]]).count, 2u);
    [db saveIncomingMessage:old advancingSyncedConvSeq:1];
    [db saveIncomingMessage:expired advancingSyncedConvSeq:2];
    [db saveIncomingMessage:fresh advancingSyncedConvSeq:3];
    NSArray<NSNumber *> *seqs = [[db messagesForConv:conv] valueForKey:@"convSeq"];
    XCTAssertEqualObjects([seqs sortedArrayUsingSelector:@selector(compare:)], (@[@1, @3]), @"库内落库闸与 UI 过滤同一份保留集合");
    // msg_op 事件行不受约束
    IMMessageModel *op = [self msg:conv seq:4 from:@"bob" ts:from + day content:@""];
    op.contentType = kIMTypeMsgOp;
    XCTAssertFalse([db autoDeleteDropsIncoming:op]);
}

#pragma mark - conv_update / 会话行预览 / 只读档位页

/// conv_update：sec+from 成对覆盖；缺 from 的 sec>0 当关闭；sec 或 from 变化且 sec>0 才会触发扫描（返回由落库 changed 体现）。
- (void)testConvUpdateAppliesPairAndIgnoresFromlessSec {
    IMDatabase *db = [self freshDB:@"ad-owner-8"];
    IMSocketManager *sm = IMSocketManager.sharedManager;
    [sm applyAutoDeleteFromConvUpdate:@{ @"auto_delete_sec": @86400, @"auto_delete_from": @1700000000001 } convID:@"cu" database:db];
    XCTAssertEqual([db autoDeleteConfigForConv:@"cu"].sec, 86400);
    XCTAssertEqual([db autoDeleteConfigForConv:@"cu"].from, 1700000000001);
    [sm applyAutoDeleteFromConvUpdate:@{ @"auto_delete_sec": @0, @"auto_delete_from": @0 } convID:@"cu" database:db];
    XCTAssertFalse([db autoDeleteConfigForConv:@"cu"].active, @"关闭帧");
    [sm applyAutoDeleteFromConvUpdate:@{ @"auto_delete_sec": @86400 } convID:@"cu" database:db];
    XCTAssertFalse([db autoDeleteConfigForConv:@"cu"].active, @"缺 from 不能当 from=0（会追溯清历史）");
    [sm applyAutoDeleteFromConvUpdate:@{ @"pinned_at": @1 } convID:@"cu" database:db];
    XCTAssertFalse([db autoDeleteConfigForConv:@"cu"].active, @"帧里没有 auto_delete_sec 不动");
}

/// 会话列表副标题：最后一条是 auto_delete 系统消息 → 按 sys_event 本地化（与聊天页气泡同源 IMSegmentsForSysEvent）。
- (void)testConversationPreviewRendersAutoDeleteSysEvent {
    IMConversation *c = IMADConv(@{ @"conv_id": @"g1", @"is_group": @YES, @"last_message": @{
        @"content_type": @"system", @"content": @"张三 开启了自动删除，消息将在1天后自动删除",
        @"sys_event": @"auto_delete", @"sys_args": @{ @"sec": @"86400" },
        @"sys_segments": @[@{ @"uid": @"u1", @"text": @"张三" }, @{ @"text": @" 开启了自动删除" }] } });
    XCTAssertEqualObjects([c lastPreviewTextForSelfUID:@"other"], @"张三 开启了自动删除，消息将在1 天后自动删除");
    IMConversation *noSec = IMADConv(@{ @"conv_id": @"g1", @"is_group": @YES, @"last_message": @{
        @"content_type": @"system", @"content": @"张三 开启了自动删除，消息将在1天后自动删除", @"sys_event": @"auto_delete",
        @"sys_segments": @[@{ @"uid": @"u1", @"text": @"张三" }] } });
    XCTAssertEqualObjects([noSec lastPreviewTextForSelfUID:@"other"], @"张三", @"缺 sys_args.sec：回退服务端分段（不崩、不错渲）");
}

/// 群里非群主 / 管理员：档位页整页只读，点任意行只回调 toast，不触发保存。
- (void)testReadOnlyTierPageNeverSaves {
    __block int selects = 0, readOnlyTaps = 0;
    IMAutoDeleteTierViewController *vc = [[IMAutoDeleteTierViewController alloc] initWithCurrentSec:86400 footer:@"f" optimistic:NO
        onSelect:^(int64_t sec, void (^done)(BOOL)) { selects++; done(YES); }];
    vc.onReadOnlyTap = ^{ readOnlyTaps++; };
    UITableView *table = nil;
    for (UIView *v in vc.view.subviews) { if ([v isKindOfClass:UITableView.class]) { table = (UITableView *)v; } }
    XCTAssertNotNil(table);
    NSInteger rows = [table.dataSource tableView:table numberOfRowsInSection:0];
    for (NSInteger r = 0; r < rows; r++) { [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:0]]; }
    XCTAssertEqual(selects, 0);
    XCTAssertEqual(readOnlyTaps, (int)rows, @"含「自定义」行");
    // 可写页：点非当前档位走 onSelect
    IMAutoDeleteTierViewController *rw = [[IMAutoDeleteTierViewController alloc] initWithCurrentSec:0 footer:@"f" optimistic:NO
        onSelect:^(int64_t sec, void (^done)(BOOL)) { selects++; done(NO); }];
    UITableView *t2 = nil;
    for (UIView *v in rw.view.subviews) { if ([v isKindOfClass:UITableView.class]) { t2 = (UITableView *)v; } }
    [t2.delegate tableView:t2 didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
    XCTAssertEqual(selects, 1);
}

#pragma mark - PUT settings 是否带 auto_delete_sec / 回包 / 300204

/// 返回 @{ body: 请求体, data: 回包 data(可无), error: NSError(可无) }。不用 NSError** 出参：回调在嵌套 runloop 里 autorelease，出参会悬空。
- (NSDictionary *)putSettingsWithAutoDeleteSec:(NSNumber *)sec viaLegacyEntry:(BOOL)legacy reply:(NSDictionary *)reply {
    IMHTTPService *svc = IMHTTPService.sharedService;
    NSString *oldHost = svc.host;
    if (svc.host.length == 0) { svc.host = @"127.0.0.1:59391"; }
    @synchronized (IMADSettingsStub.class) { [IMADSettingsStub.bodies removeAllObjects]; IMADStubReply = reply; }
    [NSURLProtocol registerClass:IMADSettingsStub.class];
    XCTestExpectation *e = [self expectationWithDescription:@"put"];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (legacy) {
        [svc updateConversationSettingsWithToken:@"t" convID:kADStubConv pinnedAt:123 muted:NO muteUntil:nil markedUnread:NO
                                      completion:^(NSError *err) { if (err) { result[@"error"] = err; } [e fulfill]; }];
    } else {
        [svc updateConversationSettingsWithToken:@"t" convID:kADStubConv pinnedAt:0 muted:NO muteUntil:nil markedUnread:NO
                                   autoDeleteSec:sec completion:^(NSDictionary *data, NSError *err) {
            if (err) { result[@"error"] = err; } if (data) { result[@"data"] = data; } [e fulfill];
        }];
    }
    [self waitForExpectationsWithTimeout:5 handler:nil];
    [NSURLProtocol unregisterClass:IMADSettingsStub.class];
    svc.host = oldHost;
    @synchronized (IMADSettingsStub.class) { IMADStubReply = nil; result[@"body"] = IMADSettingsStub.bodies.lastObject ?: @{}; }
    return result;
}

- (NSDictionary *)putSettingsWithAutoDeleteSec:(NSNumber *)sec viaLegacyEntry:(BOOL)legacy {
    return [self putSettingsWithAutoDeleteSec:sec viaLegacyEntry:legacy reply:nil][@"body"];
}

/// 置顶 / 免打扰 / 标未读类 PUT 一律省略 auto_delete_sec（服务端保留原值；v2 里带本地缓存回传会把别人刚设的共享档位盖回去）。
- (void)testPinStylePutOmitsAutoDeleteSec {
    // 本机库里即便有非零设置也不能被带出去
    [IMDatabase.sharedDatabase setAutoDeleteSec:IMAutoDeleteSecWeek from:1000 forConv:kADStubConv];
    NSDictionary *body = [self putSettingsWithAutoDeleteSec:nil viaLegacyEntry:YES];
    XCTAssertEqualObjects(body[@"pinned_at"], @123);
    XCTAssertNil(body[@"auto_delete_sec"], @"%@", body);
    XCTAssertNil(body[@"auto_delete_from"]);
    XCTAssertNil([self putSettingsWithAutoDeleteSec:nil viaLegacyEntry:NO][@"auto_delete_sec"]);
    [IMDatabase.sharedDatabase setAutoDeleteSec:0 from:0 forConv:kADStubConv];
}

- (void)testExplicitTierPutCarriesAutoDeleteSecAndReturnsReply {
    NSDictionary *reply = @{ @"code": @0, @"message": @"ok", @"data": @{ @"auto_delete_sec": @86400, @"auto_delete_from": @1700000000001 } };
    NSDictionary *r = [self putSettingsWithAutoDeleteSec:@(IMAutoDeleteSecDay) viaLegacyEntry:NO reply:reply];
    XCTAssertEqualObjects(r[@"body"][@"auto_delete_sec"], @(IMAutoDeleteSecDay));
    XCTAssertEqualObjects(r[@"data"][@"auto_delete_from"], @1700000000001, @"回包 sec+from 交给调用方采纳");
    XCTAssertEqualObjects([self putSettingsWithAutoDeleteSec:@0 viaLegacyEntry:NO][@"auto_delete_sec"], @0); // 显式关闭也要带
}

/// 群普通成员改档位：服务端 300204，业务码必须保留到 NSError.code（UI 据此 toast autodel.group_admin_only 并回滚）。
- (void)testPutSurfacesBusinessCode300204 {
    NSDictionary *reply = @{ @"code": @300204, @"message": @"permission denied", @"data": @{} };
    NSError *err = [self putSettingsWithAutoDeleteSec:@(IMAutoDeleteSecDay) viaLegacyEntry:NO reply:reply][@"error"];
    XCTAssertEqual(err.code, 300204);
}

@end
