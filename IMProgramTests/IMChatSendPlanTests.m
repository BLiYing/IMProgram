//  IMChatSendPlanTests.m
//  点「发送」时粘贴图 + 文字怎么发（IMChatSendPlan）。
//
//  错法全是**静默**的：判错 = 文字丢了 / 重复发了 / 引用丢了 / 编辑被当成发新消息。
//  所以按「会怎么错」钉，用例名就是那个错法。三端口径见头文件注释。

#import <XCTest/XCTest.h>

#import "IMChatSendPlan.h"

@interface IMChatSendPlanTests : XCTestCase
@end

@implementation IMChatSendPlanTests

/// 纯文本：不碰图片，按普通发送。
- (void)test_只有文字就是普通发送 {
    IMChatSendPlan p = IMChatPlanSend(0, YES, NO, NO);
    XCTAssertEqual(p.images, IMChatSendImagesNone);
    XCTAssertEqual(p.text, IMChatSendTextSend);
}

/// 什么都没有：什么都不发（别发空消息）。
- (void)test_什么都没有不发 {
    IMChatSendPlan p = IMChatPlanSend(0, NO, NO, NO);
    XCTAssertEqual(p.images, IMChatSendImagesNone);
    XCTAssertEqual(p.text, IMChatSendTextNone);
}

/// 图文合并只在「恰好 1 张 + 有字 + 非编辑 + 非引用」成立；合并后文本段**必须不再发**，否则文字发两遍。
- (void)test_单图加文字合并成caption_文本段不再发 {
    IMChatSendPlan p = IMChatPlanSend(1, YES, NO, NO);
    XCTAssertEqual(p.images, IMChatSendImagesSingleWithCaption);
    XCTAssertEqual(p.text, IMChatSendTextNone, @"文字已随图发出，再发就是重复");
    XCTAssertFalse(p.imagesShareAlbumID);
}

/// 单图没字：普通发图，不合并（没有 caption 可合）；文本段也不发。
- (void)test_单图没字就只发图 {
    IMChatSendPlan p = IMChatPlanSend(1, NO, NO, NO);
    XCTAssertEqual(p.images, IMChatSendImagesPlain);
    XCTAssertFalse(p.imagesShareAlbumID, @"单张不要相册 ID");
    XCTAssertEqual(p.text, IMChatSendTextNone);
}

/// 多张是相册：共享一个新 group_id；宫格不带 caption，文字另发一条。
- (void)test_多图成相册_文字另发 {
    IMChatSendPlan p = IMChatPlanSend(3, YES, NO, NO);
    XCTAssertEqual(p.images, IMChatSendImagesPlain);
    XCTAssertTrue(p.imagesShareAlbumID);
    XCTAssertEqual(p.text, IMChatSendTextSend);
    // 恰好 2 张就是相册的下限。
    XCTAssertTrue(IMChatPlanSend(2, NO, NO, NO).imagesShareAlbumID);
}

/// iOS/Web 的媒体发送不带 replyTo：引用态下**不合并**，图和字各发，引用只挂在文字上（否则引用丢了）。
- (void)test_引用态不合并_引用留给文本 {
    IMChatSendPlan p = IMChatPlanSend(1, YES, NO, YES);
    XCTAssertEqual(p.images, IMChatSendImagesPlain);
    XCTAssertEqual(p.text, IMChatSendTextSend);
}

/// 编辑态：文字是 msg_op edit，**不是**新消息（判错 = 对端多一条、原消息还是旧的）。
- (void)test_编辑态文字是编辑不是新消息 {
    IMChatSendPlan p = IMChatPlanSend(0, YES, YES, NO);
    XCTAssertEqual(p.text, IMChatSendTextEdit);
    XCTAssertEqual(p.images, IMChatSendImagesNone);
}

/// 编辑态 + 粘贴图：不合并（caption 不能「编辑」），图照发、文字仍是编辑。现状，与 Android 不同（见头文件）。
- (void)test_编辑态带粘贴图不合并 {
    IMChatSendPlan p = IMChatPlanSend(1, YES, YES, NO);
    XCTAssertEqual(p.images, IMChatSendImagesPlain);
    XCTAssertEqual(p.text, IMChatSendTextEdit);
}

/// 编辑 + 引用同时存在：编辑优先于发送，且仍不合并。
- (void)test_编辑加引用 {
    IMChatSendPlan p = IMChatPlanSend(0, YES, YES, YES);
    XCTAssertEqual(p.text, IMChatSendTextEdit);
}

@end
