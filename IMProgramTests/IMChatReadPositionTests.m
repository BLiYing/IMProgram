//  IMChatReadPositionTests.m
//  首条未读下标 + 可见行最大 seq（IMChatReadPosition）。
//
//  错法的后果是**清掉用户的未读**：首条未读找错 → 进会话被锚错位置 → 「可见即读」把读位点推到视口最大 seq，
//  十万条未读打开即清零（user13028 实测 read_position 0 → 109820）。所以按「会怎么错」钉。

#import <XCTest/XCTest.h>

#import "IMChatReadPosition.h"
#import "IMMessageModel.h"

@interface IMChatReadPositionTests : XCTestCase
@end

@implementation IMChatReadPositionTests

/// 可见行（NSIndexPath）：直接传 indexPathsForVisibleRows 的形状。
static NSArray<NSIndexPath *> *Rows(NSInteger first, ...) {
    NSMutableArray *out = [NSMutableArray array];
    va_list ap; va_start(ap, first);
    for (NSInteger r = first; r != NSIntegerMin; r = va_arg(ap, NSInteger)) { [out addObject:[NSIndexPath indexPathForRow:r inSection:0]]; }
    va_end(ap);
    return out;
}

static IMMessageModel *M(int64_t seq, NSString *from, NSString *type) {
    IMMessageModel *m = [[IMMessageModel alloc] init];
    m.convSeq = seq; m.from = from; m.contentType = type;
    return m;
}

#pragma mark - 首条未读

/// 没有未读（服务端说 0）：直接 -1，**不能**去猜「conv_seq > readSeq 的第一条」。
- (void)test_没有未读就不猜 {
    NSArray *msgs = @[M(1, @"peer", @"text"), M(2, @"peer", @"text")];
    XCTAssertEqual(IMChatFirstUnreadIndex(msgs, 0, 0, @"me"), -1);
    XCTAssertEqual(IMChatFirstUnreadIndex(msgs, -3, 0, @"me"), -1);
}

/// 正常：位点之后的第一条对端消息。
- (void)test_位点之后第一条对端消息 {
    NSArray *msgs = @[M(1, @"peer", @"text"), M(2, @"peer", @"text"), M(3, @"peer", @"text"), M(4, @"peer", @"text")];
    XCTAssertEqual(IMChatFirstUnreadIndex(msgs, 2, 2, @"me"), 2);
}

/// readSeq==0 是「一条都没读过」（首次登录/刚入群）：首条未读就是第一条可见消息，不是「没有可锚的位点」。
- (void)test_读位点为0时首条就是第一条 {
    NSArray *msgs = @[M(1, @"peer", @"text"), M(2, @"peer", @"text")];
    XCTAssertEqual(IMChatFirstUnreadIndex(msgs, 2, 0, @"me"), 0);
}

/// 自己发的不计未读（服务端未读计数带 sender<>me）：跳过，不然分割线会落在自己的消息上。
- (void)test_自己发的不计未读 {
    NSArray *msgs = @[M(3, @"me", @"text"), M(4, @"me", @"image"), M(5, @"peer", @"text")];
    XCTAssertEqual(IMChatFirstUnreadIndex(msgs, 1, 2, @"me"), 2);
}

/// system 与 msg_op 事件行不计未读（群改名、入群留痕都是 system）：分割线不能落在它们身上，
/// 否则「以下为 N 条新消息」下方实际多出几行。
- (void)test_系统行与事件行不计未读 {
    NSArray *msgs = @[M(3, @"peer", @"system"), M(4, @"peer", @"msg_op"), M(5, @"peer", @"text")];
    XCTAssertEqual(IMChatFirstUnreadIndex(msgs, 1, 2, @"me"), 2);
}

/// 位点之后全是自己发的/系统行：返回 -1（有「未读数」但这一窗里没有可定位的行——那一段没下载）。
- (void)test_窗口里找不到可定位的行返回负一 {
    NSArray *msgs = @[M(3, @"me", @"text"), M(4, @"peer", @"system")];
    XCTAssertEqual(IMChatFirstUnreadIndex(msgs, 5, 2, @"me"), -1);
    XCTAssertEqual(IMChatFirstUnreadIndex(@[], 5, 2, @"me"), -1);
}

/// 待发件（conv_seq=0，且是自己发的）不会被当成未读；位点比较是 `<=`：等于位点的那条算已读。
- (void)test_等于位点算已读_待发件不算 {
    NSArray *msgs = @[M(2, @"peer", @"text"), M(0, @"me", @"text")];
    XCTAssertEqual(IMChatFirstUnreadIndex(msgs, 1, 2, @"me"), -1);
}

/// 自己的 uid 未知（nil/空）：不能把「from 为空」之类的当成自己；退化为只按位点与类型判。
- (void)test_自己uid未知时不误跳过 {
    NSArray *msgs = @[M(3, @"peer", @"text")];
    XCTAssertEqual(IMChatFirstUnreadIndex(msgs, 1, 2, nil), 0);
    XCTAssertEqual(IMChatFirstUnreadIndex(msgs, 1, 2, @""), 0);
}

#pragma mark - 可见行最大 seq

- (void)test_取可见行里最大的seq {
    NSArray *msgs = @[M(1, @"p", @"text"), M(2, @"p", @"text"), M(9, @"p", @"text"), M(4, @"p", @"text")];
    XCTAssertEqual(IMChatMaxSeqOfRows(msgs, Rows(1, 2, NSIntegerMin)), 9);
    XCTAssertEqual(IMChatMaxSeqOfRows(msgs, Rows(0, NSIntegerMin)), 1);
}

/// 越界行跳过（表格刷新瞬间可见行下标可能比数据源新）；全越界 / 没有可见行返回 0。
- (void)test_越界行跳过 {
    NSArray *msgs = @[M(1, @"p", @"text"), M(2, @"p", @"text")];
    XCTAssertEqual(IMChatMaxSeqOfRows(msgs, Rows(1, 7, -1, NSIntegerMin)), 2);
    XCTAssertEqual(IMChatMaxSeqOfRows(msgs, Rows(7, 8, NSIntegerMin)), 0);
    XCTAssertEqual(IMChatMaxSeqOfRows(msgs, @[]), 0);
    XCTAssertEqual(IMChatMaxSeqOfRows(@[], Rows(0, NSIntegerMin)), 0);
}

/// 视口里只有待发件（conv_seq=0）：位点 0，不能据此推进读位点。
- (void)test_只有待发件时位点为0 {
    NSArray *msgs = @[M(0, @"me", @"text")];
    XCTAssertEqual(IMChatMaxSeqOfRows(msgs, Rows(0, NSIntegerMin)), 0);
}

@end
