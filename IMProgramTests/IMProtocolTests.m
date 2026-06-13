//  IMProtocolTests.m
//  对纯逻辑做单元测试：会话 id 规范化、协议常量、消息模型解析（含脏数据安全）。
//  app-hosted 测试，符号由宿主 App 提供；头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Network/IMProtocol.h"
#import "../IMProgram/Models/IMMessageModel.h"

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

@end
