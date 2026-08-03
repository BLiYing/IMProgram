#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMMediaFormat.h"

/// 媒体气泡纯函数：时长/字节/进度文案 + 按原比例的显示尺寸（M4+）。
@interface IMMediaFormatTests : XCTestCase
@end

@implementation IMMediaFormatTests

#pragma mark 时长角标

- (void)testDurationFormatsMinutesAndHours {
    XCTAssertEqualObjects(IMFormatMediaDuration(7000), @"0:07");
    XCTAssertEqualObjects(IMFormatMediaDuration(65000), @"1:05");
    XCTAssertEqualObjects(IMFormatMediaDuration(600000), @"10:00");
    XCTAssertEqualObjects(IMFormatMediaDuration(3723000), @"1:02:03"); // ≥1h 才带小时段
}

- (void)testDurationRoundsUpSubSecondAndHidesWhenUnknown {
    XCTAssertEqualObjects(IMFormatMediaDuration(400), @"0:01", @"不足 1 秒也要显 0:01，不能显 0:00");
    XCTAssertNil(IMFormatMediaDuration(0), @"未知时长 → 不显角标");
    XCTAssertNil(IMFormatMediaDuration(-1));
}

#pragma mark 字节 / 进度

- (void)testByteSizeUnits {
    XCTAssertEqualObjects(IMFormatByteSize(512), @"512 B");
    XCTAssertEqualObjects(IMFormatByteSize(913455), @"892 KB");
    XCTAssertEqualObjects(IMFormatByteSize(8249438), @"7.9 MB");
    XCTAssertEqualObjects(IMFormatByteSize(2LL * 1024 * 1024 * 1024), @"2.0 GB");
    XCTAssertNil(IMFormatByteSize(0));
}

- (void)testUploadProgressShowsSentOverTotal {
    XCTAssertEqualObjects(IMFormatUploadProgress(0.5, 8249438), @"3.9 MB / 7.9 MB");
    XCTAssertEqualObjects(IMFormatUploadProgress(1.0, 8249438), @"7.9 MB / 7.9 MB");
}

- (void)testUploadProgressFallsBackWhenTotalUnknown {
    XCTAssertEqualObjects(IMFormatUploadProgress(0.45, 0), @"45%", @"总大小未知 → 回退百分比");
    XCTAssertEqualObjects(IMFormatUploadProgress(0, 8249438), @"等待中", @"尚未开始上传");
    XCTAssertEqualObjects(IMFormatUploadProgress(2.0, 1024), @"1 KB / 1 KB", @"比例超 1 需夹住");
}

#pragma mark 显示尺寸

- (void)testDisplaySizeKeepsAspectRatioWithinBox {
    CGSize box = CGSizeMake(240, 320);
    CGSize landscape = IMMediaDisplaySize(4032, 3024, box, 80); // 4:3 横图 → 顶宽
    XCTAssertEqualWithAccuracy(landscape.width, 240, 0.5);
    XCTAssertEqualWithAccuracy(landscape.height, 180, 1.0);

    CGSize portrait = IMMediaDisplaySize(1080, 1920, box, 80);  // 9:16 竖视频 → 顶高
    XCTAssertEqualWithAccuracy(portrait.height, 320, 0.5);
    XCTAssertEqualWithAccuracy(portrait.width, 180, 1.0);
}

- (void)testDisplaySizeNeverUpscalesSmallMedia {
    CGSize out = IMMediaDisplaySize(100, 90, CGSizeMake(240, 320), 80);
    XCTAssertEqualWithAccuracy(out.width, 100, 0.5, @"小图保持 1pt/px，不放大糊掉");
    XCTAssertEqualWithAccuracy(out.height, 90, 0.5);
}

- (void)testDisplaySizeClampsExtremeStripToMinSide {
    CGSize out = IMMediaDisplaySize(4000, 200, CGSizeMake(240, 320), 80); // 20:1 长条
    XCTAssertLessThanOrEqual(out.width, 240);
    XCTAssertLessThanOrEqual(out.height, 320);
    XCTAssertGreaterThanOrEqual(out.height, 80, @"短边不得小于 minSide，否则点不中");
}

- (void)testDisplaySizeFallsBackToSquareWhenUnknown {
    CGSize out = IMMediaDisplaySize(0, 0, CGSizeMake(240, 320), 80);
    XCTAssertEqualWithAccuracy(out.width, kIMMediaFallbackSide, 0.5);
    XCTAssertEqualWithAccuracy(out.height, kIMMediaFallbackSide, 0.5);
}

@end
