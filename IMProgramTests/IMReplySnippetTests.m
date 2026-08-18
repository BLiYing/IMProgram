#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMMediaUtil.h"
#import "../IMProgram/Models/IMMessageModel.h"

// 引用快照 token 本地化与文件名解析（IMBubbleCell / IMLinkCardCell 共用，M4-x 引用增强）。
@interface IMReplySnippetTests : XCTestCase
@end

@implementation IMReplySnippetTests

- (void)testTokenLocalization {
    XCTAssertEqualObjects(IMLocalizeReplySnippet(@"[image]"), @"[图片]");
    XCTAssertEqualObjects(IMLocalizeReplySnippet(@"[video]"), @"[视频]");
    XCTAssertEqualObjects(IMLocalizeReplySnippet(@"[file]"), @"[文件]");
    XCTAssertEqualObjects(IMLocalizeReplySnippet(@"[chat_record]"), @"[聊天记录]");
    XCTAssertEqualObjects(IMLocalizeReplySnippet(@"你好，周末爬山吗"), @"你好，周末爬山吗"); // 普通文本原样
    XCTAssertEqualObjects(IMLocalizeReplySnippet(nil), @"");
}

- (void)testFileSnippetCarriesName {
    XCTAssertEqualObjects(IMLocalizeReplySnippet(@"[file] 季度财报_2026Q2.pdf"), @"[文件] 季度财报_2026Q2.pdf");
    // 幂等：本端存量以本地化形入库，再过本地化不得二次变形。
    XCTAssertEqualObjects(IMLocalizeReplySnippet(@"[文件] 季度财报_2026Q2.pdf"), @"[文件] 季度财报_2026Q2.pdf");
}

- (void)testChatRecordJSONRescue {
    XCTAssertEqualObjects(IMLocalizeReplySnippet(@"{\"t\":\"张三和李四的聊天记录\",\"items\":[]}"),
                          @"[聊天记录] 张三和李四的聊天记录");
}

- (void)testFileNameParsing {
    XCTAssertEqualObjects(IMReplySnippetFileName(@"[file] report.pdf"), @"report.pdf");  // wire 形（服务端冻结）
    XCTAssertEqualObjects(IMReplySnippetFileName(@"[文件] report.pdf"), @"report.pdf"); // 本端存量本地化形
    XCTAssertNil(IMReplySnippetFileName(@"[file]"));  // 无名 token 不算带文件名
    XCTAssertNil(IMReplySnippetFileName(@"[图片]"));
    XCTAssertNil(IMReplySnippetFileName(@"随便一句话"));
    XCTAssertNil(IMReplySnippetFileName(nil));
}

#pragma mark - IMReplySnippet（消息模型 → 引用占位；发送时冻结进 replySnapshot 落库）

- (void)testReplySnippetMediaPlaceholders {
    IMMessageModel *img = [IMMessageModel new]; img.contentType = @"image"; img.content = @"/uploads/x.jpg";
    XCTAssertEqualObjects(IMReplySnippet(img), @"[图片]");
    IMMessageModel *vid = [IMMessageModel new]; vid.contentType = @"video"; vid.content = @"/uploads/x.mp4";
    XCTAssertEqualObjects(IMReplySnippet(vid), @"[视频]");
    IMMessageModel *file = [IMMessageModel new]; file.contentType = @"file"; file.content = @"/uploads/x.bin"; file.fileName = @"季度财报.pdf";
    XCTAssertEqualObjects(IMReplySnippet(file), @"[文件] 季度财报.pdf");
    IMMessageModel *bare = [IMMessageModel new]; bare.contentType = @"file"; bare.content = @""; // 无名兜底（IMMediaFileName("")=""）
    XCTAssertEqualObjects(IMReplySnippet(bare), @"[文件]");
}

- (void)testReplySnippetChatRecordUsesTitle {
    IMMessageModel *rec = [IMMessageModel new];
    rec.contentType = @"chat_record";
    rec.content = @"{\"t\":\"张三和李四的聊天记录\",\"items\":[]}";
    XCTAssertEqualObjects(IMReplySnippet(rec), @"[聊天记录] 张三和李四的聊天记录"); // 与 IMChatRecordSnippet 同口径
}

- (void)testReplySnippetTextTruncatesAt60 {
    IMMessageModel *shortMsg = [IMMessageModel new]; shortMsg.contentType = @"text"; shortMsg.content = @"周末爬山吗";
    XCTAssertEqualObjects(IMReplySnippet(shortMsg), @"周末爬山吗"); // ≤60 原样
    NSString *long70 = [@"" stringByPaddingToLength:70 withString:@"A" startingAtIndex:0];
    IMMessageModel *longMsg = [IMMessageModel new]; longMsg.contentType = @"text"; longMsg.content = long70;
    NSString *snip = IMReplySnippet(longMsg);
    XCTAssertEqual(snip.length, (NSUInteger)61);                    // 前 60 字 + 省略号
    XCTAssertTrue([snip hasSuffix:@"…"]);
    XCTAssertEqualObjects([snip substringToIndex:60], [long70 substringToIndex:60]);
}

@end
