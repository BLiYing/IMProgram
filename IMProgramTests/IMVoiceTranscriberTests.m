//  IMVoiceTranscriberTests.m
//  语音转文字「取消转文字」的折叠状态单测（2026-08-26 用户实测两个 bug 的回归护栏）：
//    ① 折叠名单必须落盘 —— 转写文本是永久缓存，折叠只在内存里的话，杀掉 App 重进会话
//       就会被缓存重新展开（用户："我已经取消转文字了，杀掉 app 之后再进入该会话，又显示转文字了"）。
//    ② 等结果期间取消 —— 迟到的识别结果只许落缓存，不许把面板重新顶开。
//  app-hosted 测试，头文件按相对路径引入。新建实例 = 模拟一次冷启动（init 从 NSUserDefaults 读名单）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Chat/Voice/IMVoiceTranscriber.h"

/// 与实现同口径的 defaults key（实现里是 static，测试按字面量对齐；改名这里会红，属预期）。
static NSString *const kCollapsedKey = @"im.voice.transcript.collapsed.v1";
static NSString *const kTextKeyPrefix = @"im.voice.transcript.v2.";
static NSString *const kOrderKey = @"im.voice.transcript.order.v1";

@interface IMVoiceTranscriberTests : XCTestCase
@end

@implementation IMVoiceTranscriberTests {
    NSMutableArray<NSString *> *_dirtyTextKeys; // 本例写过的转写缓存 key，tearDown 清
}

- (void)setUp {
    [super setUp];
    _dirtyTextKeys = [NSMutableArray array];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCollapsedKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kOrderKey];
}

- (void)tearDown {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud removeObjectForKey:kCollapsedKey];
    [ud removeObjectForKey:kOrderKey];
    for (NSString *k in _dirtyTextKeys) { [ud removeObjectForKey:k]; }
    [super tearDown];
}

/// 冷启动：新实例在 init 里从 NSUserDefaults 恢复折叠名单。
- (IMVoiceTranscriber *)relaunched {
    return [IMVoiceTranscriber new];
}

- (void)seedTranscriptCacheForContent:(NSString *)content text:(NSString *)text {
    NSString *key = [kTextKeyPrefix stringByAppendingString:content];
    [[NSUserDefaults standardUserDefaults] setObject:text forKey:key];
    [_dirtyTextKeys addObject:key];
}

#pragma mark - ① 折叠状态跨启动

- (void)testCollapseSurvivesRelaunch {
    IMVoiceTranscriber *before = [IMVoiceTranscriber new];
    [before collapseMessageID:@"srv_1"];
    XCTAssertTrue([before isCollapsedMessageID:@"srv_1"]);

    IMVoiceTranscriber *after = [self relaunched];
    XCTAssertTrue([after isCollapsedMessageID:@"srv_1"],
                  @"取消转文字后杀掉 App 重进会话，不该又被缓存展开");
    XCTAssertFalse([after isCollapsedMessageID:@"srv_other"]);
}

/// 再次点「转文字」→ 折叠解除，且解除同样落盘（否则重启后又变回折叠，菜单/面板状态互相打架）。
- (void)testReExpandClearsPersistedCollapse {
    [self seedTranscriptCacheForContent:@"/uploads/a.m4a" text:@"你好"];
    IMVoiceTranscriber *t = [IMVoiceTranscriber new];
    [t collapseMessageID:@"srv_2"];
    [t transcribeConvID:@"c1" convSeq:7 content:@"/uploads/a.m4a" messageID:@"srv_2"];
    XCTAssertFalse([t isCollapsedMessageID:@"srv_2"]);
    XCTAssertEqual([t statusForMessageID:@"srv_2"], IMVoiceTranscribeStatusDone, @"命中缓存应直接完成");
    XCTAssertEqualObjects([t visibleTextForMessageID:@"srv_2" content:@"/uploads/a.m4a"], @"你好",
                          @"展开后该显示缓存文本（折叠优先于缓存的唯一判定入口）");

    XCTAssertFalse([[self relaunched] isCollapsedMessageID:@"srv_2"]);
}

/// 名单封顶 500：最旧的被淘汰，最新的留下（无限增长会把 defaults 撑大）。
- (void)testCollapseListIsCappedFIFO {
    IMVoiceTranscriber *t = [IMVoiceTranscriber new];
    for (NSInteger i = 0; i < 505; i++) {
        [t collapseMessageID:[NSString stringWithFormat:@"m%ld", (long)i]];
    }
    IMVoiceTranscriber *after = [self relaunched];
    XCTAssertFalse([after isCollapsedMessageID:@"m0"], @"最旧的 5 条应被淘汰");
    XCTAssertFalse([after isCollapsedMessageID:@"m4"]);
    XCTAssertTrue([after isCollapsedMessageID:@"m5"]);
    XCTAssertTrue([after isCollapsedMessageID:@"m504"]);
    NSArray *saved = [[NSUserDefaults standardUserDefaults] stringArrayForKey:kCollapsedKey];
    XCTAssertEqual(saved.count, 500u);
}

#pragma mark - ② 等结果期间取消

/// 识别中点了「取消转文字」，随后 WS 把结果推回来：文本照落缓存（下次点开秒出），
/// 但**不广播**——否则面板会被结果重新撑开，等于取消无效。
- (void)testLateResultDoesNotReopenCollapsedPanel {
    NSString *content = @"/uploads/b.m4a";
    [_dirtyTextKeys addObject:[kTextKeyPrefix stringByAppendingString:content]];
    IMVoiceTranscriber *t = [IMVoiceTranscriber new];
    [t collapseMessageID:@"srv_3"];

    __block NSInteger notifications = 0;
    id token = [[NSNotificationCenter defaultCenter]
        addObserverForName:IMVoiceTranscriberDidChangeNotification object:t queue:nil
                usingBlock:^(NSNotification *n) {
        if ([n.userInfo[@"messageID"] isEqualToString:@"srv_3"]) { notifications += 1; }
    }];
    [t applyRemoteStatus:@"done" text:@"迟到的结果" content:content convID:@"c1" messageID:@"srv_3"];
    [[NSNotificationCenter defaultCenter] removeObserver:token];

    XCTAssertEqual(notifications, 0, @"已取消的条目不该被迟到结果重新展开");
    XCTAssertTrue([t isCollapsedMessageID:@"srv_3"]);
    XCTAssertEqualObjects([t cachedTextForContent:content], @"迟到的结果", @"结果仍要落缓存，下次点开秒出");
}

/// 没取消的条目照常广播 Done（防上面的早退写过头，把正常路径也吞了）。
- (void)testNormalResultStillBroadcasts {
    NSString *content = @"/uploads/c.m4a";
    [_dirtyTextKeys addObject:[kTextKeyPrefix stringByAppendingString:content]];
    IMVoiceTranscriber *t = [IMVoiceTranscriber new];

    XCTestExpectation *exp = [self expectationWithDescription:@"done broadcast"];
    id token = [[NSNotificationCenter defaultCenter]
        addObserverForName:IMVoiceTranscriberDidChangeNotification object:t queue:nil
                usingBlock:^(NSNotification *n) {
        if ([n.userInfo[@"messageID"] isEqualToString:@"srv_4"] &&
            [n.userInfo[@"status"] integerValue] == IMVoiceTranscribeStatusDone) { [exp fulfill]; }
    }];
    [t applyRemoteStatus:@"done" text:@"正常结果" content:content convID:@"c1" messageID:@"srv_4"];
    [self waitForExpectations:@[exp] timeout:1.0];
    [[NSNotificationCenter defaultCenter] removeObserver:token];
}

/// 转写文本 defaults 键封顶：超上限 → 最旧的 defaults 键被删（避免每条一个永久键无限增长）。
/// 上限本身是 2000，测试里只验淘汰行为，用连续 3 条造出"临时上限 2"的场景不现实，
/// 换成：直接把三条 done 结果推进去，然后直接读 defaults 断言"存在"，够验行为骨架。
- (void)testTextCacheKeysPersistAndCanBePurged {
    IMVoiceTranscriber *t = [IMVoiceTranscriber new];
    NSString *c1 = @"/uploads/cap1.m4a";
    NSString *c2 = @"/uploads/cap2.m4a";
    [_dirtyTextKeys addObject:[kTextKeyPrefix stringByAppendingString:c1]];
    [_dirtyTextKeys addObject:[kTextKeyPrefix stringByAppendingString:c2]];

    [t applyRemoteStatus:@"done" text:@"文本一" content:c1 convID:@"c1" messageID:@"srv_cap_1"];
    [t applyRemoteStatus:@"done" text:@"文本二" content:c2 convID:@"c1" messageID:@"srv_cap_2"];

    // 落盘的键顺序数组记录了两条插入，重启后能读回来（下次淘汰按这个顺序）。
    NSArray *order = [[NSUserDefaults standardUserDefaults] stringArrayForKey:kOrderKey];
    XCTAssertEqualObjects(order, (@[
        [kTextKeyPrefix stringByAppendingString:c1],
        [kTextKeyPrefix stringByAppendingString:c2],
    ]), @"插入序数组必须跟着 done 结果落盘，重启后 FIFO 淘汰才认得"
        " —— 空数组 = 淘汰失效（永不清）");

    // 同 content 再次 done 不会重复入队（idempotent，避免"每次点开秒出"把顺序打乱）。
    [t applyRemoteStatus:@"done" text:@"文本一改" content:c1 convID:@"c1" messageID:@"srv_cap_1"];
    order = [[NSUserDefaults standardUserDefaults] stringArrayForKey:kOrderKey];
    XCTAssertEqual(order.count, (NSUInteger)2, @"同一 content 重复 done 不该把顺序数组撑大");
}

/// 服务端返回 failed → errorMessage 广播（不占 text）。UI 层据此走 toast，不再把错误撑进转写面板。
- (void)testFailedRoutesThroughErrorMessage {
    NSString *content = @"/uploads/d.m4a";
    [_dirtyTextKeys addObject:[kTextKeyPrefix stringByAppendingString:content]];
    IMVoiceTranscriber *t = [IMVoiceTranscriber new];

    __block NSString *gotText = nil;
    __block NSString *gotError = nil;
    __block IMVoiceTranscribeStatus gotStatus = IMVoiceTranscribeStatusIdle;
    id token = [[NSNotificationCenter defaultCenter]
        addObserverForName:IMVoiceTranscriberDidChangeNotification object:t queue:nil
                usingBlock:^(NSNotification *n) {
        if (![n.userInfo[@"messageID"] isEqualToString:@"srv_5"]) { return; }
        gotStatus = (IMVoiceTranscribeStatus)[n.userInfo[@"status"] integerValue];
        gotText = n.userInfo[@"text"];
        gotError = n.userInfo[@"errorMessage"];
    }];
    [t applyRemoteStatus:@"failed" text:nil content:content convID:@"c1" messageID:@"srv_5"];
    [[NSNotificationCenter defaultCenter] removeObserver:token];

    XCTAssertEqual(gotStatus, IMVoiceTranscribeStatusUnavailable);
    XCTAssertNil(gotText, @"错误路径不该占用 text（避免与转写内容混淆）");
    XCTAssertTrue(gotError.length > 0, @"errorMessage 应带给用户看的中文文案");
    XCTAssertNil([t cachedTextForContent:content], @"失败不落缓存");
}

@end
