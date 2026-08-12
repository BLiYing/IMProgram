//  IMPinnedMessageTests.m
//  置顶消息模型（G0）：JSON 解析容错 + 横幅预览文案 + 发送者名。
//  判据与 Web `src/pinned.test.ts` 逐条对齐（parity）。

#import <XCTest/XCTest.h>
#import "IMPinnedMessage.h"

@interface IMPinnedMessageTests : XCTestCase
@end

@implementation IMPinnedMessageTests

- (IMPinnedMessage *)itemWithType:(NSString *)type content:(NSString *)content {
    return [IMPinnedMessage fromJSON:@{ @"conv_seq": @7, @"content_type": type, @"content": content }];
}

#pragma mark - JSON 解析

- (void)testParsesFullPayload {
    IMPinnedMessage *p = [IMPinnedMessage fromJSON:@{
        @"conv_seq": @12, @"server_msg_id": @"srv-1", @"sender": @"1002",
        @"from_nickname": @"小刚", @"content_type": @"text", @"content": @"共享盘链接",
        @"timestamp": @1700, @"pinned_at": @1800,
    }];
    XCTAssertEqual(p.convSeq, 12);
    XCTAssertEqualObjects(p.serverMsgID, @"srv-1");
    XCTAssertEqualObjects(p.from, @"1002");
    XCTAssertEqualObjects(p.fromNickname, @"小刚");
    XCTAssertEqualObjects(p.content, @"共享盘链接");
    XCTAssertEqual(p.timestamp, 1700);
    XCTAssertEqual(p.pinnedAt, 1800);
}

- (void)testRejectsItemsWithoutConvSeq {
    // 没有位点就无法跳转，这条对横幅毫无用处——解析层直接丢弃，别让它占一格空白。
    XCTAssertNil([IMPinnedMessage fromJSON:nil]);
    XCTAssertNil([IMPinnedMessage fromJSON:@{}]);
    XCTAssertNil([IMPinnedMessage fromJSON:@{ @"conv_seq": @0 }]);
    XCTAssertNil([IMPinnedMessage fromJSON:(NSDictionary *)@"not a dict"]);
}

- (void)testSurvivesDirtyTypes {
    // 脏字段一律回退默认值，不抛不崩（服务端字段类型变更时不能整条横幅废掉）。
    IMPinnedMessage *p = [IMPinnedMessage fromJSON:@{
        @"conv_seq": @3, @"sender": @42, @"content": @[], @"content_type": @{}, @"from_nickname": @"",
    }];
    XCTAssertNotNil(p);
    XCTAssertEqualObjects(p.from, @"");
    XCTAssertEqualObjects(p.content, @"");
    XCTAssertEqualObjects(p.contentType, @"text");
    XCTAssertNil(p.fromNickname, @"空昵称应归一为 nil，好让显示层直接回退 uid");
}

#pragma mark - 预览文案

- (void)testTextPreviewCollapsesWhitespace {
    // 横幅是单行省略号布局，换行会把它撑高。
    XCTAssertEqualObjects([[self itemWithType:@"text" content:@"第一行\n第二行   缩进"] previewText],
                          @"第一行 第二行 缩进");
}

- (void)testMediaPreviewShowsTypeWordNotURL {
    XCTAssertEqualObjects([[self itemWithType:@"image" content:@"https://x/a.png"] previewText], @"[图片]");
    XCTAssertEqualObjects([[self itemWithType:@"video" content:@"https://x/a.mp4"] previewText], @"[视频]");
    XCTAssertEqualObjects([[self itemWithType:@"audio" content:@"https://x/a.m4a"] previewText], @"[语音]");
    XCTAssertEqualObjects([[self itemWithType:@"file"  content:@"https://x/a.zip"] previewText], @"[文件]");
}

- (void)testPreviewNeverReturnsEmpty {
    XCTAssertEqualObjects([[self itemWithType:@"text" content:@"   "] previewText], @"（空消息）");
    XCTAssertEqualObjects([[self itemWithType:@"sticker" content:@""] previewText], @"[sticker]");
}

#pragma mark - 发送者名

- (void)testSenderLabelPrefersGroupNicknameAndOnlyInGroups {
    IMPinnedMessage *withNick = [IMPinnedMessage fromJSON:@{
        @"conv_seq": @1, @"sender": @"1002", @"from_nickname": @"小刚" }];
    IMPinnedMessage *noNick = [IMPinnedMessage fromJSON:@{ @"conv_seq": @1, @"sender": @"1002" }];
    XCTAssertEqualObjects([withNick senderLabelForGroup:YES], @"小刚");
    XCTAssertEqualObjects([noNick senderLabelForGroup:YES], @"1002", @"无昵称回退 uid");
    XCTAssertEqualObjects([withNick senderLabelForGroup:NO], @"", @"单聊不显示发送者");
}

@end
