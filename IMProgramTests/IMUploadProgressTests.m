#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMUploadProgress.h"

/// 转码 + 上传融合成一条进度：文案分阶段、总进度只增不减（M4+）。
@interface IMUploadProgressTests : XCTestCase
@end

@implementation IMUploadProgressTests

#pragma mark 文案

- (void)testDisplayTextPerPhase {
    XCTAssertEqualObjects([IMUploadProgress queued].displayText, @"等待中");
    XCTAssertEqualObjects([IMUploadProgress transcodingWithFraction:0.42].displayText, @"压缩中 42%");
    XCTAssertEqualObjects([IMUploadProgress failedProgress].displayText, @"发送失败");
    // 上传期显「已传 / 总大小」，分母是媒体本体字节数。
    IMUploadProgress *up = [IMUploadProgress uploadingWithFraction:0.5 totalBytes:8249438 previous:nil];
    XCTAssertEqualObjects(up.displayText, @"3.9 MB / 7.9 MB");
}

- (void)testTotalUnknownFallsBackToPercent {
    IMUploadProgress *up = [IMUploadProgress uploadingWithFraction:0.45 totalBytes:0 previous:nil];
    XCTAssertEqualObjects(up.displayText, @"45%");
}

#pragma mark 融合进度

- (void)testTranscodeThenUploadNeverGoesBackwards {
    IMUploadProgress *queued = [IMUploadProgress queued];
    IMUploadProgress *midTranscode = [IMUploadProgress transcodingWithFraction:0.5];
    IMUploadProgress *doneTranscode = [IMUploadProgress transcodingWithFraction:1.0];
    // 关键：上传起点必须接在转码终点之后，否则进度会从 35% 掉回 0。
    IMUploadProgress *upStart = [IMUploadProgress uploadingWithFraction:0 totalBytes:1000 previous:doneTranscode];
    IMUploadProgress *upEnd = [IMUploadProgress uploadingWithFraction:1 totalBytes:1000 previous:upStart];

    XCTAssertEqual(queued.overallFraction, 0);
    XCTAssertLessThan(queued.overallFraction, midTranscode.overallFraction);
    XCTAssertLessThan(midTranscode.overallFraction, doneTranscode.overallFraction);
    XCTAssertLessThanOrEqual(doneTranscode.overallFraction, upStart.overallFraction);
    XCTAssertLessThan(upStart.overallFraction, upEnd.overallFraction);
    XCTAssertEqualWithAccuracy(upEnd.overallFraction, 1.0, 0.001);
}

- (void)testNoTranscodePhaseUsesFullScale {
    // 图片/直传视频没有转码阶段：上传 0% 就该是 0%，不能凭空从 35% 起跳。
    IMUploadProgress *up = [IMUploadProgress uploadingWithFraction:0 totalBytes:1000 previous:[IMUploadProgress queued]];
    XCTAssertEqual(up.overallFraction, 0);
    IMUploadProgress *half = [IMUploadProgress uploadingWithFraction:0.5 totalBytes:1000 previous:up];
    XCTAssertEqualWithAccuracy(half.overallFraction, 0.5, 0.001);
}

- (void)testAfterTranscodeIsInheritedAcrossUploadTicks {
    // 上传阶段每次进度回调都会新建对象，"转码过"必须一路继承，否则刻度中途会跳。
    IMUploadProgress *first = [IMUploadProgress uploadingWithFraction:0.1 totalBytes:1000
                                                             previous:[IMUploadProgress transcodingWithFraction:1.0]];
    IMUploadProgress *second = [IMUploadProgress uploadingWithFraction:0.2 totalBytes:1000 previous:first];
    XCTAssertTrue(first.afterTranscode);
    XCTAssertTrue(second.afterTranscode);
    XCTAssertLessThan(first.overallFraction, second.overallFraction);
}

- (void)testFailedIsTerminalAndFlagged {
    IMUploadProgress *failed = [IMUploadProgress failedProgress];
    XCTAssertTrue(failed.failed);
    XCTAssertEqual(failed.phase, IMUploadPhaseFailed);
    XCTAssertEqual(failed.overallFraction, 0);
}

@end
