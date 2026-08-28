#import <XCTest/XCTest.h>

#import "IMDatabase.h"
#import "IMMessageModel.h"
#import "IMRemarkStore.h"

/// 系统消息结构化分段：解析 / 落库往返 / 隐私口径。
/// 分段来自服务端，必须脏数据安全——解析不出就回退整句（= 历史系统消息的老样子），
/// 绝不能因为一条脏消息把消息列表读不出来。与 Web `src/sysSegments.ts` 同语义。
@interface IMSysSegmentTests : XCTestCase
@end

@implementation IMSysSegmentTests

- (void)testParsesNamedAndPlainSegments {
    NSArray<IMSysSegment *> *segs = [IMSysSegment segmentsFromArray:@[
        @{ @"uid": @"1001", @"text": @"张三" }, @{ @"text": @" 邀请 " },
        @{ @"uid": @"1002", @"text": @"李四" }, @{ @"text": @" 加入群聊" },
    ]];
    XCTAssertEqual(segs.count, 4u);
    XCTAssertEqualObjects(segs[0].uid, @"1001");
    XCTAssertEqualObjects(segs[0].text, @"张三");
    XCTAssertNil(segs[1].uid, @"固定文案段不该带 uid（不会挂点击）");
    XCTAssertEqualObjects(segs[3].text, @" 加入群聊");
}

- (void)testDirtyInputDegradesToNoSegments {
    XCTAssertNil([IMSysSegment segmentsFromArray:nil]);
    XCTAssertNil([IMSysSegment segmentsFromArray:@[]]);
    XCTAssertNil([IMSysSegment segmentsFromArray:(NSArray *)@"张三 邀请 李四"], @"非数组不该崩");
    // 注意：数组字面量里的逗号会被预处理器当作宏参数分隔符，故先落到局部变量再断言。
    NSArray *allDirty = @[@42, @{ @"uid": @"x" }, @{ @"text": @"" }];
    XCTAssertNil([IMSysSegment segmentsFromArray:allDirty], @"一段都解析不出应回退整句渲染");
    // uid 非字符串/空串 → 退化成不可点的固定文案段（不会挂错跳转）。
    NSArray *badUIDs = @[@{ @"uid": @42, @"text": @"张三" }, @{ @"uid": @"", @"text": @"李四" }];
    NSArray<IMSysSegment *> *segs = [IMSysSegment segmentsFromArray:badUIDs];
    XCTAssertEqual(segs.count, 2u);
    XCTAssertNil(segs[0].uid);
    XCTAssertNil(segs[1].uid);
}

/// 分段必须落库：否则重进会话/冷启动读本地库时分段丢失，系统消息退回"显真实昵称、名字不可点"，
/// 与刚收到那一刻不一致（同一条消息两副面孔）。
- (void)testSegmentsSurviveDatabaseRoundTrip {
    NSString *name = [NSString stringWithFormat:@"im-sysseg-%@.sqlite", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];

    IMDatabase *writer = [[IMDatabase alloc] initWithFileURL:url];
    [writer useOwnerUserID:@"alice"];
    IMMessageModel *m = [IMMessageModel new];
    m.convID = @"g_1";
    m.serverMsgID = @"sys-1";
    m.contentType = @"system";
    m.content = @"张三 邀请 李四 加入群聊";
    m.convSeq = 7;
    m.timestamp = 123456789;
    m.sysSegments = [IMSysSegment segmentsFromArray:@[
        @{ @"uid": @"1001", @"text": @"张三" }, @{ @"text": @" 邀请 " },
        @{ @"uid": @"1002", @"text": @"李四" }, @{ @"text": @" 加入群聊" },
    ]];
    [writer saveMessage:m];

    IMDatabase *reader = [[IMDatabase alloc] initWithFileURL:url];
    [reader useOwnerUserID:@"alice"];
    IMMessageModel *loaded = [reader messagesForConv:@"g_1"].firstObject;
    XCTAssertEqualObjects(loaded.content, @"张三 邀请 李四 加入群聊");
    XCTAssertEqual(loaded.sysSegments.count, 4u);
    XCTAssertEqualObjects(loaded.sysSegments[0].uid, @"1001");
    XCTAssertEqualObjects(loaded.sysSegments[2].text, @"李四");
    XCTAssertNil(loaded.sysSegments[1].uid);

    // 无分段的历史消息：读回也是空，渲染回退 content 整句。
    IMMessageModel *old = [IMMessageModel new];
    old.convID = @"g_1"; old.serverMsgID = @"sys-0"; old.contentType = @"system";
    old.content = @"李四 加入了群聊"; old.convSeq = 6; old.timestamp = 1;
    [writer saveMessage:old];
    IMDatabase *reader2 = [[IMDatabase alloc] initWithFileURL:url];
    [reader2 useOwnerUserID:@"alice"];
    for (IMMessageModel *x in [reader2 messagesForConv:@"g_1"]) {
        if ([x.serverMsgID isEqualToString:@"sys-0"]) { XCTAssertNil(x.sysSegments); }
    }

    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
}

/// 分段里的字面是**公开昵称**——这条消息全群都收得到。备注只在收端按 uid 重解析时才出现。
- (void)testSegmentTextIsPublicNameNotRemark {
    [IMRemarkStore.sharedStore applyRemark:@"老王" forUser:@"1002"];
    NSArray<IMSysSegment *> *segs = [IMSysSegment segmentsFromArray:@[@{ @"uid": @"1002", @"text": @"李四" }]];
    XCTAssertEqualObjects(segs[0].text, @"李四", @"服务端下发的字面不该受本机备注影响");
    // 本机渲染时才换成备注（IMSystemCell 用 uid 走 IMRemarkStore 这一步）。
    XCTAssertEqualObjects([IMRemarkStore.sharedStore displayNameForUser:segs[0].uid fallback:segs[0].text], @"老王");
    [IMRemarkStore.sharedStore applyRemark:@"" forUser:@"1002"];
}

@end
