//  IMProtocolTests.m
//  对纯逻辑做单元测试：会话 id 规范化、协议常量、消息模型解析（含脏数据安全）。
//  app-hosted 测试，符号由宿主 App 提供；头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Network/IMProtocol.h"
#import "../IMProgram/Models/IMMessageModel.h"
#import "../IMProgram/Models/IMConversation.h"
#import "../IMProgram/Database/IMDatabase.h"
#import "../IMProgram/Common/IMTheme.h"

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
    XCTAssertEqualObjects(kIMTypeTyping, @"typing");     // M2
    XCTAssertEqualObjects(kIMTypePresence, @"presence"); // M2
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
        @{ @"conv_id": @"u_1001_u_1002", @"peer": @"1002", @"latest_conv_seq": @5, @"read_seq": @3,
           @"peer_read_seq": @4, @"unread": @2,
           @"last_message": @{ @"content": @"hi", @"from": @"1001", @"timestamp": @1700000000000 } },
        @{ @"conv_id": @"u_1001_u_1003", @"peer": @"1003" }, // 无 last_message
    ];
    NSArray<IMConversation *> *convs = [IMConversation conversationsFromArray:arr];
    XCTAssertEqual(convs.count, 2);
    XCTAssertEqualObjects(convs[0].peer, @"1002");
    XCTAssertEqualObjects(convs[0].lastContent, @"hi");
    XCTAssertEqualObjects(convs[0].lastFrom, @"1001");
    XCTAssertEqual(convs[0].latestConvSeq, 5);
    XCTAssertEqual(convs[0].readSeq, 3);       // M2：本人已读位点
    XCTAssertEqual(convs[0].peerReadSeq, 4);   // 对端已读位点（列表已读双勾用）
    XCTAssertEqual(convs[0].unread, 2);     // M2：未读数
    XCTAssertEqual(convs[0].timestamp, 1700000000000);
    XCTAssertNil(convs[1].lastContent); // 无 last_message
    XCTAssertEqual(convs[1].readSeq, 0); // 缺省
}

- (void)testConversationParsingToleratesDirtyData {
    XCTAssertEqual([IMConversation conversationsFromArray:nil].count, 0);
    XCTAssertEqual([IMConversation conversationsFromArray:(id)@"not-an-array"].count, 0);
    // 数组里混入非字典项应被跳过。
    NSArray *mixed = @[@"junk", @{ @"conv_id": @"u_1_u_2", @"peer": @"2" }];
    XCTAssertEqual([IMConversation conversationsFromArray:mixed].count, 1);
}

#pragma mark - 聊天日期分组（IMTheme 工具）

- (void)testSameDayGrouping {
    int64_t now = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
    XCTAssertTrue([IMTheme isMillis:now sameDayAsMillis:now + 60 * 1000]); // 同日相隔一分钟
    XCTAssertFalse([IMTheme isMillis:now sameDayAsMillis:now - 2LL * 24 * 3600 * 1000]); // 隔两天
    // 0/负值视为无效，恒不同日（用于发送中无服务端时间的消息）。
    XCTAssertFalse([IMTheme isMillis:0 sameDayAsMillis:now]);
    XCTAssertFalse([IMTheme isMillis:now sameDayAsMillis:0]);
}

- (void)testDayHeaderString {
    int64_t now = (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
    XCTAssertEqualObjects([IMTheme dayHeaderStringFromMillis:now], @"今天");
    XCTAssertEqualObjects([IMTheme dayHeaderStringFromMillis:now - 24LL * 3600 * 1000], @"昨天");
    XCTAssertEqualObjects([IMTheme dayHeaderStringFromMillis:0], @""); // 无效时间空串
    // 更早的固定日期 → "M月d日" 或 "yyyy年M月d日"（不空、含「日」）。
    NSString *old = [IMTheme dayHeaderStringFromMillis:1700000000000]; // 2023-11
    XCTAssertTrue(old.length > 0);
    XCTAssertTrue([old hasSuffix:@"日"]);
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

// 被拉黑拒收的失败消息：status=Failed + note（系统提示）落库，重开新实例仍可读回（重进会话不丢"被对方拒收"行）。
- (void)testDatabasePersistsRejectedNote {
    NSURL *tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:tmp];

    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = @"c-reject"; m.convID = @"u_1_u_2"; m.from = @"1"; m.content = @"hi";
    m.contentType = @"text"; m.convSeq = 0; m.status = IMMessageStatusFailed;
    m.note = @"消息已发出，但被对方拒收了";
    [db saveMessage:m];

    IMDatabase *db2 = [[IMDatabase alloc] initWithFileURL:tmp];
    NSArray<IMMessageModel *> *loaded = [db2 messagesForConv:@"u_1_u_2"];
    XCTAssertEqual(loaded.count, 1);
    XCTAssertEqual(loaded[0].status, IMMessageStatusFailed);
    XCTAssertEqual(loaded[0].convSeq, 0);
    XCTAssertEqualObjects(loaded[0].note, @"消息已发出，但被对方拒收了");

    [NSFileManager.defaultManager removeItemAtURL:tmp error:NULL];
}

- (void)testDatabaseDeleteMessage {
    NSURL *tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    IMDatabase *db = [[IMDatabase alloc] initWithFileURL:tmp];

    IMMessageModel *out = [IMMessageModel new]; // 出站：按 clientMsgID 删
    out.clientMsgID = @"c1"; out.convID = @"u_1_u_2"; out.from = @"1"; out.content = @"a";
    out.contentType = @"text"; out.status = IMMessageStatusSent; out.convSeq = 5;
    IMMessageModel *in = [IMMessageModel new]; // 入站：无 clientMsgID，按 conv_seq 删
    in.convID = @"u_1_u_2"; in.from = @"2"; in.content = @"b"; in.contentType = @"text";
    in.status = IMMessageStatusReceived; in.convSeq = 6;
    [db saveMessage:out];
    [db saveMessage:in];
    XCTAssertEqual([db messagesForConv:@"u_1_u_2"].count, 2);

    [db deleteMessage:out];
    NSArray<IMMessageModel *> *left = [db messagesForConv:@"u_1_u_2"];
    XCTAssertEqual(left.count, 1);
    XCTAssertEqualObjects(left[0].content, @"b"); // 只剩入站那条

    [db deleteMessage:in];
    XCTAssertEqual([db messagesForConv:@"u_1_u_2"].count, 0);

    [NSFileManager.defaultManager removeItemAtURL:tmp error:NULL];
}

@end
