#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMMessageModel.h"
#import "../IMProgram/Modules/Chat/IMChatMessageLogic.h"

/// 发送失败重发的分流判据（红❗可不可点 / 点了走哪条路）。
/// 这是三端共用的口径，写错的两种后果都不小：
///   - 该走「原 client_msg_id 重发」的走成「重传换新 ID」→ 对端可能收到两条；
///   - 该走「重传」的走成「原样重发」→ 把本地路径当媒体地址发出去，对端收到打不开的媒体。
@interface IMResendPolicyTests : XCTestCase
@end

@implementation IMResendPolicyTests

/// 造一条"我发的、失败了"的消息（默认文本、无 note、conv_seq=0）。
static IMMessageModel *failedText(NSString *content) {
    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = @"cid-1";
    m.convID = @"u_1001_u_1002";
    m.from = @"1001";
    m.contentType = @"text";
    m.content = content;
    m.status = IMMessageStatusFailed;
    return m;
}

#pragma mark 不可重发

- (void)testNilAndNotMine {
    XCTAssertEqual(IMResendPolicyForMessage(nil, YES), IMResendPolicyNone);
    XCTAssertEqual(IMResendPolicyForMessage(failedText(@"在吗"), NO), IMResendPolicyNone); // 别人的消息
}

- (void)testOnlyFailedIsResendable {
    IMMessageModel *m = failedText(@"在吗");
    for (NSNumber *st in @[@(IMMessageStatusSending), @(IMMessageStatusSent), @(IMMessageStatusReceived)]) {
        m.status = (IMMessageStatus)st.integerValue;
        XCTAssertEqual(IMResendPolicyForMessage(m, YES), IMResendPolicyNone, @"status=%@", st);
    }
    m.status = IMMessageStatusFailed;
    XCTAssertEqual(IMResendPolicyForMessage(m, YES), IMResendPolicySameID);
}

- (void)testAcknowledgedMessageNeverResends {
    IMMessageModel *m = failedText(@"在吗");
    m.convSeq = 42; // 服务端已收下：再发就是重复
    XCTAssertEqual(IMResendPolicyForMessage(m, YES), IMResendPolicyNone);
}

/// 被服务端明确拒收（拉黑/禁言/非好友/内容过大）：原样重发必然再次被拒 → 不给入口。
/// **判据必须是 note 而不是 noteCode**：noteCode 瞬态不落库，重进会话后归 0。
- (void)testRejectedByServerIsNotResendable {
    IMMessageModel *m = failedText(@"在吗");
    m.note = @"消息已发出，但被对方拒收了";
    m.noteCode = 200102;
    XCTAssertEqual(IMResendPolicyForMessage(m, YES), IMResendPolicyNone);

    m.noteCode = 0; // 重启后：文案还在、码没了 —— 仍然不可重发
    XCTAssertEqual(IMResendPolicyForMessage(m, YES), IMResendPolicyNone);
}

#pragma mark 重传（服务器上根本没有这条）

- (void)testPendingLocalRefRetriesUpload {
    IMMessageModel *m = failedText(@"im-pending://abc.jpg");
    m.contentType = @"image";
    XCTAssertEqual(IMResendPolicyForMessage(m, YES), IMResendPolicyRetryUpload);
}

- (void)testEmptyContentRetriesUpload {
    IMMessageModel *m = failedText(@"");
    m.contentType = @"image"; // 排队/压缩期就失败：还没落盘，content 为空
    XCTAssertEqual(IMResendPolicyForMessage(m, YES), IMResendPolicyRetryUpload);
}

/// 2026-08-27 前语音失败件落库的 tmp 绝对路径（旧方言）。归到重传，否则会被当服务器地址发出去，
/// 对端收到一条永远打不开的语音（2026-08-26 修过一次的坑）。
- (void)testLegacyFileURLRetriesUpload {
    IMMessageModel *m = failedText(@"file:///tmp/voice-1.m4a");
    m.contentType = @"voice";
    XCTAssertEqual(IMResendPolicyForMessage(m, YES), IMResendPolicyRetryUpload);
}

#pragma mark 原 client_msg_id 重发（内容已就绪）

- (void)testPlainTextResendsWithSameID {
    XCTAssertEqual(IMResendPolicyForMessage(failedText(@"在吗"), YES), IMResendPolicySameID);
}

/// 已上传成功、只是 send_msg 失败的媒体：content 已是服务器地址 → 原 ID 重发，不重传。
- (void)testUploadedMediaResendsWithSameID {
    IMMessageModel *m = failedText(@"/media/2026/08/abc.jpg");
    m.contentType = @"image";
    XCTAssertEqual(IMResendPolicyForMessage(m, YES), IMResendPolicySameID);
}

- (void)testUploadedVoiceResendsWithSameID {
    IMMessageModel *m = failedText(@"/media/2026/08/v.m4a");
    m.contentType = @"voice";
    m.waveform = @"AAECAw==";
    XCTAssertEqual(IMResendPolicyForMessage(m, YES), IMResendPolicySameID);
}

@end
