//  IMProtocolTests.m
//  对纯逻辑做单元测试：会话 id 规范化、协议常量、消息模型解析（含脏数据安全）。
//  app-hosted 测试，符号由宿主 App 提供；头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Network/IMProtocol.h"
#import "../IMProgram/Models/IMMessageModel.h"
#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Database/IMDatabase.h"

@interface IMProtocolTests : XCTestCase
@end

@implementation IMProtocolTests

#pragma mark - 会话 id

- (void)testConversationIDIsOrderIndependent {
    // 两个方向必须得到同一个 conv_id（收发双方一致）。
    XCTAssertEqualObjects(IMConversationID(@"1001", @"1002"), IMConversationID(@"1002", @"1001"));
}

- (void)testConversationIDFormat {
    XCTAssertEqualObjects(IMConversationID(@"1001", @"1002"), @"u_1001_u_1002");
    // 规范排序：较小者在前（字符串比较）。
    XCTAssertEqualObjects(IMConversationID(@"9", @"1002"), @"u_1002_u_9");
}

- (void)testConversationIDHandlesNil {
    // 经变量传 nil（绕过字面量 nonnull 静态检查），验证运行期对 nil 的容错。
    NSString *nilID = nil;
    XCTAssertNoThrow(IMConversationID(nilID, @"1002"));
    XCTAssertNotNil(IMConversationID(nilID, nilID));
}

#pragma mark - 协议常量

- (void)testEnvelopeTypeConstants {
    XCTAssertEqualObjects(kIMTypeSendMsg, @"send_msg");
    XCTAssertEqualObjects(kIMTypeAck, @"ack");
    XCTAssertEqualObjects(kIMTypeNewMsg, @"new_msg");
    XCTAssertEqualObjects(kIMTypeReceipt, @"receipt");
    XCTAssertEqualObjects(kIMTypeSyncReq, @"sync_req");
    XCTAssertEqualObjects(kIMTypeSyncResp, @"sync_resp");
    XCTAssertEqualObjects(kIMTypePing, @"ping");
}

#pragma mark - 消息模型

- (void)testReceivedMessageParsing {
    NSDictionary *data = @{
        @"server_msg_id": @"snow-1",
        @"conv_id": @"u_1001_u_1002",
        @"from": @"1001",
        @"content_type": @"text",
        @"content": @"hello",
        @"conv_seq": @57,
        @"timestamp": @1700000000000,
    };
    IMMessageModel *m = [IMMessageModel receivedMessageWithNewMsgData:data];
    XCTAssertEqualObjects(m.serverMsgID, @"snow-1");
    XCTAssertEqualObjects(m.from, @"1001");
    XCTAssertEqualObjects(m.content, @"hello");
    XCTAssertEqual(m.convSeq, 57);
    XCTAssertEqual(m.timestamp, 1700000000000);
    XCTAssertEqual(m.status, IMMessageStatusReceived);
}

- (void)testReceivedMessageToleratesDirtyData {
    // content 为非字符串（脏数据）时应安全降级为空串，不崩溃。
    NSDictionary *dirty = @{ @"content": @123, @"conv_id": @"u_1001_u_1002" };
    IMMessageModel *m = [IMMessageModel receivedMessageWithNewMsgData:dirty];
    XCTAssertEqualObjects(m.content, @"");
    XCTAssertEqualObjects(m.contentType, @"text"); // 缺省回退
    XCTAssertEqual(m.status, IMMessageStatusReceived);
}

#pragma mark - 会话列表模型

- (void)testConversationParsing {
    NSArray *arr = @[
        @{ @"conv_id": @"u_1001_u_1002", @"peer": @"1002", @"latest_conv_seq": @5, @"unread": @0,
           @"last_message": @{ @"content": @"hi", @"from": @"1001", @"timestamp": @1700000000000 } },
        @{ @"conv_id": @"u_1001_u_1003", @"peer": @"1003" }, // 无 last_message
    ];
    NSArray<IMConversation *> *convs = [IMConversation conversationsFromArray:arr];
    XCTAssertEqual(convs.count, 2);
    XCTAssertEqualObjects(convs[0].peer, @"1002");
    XCTAssertEqualObjects(convs[0].lastContent, @"hi");
    XCTAssertEqualObjects(convs[0].lastFrom, @"1001");
    XCTAssertEqual(convs[0].latestConvSeq, 5);
    XCTAssertEqual(convs[0].timestamp, 1700000000000);
    XCTAssertNil(convs[1].lastContent); // 无 last_message
}

- (void)testConversationParsingToleratesDirtyData {
    XCTAssertEqual([IMConversation conversationsFromArray:nil].count, 0);
    XCTAssertEqual([IMConversation conversationsFromArray:(id)@"not-an-array"].count, 0);
    // 数组里混入非字典项应被跳过。
    NSArray *mixed = @[@"junk", @{ @"conv_id": @"u_1_u_2", @"peer": @"2" }];
    XCTAssertEqual([IMConversation conversationsFromArray:mixed].count, 1);
}

#pragma mark - 本地落库 IMDatabase

- (void)testDatabasePersistAndReload {
    NSURL *tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:tmp];

    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = @"c1"; m.convID = @"u_1_u_2"; m.from = @"1"; m.content = @"hi";
    m.contentType = @"text"; m.convSeq = 0; m.status = IMMessageStatusSending;
    [db saveMessage:m];
    // upsert：同 clientMsgID 再存（模拟 ack 后更新状态/seq），数量不增。
    m.status = IMMessageStatusSent; m.convSeq = 3;
    [db saveMessage:m];
    XCTAssertEqual([db messagesForConv:@"u_1_u_2"].count, 1);

    // 新实例从同一文件加载 → 已持久化。
    IMDatabase *db2 = [[IMDatabase alloc] initWithFileURL:tmp];
    NSArray<IMMessageModel *> *loaded = [db2 messagesForConv:@"u_1_u_2"];
    XCTAssertEqual(loaded.count, 1);
    XCTAssertEqualObjects(loaded[0].content, @"hi");
    XCTAssertEqual(loaded[0].convSeq, 3);
    XCTAssertEqual(loaded[0].status, IMMessageStatusSent);
    XCTAssertEqual([db2 maxConvSeqForConv:@"u_1_u_2"], 3); // 派生同步位点
    XCTAssertEqual([db2 maxConvSeqForConv:@"none"], 0);

    [NSFileManager.defaultManager removeItemAtURL:tmp error:NULL];
}

@end
