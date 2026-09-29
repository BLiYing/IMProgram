//  IMConversationPreviewTests.m
//  IMConversationMediaPreview 纯函数单测（Common/IMConversationPreview.h）：会话列表与应用内横幅
//  共用的媒体摘要判定。覆盖文本回退、caption 覆盖、call 未接判定、voice 时长格式。

#import <XCTest/XCTest.h>
#import "../IMProgram/Common/IMConversationPreview.h"
#import "../IMProgram/Common/IMCallRecord.h"
#import "../IMProgram/Common/IMLocalization.h"

@interface IMConversationPreviewTests : XCTestCase
@end

@implementation IMConversationPreviewTests

- (void)testPlainTextReturnsNilSoCallerFallsBackToContent {
    NSString *r = IMConversationMediaPreview(@"text", nil, @"hello", 0, NO, NO, NULL);
    XCTAssertNil(r);
}

- (void)testUnknownContentTypeReturnsNil {
    NSString *r = IMConversationMediaPreview(@"some_future_type", nil, @"x", 0, NO, NO, NULL);
    XCTAssertNil(r);
}

- (void)testEmptyContentTypeReturnsNil {
    XCTAssertNil(IMConversationMediaPreview(@"", nil, @"x", 0, NO, NO, NULL));
    XCTAssertNil(IMConversationMediaPreview(nil, nil, @"x", 0, NO, NO, NULL));
}

- (void)testImageWithoutCaptionUsesPlaceholder {
    NSString *r = IMConversationMediaPreview(@"image", nil, nil, 0, NO, NO, NULL);
    XCTAssertEqualObjects(r, IMLocalized(@"preview.image"));
}

- (void)testImageWithCaptionShowsCaptionVerbatim {
    NSString *r = IMConversationMediaPreview(@"image", @"生日快乐", nil, 0, NO, NO, NULL);
    XCTAssertEqualObjects(r, @"生日快乐");
}

- (void)testVideoAndFileAlsoRespectCaption {
    XCTAssertEqualObjects(IMConversationMediaPreview(@"video", @"看这个", nil, 0, NO, NO, NULL), @"看这个");
    XCTAssertEqualObjects(IMConversationMediaPreview(@"file", @"合同", nil, 0, NO, NO, NULL), @"合同");
}

- (void)testChatRecordAndLocationIgnoreCaptionAlwaysPlaceholder {
    // chat_record/location 不支持 caption 覆盖（与 image/video/file 不同），caption 传了也不该生效。
    NSString *r = IMConversationMediaPreview(@"chat_record", @"不该出现", nil, 0, NO, NO, NULL);
    XCTAssertEqualObjects(r, IMLocalized(@"preview.chat_record"));
}

- (void)testVoiceFormatsDurationAsMinutesSeconds {
    NSString *r = IMConversationMediaPreview(@"voice", nil, nil, 65000, NO, NO, NULL); // 65s → 1:05
    XCTAssertEqualObjects(r, IMLocalizedFormat(@"preview.voice_duration", @"1:05"));
}

- (void)testVoiceNegativeDurationClampsToZero {
    NSString *r = IMConversationMediaPreview(@"voice", nil, nil, -500, NO, NO, NULL);
    XCTAssertEqualObjects(r, IMLocalizedFormat(@"preview.voice_duration", @"0:00"));
}

- (void)testCallRecordMissedForMeSetsMissedCallOutParam {
    NSString *content = IMCallRecordBuild(@"cid1", NO, @"cancel", 0, NO); // 主叫取消 → 被叫视角「未接来电」
    BOOL missed = NO;
    // mine=NO：以「被叫」视角渲染（viewerIsSender=NO）
    NSString *r = IMConversationMediaPreview(IMContentTypeCall, nil, content, 0, NO, NO, &missed);
    XCTAssertTrue(missed);
    XCTAssertTrue(r.length > 0);
}

- (void)testCallRecordConnectedIsNotMissed {
    NSString *content = IMCallRecordBuild(@"cid2", NO, @"", 30, NO); // 时长>0 → 已接通
    BOOL missed = YES; // 故意先置 YES，验证函数会覆盖成 NO
    NSString *r = IMConversationMediaPreview(IMContentTypeCall, nil, content, 0, NO, NO, &missed);
    XCTAssertFalse(missed);
    XCTAssertTrue(r.length > 0);
}

- (void)testMissedCallOutParamIsResetToNoWhenCallerPassesGarbage {
    BOOL missed = YES;
    IMConversationMediaPreview(@"text", nil, @"hi", 0, NO, NO, &missed);
    XCTAssertFalse(missed); // 非 call 类型也要把 missedCall 复位，调用方不用自己先清零
}

- (void)testNullMissedCallPointerDoesNotCrash {
    XCTAssertNoThrow(IMConversationMediaPreview(IMContentTypeCall,
        nil, IMCallRecordBuild(@"cid3", NO, @"cancel", 0, NO), 0, NO, NO, NULL));
}

@end
