#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMMediaUtil.h"
#import "../IMProgram/Modules/Chat/IMChatMessageLogic.h"

/// 合并转发「聊天记录」共用纯函数：IMRecordItemPreview（单条预览 token）+ IMSummarizeRecord（标题+前 N 行）。
/// 三处渲染（气泡卡片 / 详情 mini 卡片 / 详情行）共用同一映射；含嵌套「套娃」→[聊天记录] 子标题。
/// 与 Web src/chatRecord.test.ts 逐条对齐。
@interface IMChatRecordUtilTests : XCTestCase
@end

@implementation IMChatRecordUtilTests

- (void)testItemPreviewTokensPerType {
    XCTAssertEqualObjects(IMRecordItemPreview(@{@"n": @"a", @"ct": @"text", @"c": @"hi"}), @"hi");
    XCTAssertEqualObjects(IMRecordItemPreview(@{@"n": @"a", @"ct": @"image", @"c": @"u"}), @"[图片]");
    XCTAssertEqualObjects(IMRecordItemPreview(@{@"n": @"a", @"ct": @"video", @"c": @"u"}), @"[视频]");
    XCTAssertEqualObjects(IMRecordItemPreview(@{@"n": @"a", @"ct": @"file", @"c": @"x", @"fn": @"报表.xlsx"}),
                          @"[文件] 报表.xlsx");
}

- (void)testItemPreviewVoiceShowsDurationNotURL {
    // 打包端随包带 d（时长毫秒）；老记录没有 d 时退化成裸 token，但绝不铺 URL。
    XCTAssertEqualObjects(IMRecordItemPreview(@{@"n": @"a", @"ct": @"voice", @"c": @"/uploads/v/x.m4a", @"d": @12400}),
                          @"[语音] 0:12");
    XCTAssertEqualObjects(IMRecordItemPreview(@{@"n": @"a", @"ct": @"voice", @"c": @"/uploads/v/x.m4a"}), @"[语音]");
    XCTAssertEqualObjects(IMRecordItemPreview(@{@"n": @"a", @"ct": @"audio", @"c": @"/uploads/v/x.m4a", @"d": @187000}),
                          @"[语音] 3:07", @"audio 是 voice 落地前的旧命名，同样要认");
}

- (void)testItemPreviewNestedRecordShowsSubtitleNotJSON {
    NSString *child = @"{\"t\":\"1002和1003的聊天记录\",\"items\":[{\"n\":\"1002\",\"ct\":\"text\",\"c\":\"在吗\"}]}";
    NSString *preview = IMRecordItemPreview(@{@"n": @"1001", @"ct": @"chat_record", @"c": child});
    XCTAssertEqualObjects(preview, @"[聊天记录] 1002和1003的聊天记录");
    XCTAssertFalse([preview containsString:@"items"], @"嵌套记录不得铺 JSON 原文");
}

- (void)testItemPreviewMalformedNestedFallsBackWithoutDoubledLabel {
    XCTAssertEqualObjects(IMRecordItemPreview(@{@"n": @"1001", @"ct": @"chat_record", @"c": @"garbled"}), @"[聊天记录]");
}

- (void)testSenderKeyPrefersUIDAndFallsBackToName {
    // 同名不同人必须分得开 → 有 u 就用 u。
    XCTAssertNotEqualObjects(IMRecordSenderKey(@{@"n": @"小明", @"u": @"1001"}),
                             IMRecordSenderKey(@{@"n": @"小明", @"u": @"1002"}));
    XCTAssertEqualObjects(IMRecordSenderKey(@{@"n": @"改过名了", @"u": @"1001"}),
                          IMRecordSenderKey(@{@"n": @"小明", @"u": @"1001"}), @"同 uid 即同一人，昵称变了也算连续");
    // 老记录没有 u → 退回昵称；两个前缀保证 uid 与昵称不会互撞。
    XCTAssertEqualObjects(IMRecordSenderKey(@{@"n": @"小明"}), IMRecordSenderKey(@{@"n": @"小明"}));
    XCTAssertNotEqualObjects(IMRecordSenderKey(@{@"n": @"1001"}), IMRecordSenderKey(@{@"u": @"1001"}));
    XCTAssertNoThrow(IMRecordSenderKey(nil));
    XCTAssertNoThrow(IMRecordSenderKey((NSDictionary *)@"脏数据"));
}

// 卡片内匿名发送者序号（2026-08-31 收口）：条目里的 `u` 不再是真 uid。
// 真 uid 发给一个不在群里的收件人，等于绕过 GET /users/{id} 的「不可枚举」防线
// （那个接口只校验持有合法 token、不校验关系）。
- (void)testRecordSenderKeysForUIDsAnonymizesByFirstAppearance {
    NSDictionary *keys = IMRecordSenderKeysForUIDs(@[@"4827391056", @"9173628401", @"4827391056"]);
    XCTAssertEqualObjects(keys[@"4827391056"], @"s1");
    XCTAssertEqualObjects(keys[@"9173628401"], @"s2", @"按首次出现顺序编号");
    XCTAssertEqual(keys.count, 2u, @"同一人复用同一个键");
}

- (void)testRecordSenderKeysForUIDsSkipsEmptyAndDirtyEntries {
    NSDictionary *keys = IMRecordSenderKeysForUIDs(@[@"", @"1001", (NSString *)@42, @"1002"]);
    XCTAssertEqualObjects(keys[@"1001"], @"s1");
    XCTAssertEqualObjects(keys[@"1002"], @"s2");
    XCTAssertEqual(keys.count, 2u, @"空串与非字符串不占号");
    XCTAssertEqual(IMRecordSenderKeysForUIDs(nil).count, 0u);
}

// 匿名键必须与 IMRecordSenderKey 的相等语义相容——否则「连续同一人只显一次头像」会失效。
- (void)testAnonymousKeysStillDriveSameSenderGrouping {
    NSDictionary *keys = IMRecordSenderKeysForUIDs(@[@"1001", @"1002"]);
    XCTAssertEqualObjects(IMRecordSenderKey(@{@"n": @"改过名了", @"u": keys[@"1001"]}),
                          IMRecordSenderKey(@{@"n": @"小明", @"u": keys[@"1001"]}));
    XCTAssertNotEqualObjects(IMRecordSenderKey(@{@"n": @"小明", @"u": keys[@"1001"]}),
                             IMRecordSenderKey(@{@"n": @"小明", @"u": keys[@"1002"]}));
}

// 标题口径（2026-08-31 两端收敛到微信式）：此前 iOS 写真实群名、Web 按条目发送者数量推，
// 同一个操作两端产出不同标题；且 iOS 那份把群名发给了往往不在群里的收件人。
- (void)testChatRecordTitleGroupNeverLeaksGroupName {
    XCTAssertEqualObjects(IMChatRecordTitle(YES, @"小明", @"我"), @"群聊的聊天记录");
    XCTAssertEqualObjects(IMChatRecordTitle(YES, @"XX病友群", nil), @"群聊的聊天记录",
                          @"即便调用方把群名塞进 peerPublicName 也不该漏出去");
}

- (void)testChatRecordTitleSingleChatWritesBothNames {
    XCTAssertEqualObjects(IMChatRecordTitle(NO, @"小明", @"老王"), @"小明和老王的聊天记录");
}

- (void)testChatRecordTitleDegradesWithoutFallingBackToInternalID {
    XCTAssertEqualObjects(IMChatRecordTitle(NO, @"小明", nil), @"小明的聊天记录");
    XCTAssertEqualObjects(IMChatRecordTitle(NO, @"", @"老王"), @"老王的聊天记录");
    XCTAssertEqualObjects(IMChatRecordTitle(NO, nil, nil), @"聊天记录");
    XCTAssertEqualObjects(IMChatRecordTitle(NO, @"   ", @" "), @"聊天记录");
}

- (void)testSummarizeTitleAndCappedLines {
    NSString *json = @"{\"t\":\"群聊的聊天记录\",\"items\":["
        "{\"n\":\"1002\",\"ct\":\"text\",\"c\":\"你好\"},"
        "{\"n\":\"1003\",\"ct\":\"image\",\"c\":\"u\"},"
        "{\"n\":\"1001\",\"ct\":\"text\",\"c\":\"在吗\"}]}";
    NSString *title = nil; NSArray<NSString *> *lines = nil;
    IMSummarizeRecord(json, &title, &lines, 2);
    XCTAssertEqualObjects(title, @"群聊的聊天记录");
    XCTAssertEqual(lines.count, 2u, @"maxLines=2 只取前 2 行");
    XCTAssertEqualObjects(lines[0], @"1002: 你好");
    XCTAssertEqualObjects(lines[1], @"1003: [图片]");
}

- (void)testSummarizeMalformedFallsBackToDefaultTitle {
    NSString *title = nil; NSArray<NSString *> *lines = nil;
    IMSummarizeRecord(@"not-json", &title, &lines, 4);
    XCTAssertEqualObjects(title, @"聊天记录");
    XCTAssertEqual(lines.count, 0u);
}

- (void)testSummarizeTitleOnlyWhenMaxLinesZero {
    NSString *json = @"{\"t\":\"X\",\"items\":[{\"n\":\"a\",\"ct\":\"text\",\"c\":\"hi\"}]}";
    NSString *title = nil; NSArray<NSString *> *lines = nil;
    IMSummarizeRecord(json, &title, &lines, 0);
    XCTAssertEqualObjects(title, @"X");
    XCTAssertEqual(lines.count, 0u, @"maxLines<=0 只取标题，不展开条目");
}

@end
