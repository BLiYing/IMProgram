#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMMediaUtil.h"

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

@end
