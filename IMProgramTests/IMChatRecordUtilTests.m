#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMMediaUtil.h"

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

- (void)testItemPreviewNestedRecordShowsSubtitleNotJSON {
    NSString *child = @"{\"t\":\"1002和1003的聊天记录\",\"items\":[{\"n\":\"1002\",\"ct\":\"text\",\"c\":\"在吗\"}]}";
    NSString *preview = IMRecordItemPreview(@{@"n": @"1001", @"ct": @"chat_record", @"c": child});
    XCTAssertEqualObjects(preview, @"[聊天记录] 1002和1003的聊天记录");
    XCTAssertFalse([preview containsString:@"items"], @"嵌套记录不得铺 JSON 原文");
}

- (void)testItemPreviewMalformedNestedFallsBackWithoutDoubledLabel {
    XCTAssertEqualObjects(IMRecordItemPreview(@{@"n": @"1001", @"ct": @"chat_record", @"c": @"garbled"}), @"[聊天记录]");
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
