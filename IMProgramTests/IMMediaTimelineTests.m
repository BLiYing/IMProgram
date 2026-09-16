//  IMMediaTimelineTests.m
//  媒体时间线定位判据（IMMediaTimeline）。
//
//  这一族错法**全是静默的**：找不到就退回"单开一个查看器"，界面照常，只是不能翻页了——
//  正是 2026-09-16 用户报的那一条（「iOS 点图片不能翻页，媒体库的翻页不是有吗」）。
//  所以第一个用例钉的就是「跨查询批次的两个对象必须认得出是同一条」。

#import <XCTest/XCTest.h>

#import "IMMediaTimeline.h"
#import "IMMessageModel.h"

@interface IMMediaTimelineTests : XCTestCase
@end

@implementation IMMediaTimelineTests

/// 造一条消息。`seq<=0` 表示还没 ack。
static IMMessageModel *MsgSeq(int64_t seq, NSString *cid) {
    IMMessageModel *m = [IMMessageModel new];
    m.convSeq = seq;
    m.clientMsgID = cid ?: @"";
    m.contentType = @"image";
    m.content = [NSString stringWithFormat:@"/uploads/%lld.jpg", (long long)seq];
    return m;
}

// ————————————————— 这次修的那条 —————————————————

/// **同一条消息的两个不同对象**（时间线现查库、点中的那条来自聊天页那一窗）必须认得出。
/// 修之前这里用指针相等，恒 NSNotFound → 查看器永远单开 → 不能翻页。
- (void)test_跨查询批次的同一条消息按convSeq认得出 {
    NSArray *timeline = @[MsgSeq(10, @"a"), MsgSeq(20, @"b"), MsgSeq(30, @"c")];
    IMMessageModel *tappedFromChatWindow = MsgSeq(20, @"b"); // 另一批查询构造出来的对象
    XCTAssertNotEqual(timeline[1], tappedFromChatWindow, @"前提：它们本就不是同一个对象");
    XCTAssertEqual(IMMediaTimelineIndexOfMessage(timeline, tappedFromChatWindow), 1u);
}

- (void)test_首尾两条也要定位得到 {
    NSArray *timeline = @[MsgSeq(10, @"a"), MsgSeq(20, @"b"), MsgSeq(30, @"c")];
    XCTAssertEqual(IMMediaTimelineIndexOfMessage(timeline, MsgSeq(10, @"a")), 0u);
    XCTAssertEqual(IMMediaTimelineIndexOfMessage(timeline, MsgSeq(30, @"c")), 2u);
}

// ————————————————— 未确认的那条 —————————————————

/// 自己刚发出、还没 ack 的：conv_seq 还是 0，只有 clientMsgID 认得出。
- (void)test_未确认的消息按clientMsgID认得出 {
    NSArray *timeline = @[MsgSeq(10, @"a"), MsgSeq(0, @"pending-1"), MsgSeq(0, @"pending-2")];
    XCTAssertEqual(IMMediaTimelineIndexOfMessage(timeline, MsgSeq(0, @"pending-2")), 2u);
}

/// **空 clientMsgID 不许当身份**：否则会命中第一条同样没有 UUID 的行
/// （im-web 那侧的原样事故：点最后一张却定位到第一张）。
- (void)test_空clientMsgID不匹配任何行 {
    NSArray *timeline = @[MsgSeq(0, @""), MsgSeq(0, @"")];
    IMMessageModel *orphan = MsgSeq(0, @"");
    XCTAssertEqual(IMMediaTimelineIndexOfMessage(timeline, orphan), NSNotFound,
                   @"两个身份都没有时只认指针相等，不能瞎命中第一条");
}

/// 两个身份都没有、但就是时间线里那个对象本身 → 指针相等仍然成立。
- (void)test_没有身份但是同一个对象时仍认得出 {
    IMMessageModel *m = MsgSeq(0, @"");
    NSArray *timeline = @[MsgSeq(0, @""), m];
    XCTAssertEqual(IMMediaTimelineIndexOfMessage(timeline, m), 1u);
}

// ————————————————— 边界 —————————————————

- (void)test_不在时间线里回NSNotFound {
    NSArray *timeline = @[MsgSeq(10, @"a"), MsgSeq(20, @"b")];
    XCTAssertEqual(IMMediaTimelineIndexOfMessage(timeline, MsgSeq(99, @"z")), NSNotFound);
}

- (void)test_空时间线与空入参 {
    XCTAssertEqual(IMMediaTimelineIndexOfMessage(@[], MsgSeq(10, @"a")), NSNotFound);
    XCTAssertEqual(IMMediaTimelineIndexOfMessage(nil, MsgSeq(10, @"a")), NSNotFound);
    XCTAssertEqual(IMMediaTimelineIndexOfMessage(@[MsgSeq(10, @"a")], nil), NSNotFound);
}

/// conv_seq 优先于 clientMsgID：已确认的消息按序号找，不受 UUID 对不对得上影响
/// （转发/重发等路径上 UUID 可能被换过）。
- (void)test_已确认时以convSeq为准 {
    NSArray *timeline = @[MsgSeq(10, @"a"), MsgSeq(20, @"b")];
    IMMessageModel *target = MsgSeq(20, @"另一个UUID");
    XCTAssertEqual(IMMediaTimelineIndexOfMessage(timeline, target), 1u);
}

@end
