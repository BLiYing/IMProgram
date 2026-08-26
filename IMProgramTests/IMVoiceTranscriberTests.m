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

@interface IMVoiceTranscriberTests : XCTestCase
@end

@implementation IMVoiceTranscriberTests {
    NSMutableArray<NSString *> *_dirtyTextKeys; // 本例写过的转写缓存 key，tearDown 清
}

- (void)setUp {
    [super setUp];
    _dirtyTextKeys = [NSMutableArray array];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCollapsedKey];
}

- (void)tearDown {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud removeObjectForKey:kCollapsedKey];
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

@end
