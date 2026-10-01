#import <XCTest/XCTest.h>

#import "IMSocketManager+BatchDelete.h"
#import "IMSocketManager.h"

/// 多选批量删除两档（PROTOCOL §6.7.1 / §6.7.2）的纯函数：服务端逐条结果怎么对回请求、
/// msg_hidden 批量帧怎么读。与 im-web `selectDelete.test.ts` 的 summarizeBatch / hiddenSeqsOf 同一组用例。
@interface IMBatchDeleteTests : XCTestCase
@end

@implementation IMBatchDeleteTests

/// 成功的留作本地移除（保持请求顺序），失败 / 缺项都不算成功——失败条数 = 请求数 - 成功数。
- (void)testOKSeqsKeepsOnlyConfirmedSuccesses {
    NSArray *results = @[
        @{ @"conv_seq": @1, @"ok": @YES },
        @{ @"conv_seq": @2, @"ok": @NO, @"code": @300006 },
        @{ @"conv_seq": @4, @"ok": @YES },
    ];
    NSArray<NSNumber *> *ok = IMBatchOKSeqs(@[ @1, @2, @3, @4 ], results);
    XCTAssertEqualObjects(ok, (@[ @1, @4 ]));
    XCTAssertEqual(4 - ok.count, 2u, @"缺项（3）与被拒（2）都计入失败");
}

/// 响应形状不对（没有 results / 元素不是字典 / ok 缺失）：整批按失败算，不能把没删掉的当删掉了。
- (void)testOKSeqsTreatsMalformedAsFailure {
    XCTAssertEqualObjects(IMBatchOKSeqs(@[ @1, @2 ], nil), @[]);
    XCTAssertEqualObjects(IMBatchOKSeqs(@[ @1, @2 ], @{ @"conv_seq": @1 }), @[]);
    XCTAssertEqualObjects(IMBatchOKSeqs(@[ @1 ], (@[ @"x", @{ @"conv_seq": @1 } ])), @[]);
}

/// msg_hidden：批量帧读 conv_seqs（不止首条），单条帧退回 conv_seq。
- (void)testHiddenSeqsReadsBatchFrame {
    XCTAssertEqualObjects(IMMsgHiddenSeqs(@{ @"conv_id": @"g", @"conv_seq": @3, @"conv_seqs": @[ @3, @5, @9 ] }), (@[ @3, @5, @9 ]));
    XCTAssertEqualObjects(IMMsgHiddenSeqs(@{ @"conv_id": @"g", @"conv_seq": @7 }), @[ @7 ]);
    XCTAssertEqualObjects(IMMsgHiddenSeqs(@{ @"conv_id": @"g" }), @[]);
}

/// 批量「为所有人删除」广播帧：一帧 targets 列全批；单条 msg_op（没有 targets）/ 非删除返回 nil，走单条路径。
- (void)testBatchDeleteFrameSeqs {
    NSDictionary *batch = @{ @"op": @"delete", @"conv_id": @"g",
                             @"targets": @[ @{ @"target_conv_seq": @3, @"op_conv_seq": @10 }, @{ @"target_conv_seq": @5, @"op_conv_seq": @11 } ] };
    XCTAssertEqualObjects(IMMsgOpBatchDeleteSeqs(batch), (@[ @3, @5 ]));
    XCTAssertNil(IMMsgOpBatchDeleteSeqs(@{ @"op": @"delete", @"conv_id": @"g", @"target_conv_seq": @3 }));
    XCTAssertNil(IMMsgOpBatchDeleteSeqs(@{ @"op": @"pin", @"targets": @[] }));
}

/// 移除通知：批量一次通知带全集（kIMMsgOpTargetSeqsKey），单条退回 kIMMsgOpTargetSeqKey。
- (void)testRemovedMessageSeqs {
    XCTAssertEqualObjects(IMRemovedMessageSeqs((@{ kIMMsgOpTargetSeqKey: @3, kIMMsgOpTargetSeqsKey: @[ @3, @5 ] })), (@[ @3, @5 ]));
    XCTAssertEqualObjects(IMRemovedMessageSeqs(@{ kIMMsgOpTargetSeqKey: @7 }), @[ @7 ]);
    XCTAssertEqualObjects(IMRemovedMessageSeqs(@{}), @[]);
}

@end
