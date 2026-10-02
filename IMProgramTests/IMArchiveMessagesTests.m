#import <XCTest/XCTest.h>

#import "IMDatabase.h"
#import "IMDatabase+Ranges.h"
#import "IMDatabase+Archive.h"
#import "IMMessageModel.h"

/// 资料页「归档索引」读的消息（archiveMessagesForConv:）的**真实 SQL**。
///
/// 它替掉了资料页对 `messagesForConv:` 的全表读（10 万条会话要构造十万个对象）。错法静默：
/// 预筛漏掉一类（页签凭空消失）或带进全部文本（又变回全表）。
@interface IMArchiveMessagesTests : XCTestCase
@end

@implementation IMArchiveMessagesTests {
    IMDatabase *_db;
    NSURL *_url;
}

static NSString * const kConv = @"g_arch";

- (void)setUp {
    [super setUp];
    NSString *name = [NSString stringWithFormat:@"im-archive-test-%@.sqlite", NSUUID.UUID.UUIDString];
    _url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    _db = [[IMDatabase alloc] initWithFileURL:_url];
    [_db useOwnerUserID:@"me"];
}

- (void)tearDown {
    [NSFileManager.defaultManager removeItemAtURL:_url error:NULL];
    [super tearDown];
}

- (void)save:(int64_t)seq type:(NSString *)type content:(NSString *)content {
    IMMessageModel *m = [IMMessageModel receivedMessageWithNewMsgData:@{
        @"server_msg_id": [NSString stringWithFormat:@"s%lld", seq], @"conv_id": kConv, @"from": @"peer",
        @"content": content, @"content_type": type, @"conv_seq": @(seq), @"timestamp": @(1788000000000 + seq),
    }];
    [_db saveIncomingMessage:m advancingSyncedConvSeq:seq];
}

- (NSArray<NSNumber *> *)archiveSeqs {
    NSMutableArray *o = [NSMutableArray array];
    for (IMMessageModel *m in [_db archiveMessagesForConv:kConv]) { [o addObject:@(m.convSeq)]; }
    return o;
}

/// 非文本一律带上；纯文本不带（这才是它比全表读省的地方）；文本含 URL 带上（链接页签的超集）。
- (void)test_只取非文本与含链接的文本 {
    [self save:1 type:@"text" content:@"早上好"];
    [self save:2 type:@"image" content:@"/uploads/a.jpg"];
    [self save:3 type:@"text" content:@"看看 https://example.com/x"];
    [self save:4 type:@"file" content:@"/uploads/b.pdf"];
    [self save:5 type:@"voice" content:@"/uploads/c.m4a"];
    [self save:6 type:@"text" content:@"没有链接的第二句"];
    XCTAssertEqualObjects([self archiveSeqs], (@[@2, @3, @4, @5]));
}

/// 撤回墓碑 / 空内容不计（与 matchesKind: 同口径，别让页签凭空多一格）。
- (void)test_撤回与空内容不计 {
    [self save:1 type:@"image" content:@"/uploads/a.jpg"];
    [self save:2 type:@"image" content:@""];
    [self save:3 type:@"image" content:@"/uploads/c.jpg"];
    XCTAssertEqualObjects([self archiveSeqs], (@[@1, @3]));
}

@end
