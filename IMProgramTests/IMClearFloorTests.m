#import <XCTest/XCTest.h>
#import <FMDB/FMDB.h>

#import "IMConversation.h"
#import "IMDatabase.h"
#import "IMDatabase+ClearFloor.h"
#import "IMDatabase+Ranges.h"
#import "IMMessageModel.h"

/// 「清空聊天记录」的本机清空位点 cleared_up_to（OFFLINE_BACKLOG_DESIGN §6.7，三端统一，Android 先行）。
///
/// 错法全是静默的：位点没抬 / 没保住 / 落库闸漏一条路 → 界面照常，只是「清空后重进把历史整页拉回来」
/// 或「清单宣称齐全而手里没有」。所以按「会怎么错」逐条钉。
@interface IMClearFloorTests : XCTestCase
@end

@implementation IMClearFloorTests {
    IMDatabase *_db;
    NSURL *_url;
}

static NSString * const kConv = @"g_clear";
static NSString * const kOther = @"g_other";
static NSString * const kMe = @"me";

- (void)setUp {
    [super setUp];
    NSString *name = [NSString stringWithFormat:@"im-clearfloor-test-%@.sqlite", NSUUID.UUID.UUIDString];
    _url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    _db = [[IMDatabase alloc] initWithFileURL:_url];
    [_db useOwnerUserID:kMe];
}

- (void)tearDown {
    [NSFileManager.defaultManager removeItemAtURL:_url error:NULL];
    [super tearDown];
}

#pragma mark - 夹具

- (IMMessageModel *)msgInConv:(NSString *)conv seq:(int64_t)seq {
    return [IMMessageModel receivedMessageWithNewMsgData:@{
        @"server_msg_id": [NSString stringWithFormat:@"%@-s%lld", conv, seq],
        @"conv_id": conv, @"from": @"peer", @"content": [NSString stringWithFormat:@"#%lld", seq],
        @"content_type": @"text", @"conv_seq": @(seq), @"timestamp": @(1788000000000 + seq),
    }];
}

/// 连续收下 1..n（逐条推游标并登记区间，与实时/sync 落库同口径），会话行随之建出来。
- (void)seedConv:(NSString *)conv upTo:(int64_t)n {
    for (int64_t i = 1; i <= n; i++) {
        [_db saveIncomingMessage:[self msgInConv:conv seq:i] advancingSyncedConvSeq:i];
    }
}

- (NSArray<NSNumber *> *)seqsInConv:(NSString *)conv {
    NSMutableArray *out = [NSMutableArray array];
    for (IMMessageModel *m in [_db messagesForConv:conv]) { [out addObject:@(m.convSeq)]; }
    return out;
}

/// 区间表里该会话的**真实行数**（rangesForConv: 带老库兜底，不能拿它判「清没清」）。
- (NSInteger)rangeRowCountInConv:(NSString *)conv {
    FMDatabase *raw = [FMDatabase databaseWithPath:_url.path];
    if (![raw open]) { return -1; }
    FMResultSet *rs = [raw executeQuery:@"SELECT COUNT(*) AS n FROM im_conv_range_local WHERE owner_uid=? AND conv_id=?", kMe, conv];
    NSInteger n = [rs next] ? [rs intForColumn:@"n"] : -1;
    [rs close]; [raw close];
    return n;
}

- (NSString *)rangesText:(NSString *)conv {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSArray<NSNumber *> *r in [_db rangesForConv:conv]) {
        [parts addObject:[NSString stringWithFormat:@"%lld-%lld", r.firstObject.longLongValue, r.lastObject.longLongValue]];
    }
    return [parts componentsJoinedByString:@","];
}

#pragma mark - 清空动作

/// 位点 = 本机所知最新（head / 本地最大 / 游标取大），清单清空、游标不低于位点；且只增不减。
- (void)test_清空抬位点_清区间_只增不减 {
    [self seedConv:kConv upTo:5];
    [_db updateHeadConvSeq:10 forConv:kConv];            // 服务端最新 10，本地只下了 1..5
    XCTAssertEqual([_db clearedUpToForConv:kConv], 0, @"没清过=0");

    XCTAssertEqual([_db clearMessagesForConv:kConv], 5);
    XCTAssertEqual([_db clearedUpToForConv:kConv], 10, @"取 head 而不是本地最大——否则 6..10 会被当成「还没下载」拉回来");
    XCTAssertEqualObjects([self seqsInConv:kConv], @[]);
    XCTAssertEqual([self rangeRowCountInConv:kConv], 0, @"区间清单连消息一起清（清单不能宣称一段手里没有的内容）");
    // rangesForConv: 在没有区间行时按「老库兼容」用游标反推 [1, synced]；游标已推到位点，所以至多宣称到位点——不越过它。
    XCTAssertEqualObjects([self rangesText:kConv], @"1-10");
    XCTAssertGreaterThanOrEqual([_db syncedConvSeqForConv:kConv], 10, @"游标推到位点：sync 不必从旧游标重拉一遍再丢掉");

    // 之后又收到 11..12 再清：位点 12；再空清一次，head 还是旧值也不得回退。
    [_db updateHeadConvSeq:12 forConv:kConv];
    [_db saveIncomingMessage:[self msgInConv:kConv seq:11] advancingSyncedConvSeq:11];
    [_db saveIncomingMessage:[self msgInConv:kConv seq:12] advancingSyncedConvSeq:12];
    [_db clearMessagesForConv:kConv];
    XCTAssertEqual([_db clearedUpToForConv:kConv], 12);
    [_db clearMessagesForConv:kConv];
    XCTAssertEqual([_db clearedUpToForConv:kConv], 12, @"只增不减：空清一次不能把位点拉低");

    // 位点高于本机其余所有已知位置（head/游标/本地最大都更低，例如别处抬过）时，再清一次也不得被拉低。
    FMDatabase *raw = [FMDatabase databaseWithPath:_url.path];
    XCTAssertTrue([raw open]);
    BOOL raised = [raw executeUpdate:@"UPDATE im_conv_clear_floor_local SET cleared_up_to=100 WHERE conv_id=?", kConv];
    XCTAssertTrue(raised);
    [raw close];
    [_db clearMessagesForConv:kConv];
    XCTAssertEqual([_db clearedUpToForConv:kConv], 100, @"MAX 语义：已有位点比现算的高就保持");
}

/// 清空只动该会话的消息 / 区间 / 位点：别的会话、会话行本身（预览、免打扰等）原样。
/// iOS 本机没有独立的「隐藏/删除」墓碑表（本地删除是物理删行），所以这条钉的是「范围」。
- (void)test_清空不波及别的会话与会话行 {
    [self seedConv:kConv upTo:3];
    [self seedConv:kOther upTo:4];
    [_db clearMessagesForConv:kConv];

    XCTAssertEqualObjects([self seqsInConv:kOther], (@[@1, @2, @3, @4]));
    XCTAssertEqualObjects([self rangesText:kOther], @"1-4");
    XCTAssertEqual([_db clearedUpToForConv:kOther], 0, @"别的会话不抬位点");
    XCTAssertNotNil([_db cachedConversationWithID:kConv], @"会话行留着，列表里仍能看到这个会话");
}

#pragma mark - 落库闸

/// ≤ 位点的消息：单条（实时 / window 页走的 saveMessage）与整页（sync）都不落库；位点之后照常收。
- (void)test_落库过滤_单条与整页 {
    [self seedConv:kConv upTo:10];
    [_db clearMessagesForConv:kConv];                          // 位点 10

    [_db saveMessage:[self msgInConv:kConv seq:7]];            // window 页路径
    [_db saveIncomingMessage:[self msgInConv:kConv seq:10] advancingSyncedConvSeq:0];   // 实时路径
    XCTAssertEqualObjects([self seqsInConv:kConv], @[], @"≤ 位点的不得被带回来");

    [_db saveMessage:[self msgInConv:kConv seq:11]];
    XCTAssertEqualObjects([self seqsInConv:kConv], @[@11], @"位点之后的新消息照常收");

    // sync 整页：9..13 里只有 11..13 该落；区间登记口径不变（照整页的 [lo,hi] 登记），游标照推。
    NSArray *page = @[[self msgInConv:kConv seq:9], [self msgInConv:kConv seq:10], [self msgInConv:kConv seq:12],
                      [self msgInConv:kConv seq:13]];
    XCTAssertTrue([_db saveIncomingPage:page advanceTo:13 rangeLo:9 rangeHi:13]);
    XCTAssertEqualObjects([self seqsInConv:kConv], (@[@11, @12, @13]), @"整页里 ≤ 位点的两条被丢，且不致整页回滚");
    XCTAssertEqual([_db syncedConvSeqForConv:kConv], 13);
    XCTAssertEqualObjects([self rangesText:kConv], @"9-13");
}

#pragma mark - 会话列表快照回写

/// replaceCachedConversations 是 DELETE 全表再逐行 INSERT，列表每刷新一次就走一遍——位点是纯本机状态、
/// 快照里没有，不保就等于刷一次列表就「忘了清空过」，重进又拉回来。
- (void)test_列表回写不重置位点 {
    [self seedConv:kConv upTo:6];
    [_db clearMessagesForConv:kConv];
    XCTAssertEqual([_db clearedUpToForConv:kConv], 6);

    IMConversation *c = [IMConversation new];
    c.convID = kConv; c.peer = @"peer"; c.latestConvSeq = 6; c.lastContentType = @"text";
    for (int i = 0; i < 3; i++) { [_db replaceCachedConversations:@[c]]; }
    XCTAssertEqual([_db clearedUpToForConv:kConv], 6, @"快照整行重写必须保住清空位点");

    // 快照里没有的会话行被删（既有行为），位点在独立小表里**不随它走**（见 test_列表不再返回又出现位点仍在）。
    [_db replaceCachedConversations:@[]];
    XCTAssertEqual([_db clearedUpToForConv:kConv], 6);
}

#pragma mark - 可见范围内的「齐全」

/// 清空后：位点之下不算缺口；位点之上照常按区间清单判。
- (void)test_清空后齐全判据只看位点之上 {
    [self seedConv:kConv upTo:10];
    [_db updateHeadConvSeq:10 forConv:kConv];
    [_db clearMessagesForConv:kConv];
    XCTAssertTrue([_db isConvComplete:kConv], @"清单空了，但可见范围 [11,10] 里本来就没东西");
    XCTAssertTrue([_db conv:kConv coversFrom:1 to:10], @"整段都在位点之下：没什么可缺的");

    [_db updateHeadConvSeq:12 forConv:kConv];             // 服务端又来了两条，本地还没有
    XCTAssertFalse([_db isConvComplete:kConv], @"位点之上缺 11..12，要补");
    XCTAssertFalse([_db conv:kConv coversFrom:8 to:12]);

    [_db saveIncomingMessage:[self msgInConv:kConv seq:11] advancingSyncedConvSeq:11];
    [_db saveIncomingMessage:[self msgInConv:kConv seq:12] advancingSyncedConvSeq:12];
    XCTAssertTrue([_db isConvComplete:kConv], @"[11,12] 登记后，可见范围齐全（清单不必从 1 起）");
    XCTAssertTrue([_db conv:kConv coversFrom:8 to:12], @"下沿被收到位点之上");
}

/// 调用方给的服务端下界与库里的位点各自独立存、用时取大。
- (void)test_齐全判据两个下界取大 {
    [self seedConv:kConv upTo:3];
    [_db updateHeadConvSeq:50 forConv:kConv];
    [_db registerRangeInConv:kConv from:20 to:50];
    XCTAssertFalse([_db isConvComplete:kConv floor:0]);
    XCTAssertTrue([_db isConvComplete:kConv floor:20], @"服务端说 20 起可见，[20,50] 齐全");
    [_db clearMessagesForConv:kConv];                       // 位点 = 50
    XCTAssertTrue([_db isConvComplete:kConv floor:0], @"传 0 也吃得到库里的位点");
}

#pragma mark - 老库回填

- (void)closeAndDropColumn {
    // 退回「升级前」的库：去掉位点小表（也没有旧列），再用新实例打开触发迁移。
    FMDatabase *raw = [FMDatabase databaseWithPath:_url.path];
    XCTAssertTrue([raw open]);
    BOOL dropped = [raw executeUpdate:@"DROP TABLE im_conv_clear_floor_local"];
    XCTAssertTrue(dropped, @"%@", raw.lastErrorMessage);
    [raw close];
}

- (void)seedRawMessagesInConv:(NSString *)conv seqs:(NSArray<NSNumber *> *)seqs {
    for (NSNumber *s in seqs) { [_db saveMessage:[self msgInConv:conv seq:s.longLongValue]]; }
}

/// 回填规则：synced>0 的会话，位点 = synced 以内最小本地消息 seq − 1；synced 以内本地一条没有则 = synced。
/// 且只在补列那一次跑（幂等）：之后重开库不再重算。
- (void)test_老库回填规则 {
    // A：synced=100，本地只剩 40..100（1..39 当年被清掉）→ 39
    [self seedRawMessagesInConv:@"A" seqs:@[@40, @41, @100]];
    [_db advanceSyncedConvSeqForConv:@"A" toConvSeq:100];
    // B：synced=50，本地一条没有（全清了）→ 50
    [self seedRawMessagesInConv:@"B" seqs:@[@1]];
    [_db clearMessagesForConv:@"B"];                       // 先造出会话行与 synced（位点随后被删列抹掉）
    [_db advanceSyncedConvSeqForConv:@"B" toConvSeq:50];
    // C：从没同步过（synced=0）→ 不回填
    [self seedRawMessagesInConv:@"C" seqs:@[@5]];
    // D：synced=100，但本地消息全在 synced 之外（150..160）→ synced 以内没有 → 100
    [self seedRawMessagesInConv:@"D" seqs:@[@150, @160]];
    [_db advanceSyncedConvSeqForConv:@"D" toConvSeq:100];

    [self closeAndDropColumn];
    IMDatabase *reopened = [[IMDatabase alloc] initWithFileURL:_url];
    [reopened useOwnerUserID:kMe];
    XCTAssertEqual([reopened clearedUpToForConv:@"A"], 39);
    XCTAssertEqual([reopened clearedUpToForConv:@"B"], 50);
    XCTAssertEqual([reopened clearedUpToForConv:@"C"], 0);
    XCTAssertEqual([reopened clearedUpToForConv:@"D"], 100);

    // 幂等：删掉 A 的本地消息再重开，位点不会被「重新推一遍」。
    [reopened clearMessagesForConv:@"A"];                   // 位点升到 max(synced=100, ...) = 100
    FMDatabase *raw = [FMDatabase databaseWithPath:_url.path];
    XCTAssertTrue([raw open]);
    BOOL set7 = [raw executeUpdate:@"UPDATE im_conv_clear_floor_local SET cleared_up_to=7 WHERE conv_id='A'"];
    XCTAssertTrue(set7);
    [raw close];
    IMDatabase *again = [[IMDatabase alloc] initWithFileURL:_url];
    [again useOwnerUserID:kMe];
    XCTAssertEqual([again clearedUpToForConv:@"A"], 7, @"回填只在补列那一次跑，重开库不得再改位点");
}

#pragma mark - 补充：闸的副作用 / 会话行缺失 / 迁移原子性

/// 被闸丢弃的单条消息：**游标不动、区间不登记**（哪怕调用方带了非零的推进参数）。
/// 若闸放在推游标之后，游标会被一条根本没落库的消息推过去。
- (void)test_落库闸丢弃的消息不推游标不登记区间 {
    [self seedConv:kConv upTo:10];
    [_db clearMessagesForConv:kConv];                       // 位点 10，游标 10，区间表为空
    XCTAssertEqual([self rangeRowCountInConv:kConv], 0);

    BOOL ok = [_db saveIncomingMessage:[self msgInConv:kConv seq:8] advancingSyncedConvSeq:50];
    XCTAssertTrue(ok, @"被闸丢弃不是失败");
    XCTAssertEqual([_db syncedConvSeqForConv:kConv], 10, @"游标不得被一条没落库的消息推过去");
    XCTAssertEqual([self rangeRowCountInConv:kConv], 0, @"区间不得登记没落库的消息");
    XCTAssertEqualObjects([self seqsInConv:kConv], @[]);
}

/// 位点在独立小表里，**不依赖会话行**：会话行不存在也能记下（也不插占位行——列表是 SELECT * 直出）。
- (void)test_会话行不存在也能记位点 {
    [self seedConv:kConv upTo:4];
    [_db deleteCachedConversation:kConv];                   // 只删会话行，消息还在
    XCTAssertEqual([_db clearMessagesForConv:kConv], 4);
    XCTAssertEqual([_db clearedUpToForConv:kConv], 4, @"没有会话行也要记下位点");
    XCTAssertNil([_db cachedConversationWithID:kConv], @"不为此插占位行");
}

/// ① 清空 → 删除会话（只删会话行）→ 重建壳行：位点仍在、游标不低于位点、之后 sync 来的旧页不会把清掉的带回来。
- (void)test_删除会话后重建壳行位点仍在 {
    [self seedConv:kConv upTo:10];
    [_db clearMessagesForConv:kConv];
    [_db deleteCachedConversation:kConv];
    XCTAssertNil([_db cachedConversationWithID:kConv]);
    XCTAssertEqual([_db clearedUpToForConv:kConv], 10, @"位点不随会话行删除");

    [_db saveIncomingMessage:[self msgInConv:kConv seq:11] advancingSyncedConvSeq:0];   // 新消息 → 壳行重建
    XCTAssertNotNil([_db cachedConversationWithID:kConv]);
    XCTAssertGreaterThanOrEqual([_db syncedConvSeqForConv:kConv], 10, @"壳行游标不得是 0，否则 since=0 重拉清掉的历史");
    NSArray *stale = @[[self msgInConv:kConv seq:8], [self msgInConv:kConv seq:9], [self msgInConv:kConv seq:12]];
    XCTAssertTrue([_db saveIncomingPage:stale advanceTo:12 rangeLo:8 rangeHi:12]);
    XCTAssertEqualObjects([self seqsInConv:kConv], (@[@11, @12]), @"旧页里位点之内的仍被闸挡掉");
}

/// ② 列表整表回灌：A 不再被返回（整表 DELETE 把行删了），之后 A 又出现——位点仍在、游标不低于位点。
- (void)test_列表不再返回又出现位点仍在 {
    [self seedConv:kConv upTo:10];
    [_db clearMessagesForConv:kConv];
    IMConversation *c = [IMConversation new];
    c.convID = kConv; c.peer = @"peer"; c.latestConvSeq = 10; c.lastContentType = @"text";
    [_db replaceCachedConversations:@[c]];
    [_db replaceCachedConversations:@[]];                   // A 不再被返回
    XCTAssertNil([_db cachedConversationWithID:kConv]);
    XCTAssertEqual([_db clearedUpToForConv:kConv], 10);
    [_db replaceCachedConversations:@[c]];                  // 又出现
    XCTAssertEqual([_db clearedUpToForConv:kConv], 10);
    XCTAssertGreaterThanOrEqual([_db syncedConvSeqForConv:kConv], 10, @"重建后 synced 取 max(旧值, 位点)");
}

/// ④ 位点按账号隔离（iOS 没有「清账号」路径：登出不抹库，各账号靠 owner_uid 隔离；小表同口径）。
- (void)test_位点按账号隔离 {
    [self seedConv:kConv upTo:6];
    [_db clearMessagesForConv:kConv];
    XCTAssertEqual([_db clearedUpToForConv:kConv], 6);
    [_db useOwnerUserID:@"someone_else"];
    XCTAssertEqual([_db clearedUpToForConv:kConv], 0, @"别的账号看不到");
    [_db useOwnerUserID:kMe];
    XCTAssertEqual([_db clearedUpToForConv:kConv], 6);
}

/// ③ 迁移：旧列（早期实现）的值拷进小表，且不重复执行 / 不覆盖更大的值。
- (void)test_迁移把旧列值拷进小表且幂等 {
    [self seedConv:@"A" upTo:3];
    [self seedConv:@"B" upTo:3];
    FMDatabase *raw = [FMDatabase databaseWithPath:_url.path];
    XCTAssertTrue([raw open]);
    BOOL ok = [raw executeUpdate:@"DROP TABLE im_conv_clear_floor_local"]
        && [raw executeUpdate:@"ALTER TABLE im_conversation_local ADD COLUMN cleared_up_to INTEGER NOT NULL DEFAULT 0"]
        && [raw executeUpdate:@"UPDATE im_conversation_local SET cleared_up_to=50 WHERE conv_id='A'"]
        && [raw executeUpdate:@"UPDATE im_conversation_local SET cleared_up_to=7 WHERE conv_id='B'"];
    XCTAssertTrue(ok, @"%@", raw.lastErrorMessage);
    [raw close];

    IMDatabase *first = [[IMDatabase alloc] initWithFileURL:_url];
    [first useOwnerUserID:kMe];
    XCTAssertEqual([first clearedUpToForConv:@"A"], 50);
    XCTAssertEqual([first clearedUpToForConv:@"B"], 7);

    // 之后位点只由清空动作维护：A 被抬到更大的值，再开库（迁移再跑一遍）不得被旧列的 50 盖回去。
    [first saveIncomingMessage:[self msgInConv:@"A" seq:60] advancingSyncedConvSeq:0];
    [first updateHeadConvSeq:90 forConv:@"A"];
    [first clearMessagesForConv:@"A"];
    XCTAssertEqual([first clearedUpToForConv:@"A"], 90);
    IMDatabase *second = [[IMDatabase alloc] initWithFileURL:_url];
    [second useOwnerUserID:kMe];
    XCTAssertEqual([second clearedUpToForConv:@"A"], 90, @"重复打开不覆盖更大的值");
}

/// 建表与回填同一事务：回填失败 → 整体回滚（小表不留下），下次启动重试；而不是表已在、回填永不再跑。
/// 注入失败：把 im_message_local 临时换成一个缺列的视图，回填子查询必然报错（建表那一步先成功）。
- (void)test_迁移回填失败整体回滚下次重试 {
    [_db saveMessage:[self msgInConv:kConv seq:40]];
    [_db saveMessage:[self msgInConv:kConv seq:41]];
    [_db advanceSyncedConvSeqForConv:kConv toConvSeq:100];
    [self closeAndDropColumn];

    FMDatabase *raw = [FMDatabase databaseWithPath:_url.path];
    XCTAssertTrue([raw open]);
    BOOL swapped = [raw executeUpdate:@"ALTER TABLE im_message_local RENAME TO im_message_local_bak"]
        && [raw executeUpdate:@"CREATE VIEW im_message_local AS SELECT 1 AS x"];
    XCTAssertTrue(swapped, @"%@", raw.lastErrorMessage);
    [raw close];

    IMDatabase *failed = [[IMDatabase alloc] initWithFileURL:_url];     // 迁移失败路径
    [failed useOwnerUserID:kMe];
    raw = [FMDatabase databaseWithPath:_url.path];
    XCTAssertTrue([raw open]);
    FMResultSet *rs = [raw executeQuery:@"SELECT name FROM sqlite_master WHERE type='table' AND name='im_conv_clear_floor_local'"];
    BOOL hasTable = [rs next];
    [rs close];
    XCTAssertFalse(hasTable, @"回填失败必须连建表一起回滚，否则下次启动回填永不再跑");
    BOOL restored = [raw executeUpdate:@"DROP VIEW im_message_local"]
        && [raw executeUpdate:@"ALTER TABLE im_message_local_bak RENAME TO im_message_local"];
    XCTAssertTrue(restored, @"%@", raw.lastErrorMessage);
    [raw close];

    IMDatabase *retry = [[IMDatabase alloc] initWithFileURL:_url];      // 下次启动：重试成功
    [retry useOwnerUserID:kMe];
    XCTAssertEqual([retry clearedUpToForConv:kConv], 39, @"重试后回填生效");
}

@end
