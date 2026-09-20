//  IMCallRecordTests.m
//  通话记录消息（content_type=call）纯逻辑单测：解析 / 构造 / 渲染（读三端共用向量）/ 发送计划（谁发、发到哪）。
//  向量在 IMServer 仓 docs/conformance/call_record.json（改文案先改向量）；按本文件相对路径找，
//  也可用环境变量 IM_CALL_RECORD_VECTORS 指定。找不到时**失败**而不是跳过——静默跳过等于没测。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMCallRecord.h"
#import "../IMProgram/Common/IMMediaUtil.h"
#import "../IMProgram/Models/IMMessageModel.h"
#import "../IMProgram/Models/IMPinnedMessage.h"
#import "../IMProgram/Modules/RTC/IMRtcCallRecordSender.h"
#import "../IMProgram/Network/IMProtocol.h"

@interface IMCallRecordTests : XCTestCase
@end

@implementation IMCallRecordTests

- (NSArray<NSDictionary *> *)vectors {
    NSString *path = NSProcessInfo.processInfo.environment[@"IM_CALL_RECORD_VECTORS"];
    if (path.length == 0) {
        NSString *repo = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]; // …/IMProgram
        path = [[repo stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"IMServer/docs/conformance/call_record.json"];
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"找不到共用向量 %@（IM_CALL_RECORD_VECTORS 可指定）", path);
    NSDictionary *root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSArray *cases = root[@"cases"];
    XCTAssertGreaterThan(cases.count, 20u);
    return cases;
}

static NSString *jsonString(NSDictionary *d) {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:d options:0 error:NULL] encoding:NSUTF8StringEncoding];
}

#pragma mark - 共用向量

- (void)testConformanceVectors {
    for (NSDictionary *c in [self vectors]) {
        NSString *content = jsonString(c[@"content"]);
        IMCallRecordDisplay *d = IMCallRecordRender(content, [c[@"viewerIsSender"] boolValue],
                                                    [c[@"isGroup"] boolValue], c[@"senderName"]);
        NSDictionary *e = c[@"expect"];
        XCTAssertEqualObjects(d.text, e[@"text"], @"%@", c[@"name"]);
        XCTAssertEqualObjects(d.tone == IMCallRecordToneMissed ? @"missed" : @"normal", e[@"tone"], @"%@", c[@"name"]);
        XCTAssertEqual(d.tappable, [e[@"tappable"] boolValue], @"%@", c[@"name"]);
        XCTAssertEqualObjects(d.preview, e[@"preview"], @"%@", c[@"name"]);
        XCTAssertEqualObjects(IMCallRecordPreview(content, [c[@"viewerIsSender"] boolValue], [c[@"isGroup"] boolValue]),
                              e[@"preview"], @"%@ (preview fn)", c[@"name"]);
    }
}

#pragma mark - 解析 / 构造

- (void)testParseOK {
    IMCallRecord *r = IMCallRecordParse(@"{\"cid\":\"call-77a1\",\"m\":\"video\",\"r\":\"hangup\",\"d\":201}");
    XCTAssertEqualObjects(r.callID, @"call-77a1");
    XCTAssertTrue(r.video);
    XCTAssertEqualObjects(r.reason, @"hangup");
    XCTAssertEqual(r.durationSec, 201);
    XCTAssertFalse(r.group);
}

- (void)testParseGroupAndClamps {
    IMCallRecord *r = IMCallRecordParse(@"{\"cid\":\"c\",\"m\":\"audio\",\"r\":\"x\",\"d\":-5,\"g\":1}");
    XCTAssertTrue(r.group);
    XCTAssertEqual(r.durationSec, 0);
    XCTAssertEqual(IMCallRecordParse(@"{\"cid\":\"c\",\"m\":\"audio\",\"d\":99999999}").durationSec, 86400 * 3);
    XCTAssertEqualObjects(IMCallRecordParse(@"{\"cid\":\"c\",\"m\":\"audio\"}").reason, @""); // 缺 r 不崩
}

/// 缺 cid / m 非法 / 非法 JSON / 非对象：一律 nil，调用方走兜底（不可点、不露 JSON）。
- (void)testParseRejects {
    XCTAssertNil(IMCallRecordParse(@"{\"m\":\"audio\",\"r\":\"hangup\"}"));
    XCTAssertNil(IMCallRecordParse(@"{\"cid\":\"  \",\"m\":\"audio\"}"));
    XCTAssertNil(IMCallRecordParse(@"{\"cid\":\"c\",\"m\":\"screen\"}"));
    XCTAssertNil(IMCallRecordParse(@"not json"));
    XCTAssertNil(IMCallRecordParse(@"[1,2]"));
    XCTAssertNil(IMCallRecordParse(nil));
}

- (void)testBuildRoundTrip {
    NSString *s = IMCallRecordBuild(@"call-1", YES, @"no_answer", 0, YES);
    IMCallRecord *r = IMCallRecordParse(s);
    XCTAssertEqualObjects(r.callID, @"call-1");
    XCTAssertTrue(r.video); XCTAssertTrue(r.group);
    XCTAssertEqualObjects(r.reason, @"no_answer");
    XCTAssertNil(IMCallRecordBuild(@"  ", NO, @"hangup", 1, NO));
    XCTAssertFalse(IMCallRecordParse(IMCallRecordBuild(@"c", NO, @"hangup", -3, NO)).durationSec > 0);
    XCTAssertFalse([IMCallRecordBuild(@"c", NO, @"hangup", 1, NO) containsString:@"\"g\""]); // 单聊不带 g
}

#pragma mark - 兜底 / 预览分支

- (void)testUnsupportedFallbackNeverLeaksJSON {
    NSString *bad = @"{\"cid\":\"\",\"m\":\"audio\"}";
    IMCallRecordDisplay *d = IMCallRecordRender(bad, YES, NO, nil);
    XCTAssertFalse(d.supported);
    XCTAssertFalse(d.tappable);
    XCTAssertEqualObjects(d.text, @"[音视频通话] 请升级新版查看");
    XCTAssertFalse([d.text containsString:@"{"]);
    XCTAssertEqualObjects(d.preview, @"[音视频通话]");
    XCTAssertEqualObjects(IMCallRecordRender(bad, NO, YES, @"张三").text, @"[音视频通话] 请升级新版查看");
}

/// 引用快照 / 置顶横幅：通话记录不可被引用，历史里已有的预本地化为 [音视频通话]。
- (void)testReplySnippetAndPinnedPreview {
    IMMessageModel *m = [IMMessageModel new];
    m.contentType = IMContentTypeCall;
    m.content = @"{\"cid\":\"c\",\"m\":\"audio\",\"r\":\"hangup\",\"d\":9}";
    XCTAssertEqualObjects(IMReplySnippet(m), @"[音视频通话]");
    XCTAssertEqualObjects(IMLocalizeReplySnippet(@"[call]"), @"[音视频通话]");
}

#pragma mark - 发送计划（谁发 / 发到哪 / 发什么）

- (NSDictionary *)summary:(NSDictionary *)over {
    NSMutableDictionary *p = [@{ @"call_id": @"call-9", @"reason": @"hangup", @"duration_sec": @201, @"ended_by": @"1003",
                                 @"media_type": @"video", @"is_group": @NO, @"chat_group_id": @"", @"caller": @"1001",
                                 @"role": @"caller", @"peer": @"1003", @"user_data": @"" } mutableCopy];
    [p addEntriesFromDictionary:over];
    return p;
}

- (void)testPlanCallerSingle {
    NSDictionary *plan = [IMRtcCallRecordSender planForSummaryPayload:[self summary:@{}] selfUID:@"1001"];
    XCTAssertEqualObjects(plan[@"clientMsgID"], @"call-call-9");
    XCTAssertEqualObjects(plan[@"convID"], IMConversationID(@"1001", @"1003"));
    XCTAssertEqualObjects(plan[@"toUser"], @"1003");
    IMCallRecord *r = IMCallRecordParse(plan[@"content"]);
    XCTAssertEqualObjects(r.callID, @"call-9"); XCTAssertTrue(r.video); XCTAssertEqual(r.durationSec, 201); XCTAssertFalse(r.group);
}

/// 被叫永不发（否则一通电话两条）。
- (void)testPlanCalleeNeverSends {
    XCTAssertNil([IMRtcCallRecordSender planForSummaryPayload:[self summary:@{ @"role": @"callee" }] selfUID:@"1003"]);
    XCTAssertNil([IMRtcCallRecordSender planForSummaryPayload:[self summary:@{ @"role": @"" }] selfUID:@"1001"]);
}

- (void)testPlanGroupGoesToGroupConv {
    NSDictionary *plan = [IMRtcCallRecordSender planForSummaryPayload:
        [self summary:@{ @"is_group": @YES, @"chat_group_id": @"g_42", @"peer": @"", @"reason": @"no_answer", @"duration_sec": @0 }]
                                                              selfUID:@"1001"];
    XCTAssertEqualObjects(plan[@"convID"], @"g_42");
    XCTAssertEqualObjects(plan[@"toUser"], @"");
    XCTAssertTrue(IMCallRecordParse(plan[@"content"]).group);
}

- (void)testPlanSkipsWhenMissingFacts {
    XCTAssertNil([IMRtcCallRecordSender planForSummaryPayload:[self summary:@{ @"call_id": @"" }] selfUID:@"1001"]);
    XCTAssertNil([IMRtcCallRecordSender planForSummaryPayload:[self summary:@{ @"peer": @"" }] selfUID:@"1001"]);
    NSDictionary *groupNoID = [self summary:@{ @"is_group": @YES, @"chat_group_id": @"" }];
    XCTAssertNil([IMRtcCallRecordSender planForSummaryPayload:groupNoID selfUID:@"1001"]);
    XCTAssertNil([IMRtcCallRecordSender planForSummaryPayload:[self summary:@{}] selfUID:@""]);
}

@end
