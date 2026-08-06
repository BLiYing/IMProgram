#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMDownloadProgress.h"

/// 下载进度模型（M4-7）：与上传镜像。文案分态、环形进度分数、中心圆钮状态机（↓/⏸/✕/↻）。
@interface IMDownloadProgressTests : XCTestCase
@end

@implementation IMDownloadProgressTests

#pragma mark 文案（媒体角标 displayText / 文件条 fileLineText）

- (void)testDisplayTextPerPhase {
    // 未下载：显尺寸（与上传"7.9 MB"同格式）。
    XCTAssertEqualObjects([IMDownloadProgress notStartedWithTotalBytes:8249438].displayText, @"7.9 MB");
    // 下载中：已下 / 总（分子=fraction*total，与上传一致）。
    IMDownloadProgress *dl = [IMDownloadProgress downloadingWithReceived:4124719 total:8249438 pausable:YES];
    XCTAssertEqualObjects(dl.displayText, @"3.9 MB / 7.9 MB");
    XCTAssertEqualObjects([IMDownloadProgress failedWithReceived:0 total:8249438].displayText, @"下载失败");
    XCTAssertEqualObjects([IMDownloadProgress done].displayText, @"");
}

- (void)testFileLineTextPerPhase {
    XCTAssertEqualObjects([IMDownloadProgress notStartedWithTotalBytes:1000].fileLineText, @"点击下载");
    IMDownloadProgress *dl = [IMDownloadProgress downloadingWithReceived:4124719 total:8249438 pausable:YES];
    XCTAssertEqualObjects(dl.fileLineText, @"3.9 MB / 7.9 MB");
    XCTAssertEqualObjects([IMDownloadProgress failedWithReceived:0 total:1000].fileLineText, @"下载失败，点击重试");
    XCTAssertEqualObjects([IMDownloadProgress done].fileLineText, @"点击打开");
}

#pragma mark 环形进度分数

- (void)testFraction {
    XCTAssertEqualWithAccuracy([IMDownloadProgress downloadingWithReceived:5 total:10 pausable:NO].fraction, 0.5, 0.0001);
    // 总未知（0）→ 回退 0（无法算百分比，环形显菊花）。
    XCTAssertEqual([IMDownloadProgress downloadingWithReceived:5 total:0 pausable:NO].fraction, 0.0);
    // 已下超过总（异常）夹到 1。
    XCTAssertEqual([IMDownloadProgress downloadingWithReceived:20 total:10 pausable:NO].fraction, 1.0);
}

#pragma mark 中心圆钮状态机（与上传 ✕/⏸/↑/↻ 镜像，↑ 换 ↓）

- (void)testCenterSymbolStateMachine {
    XCTAssertEqualObjects(IMDownloadCenterSymbolName([IMDownloadProgress notStartedWithTotalBytes:100]), @"arrow.down.circle.fill");
    XCTAssertEqualObjects(IMDownloadCenterSymbolName([IMDownloadProgress pausedWithReceived:10 total:100]), @"arrow.down.circle.fill");
    XCTAssertEqualObjects(IMDownloadCenterSymbolName([IMDownloadProgress downloadingWithReceived:10 total:100 pausable:YES]), @"pause.circle.fill");
    XCTAssertEqualObjects(IMDownloadCenterSymbolName([IMDownloadProgress downloadingWithReceived:10 total:100 pausable:NO]), @"xmark.circle.fill");
    XCTAssertEqualObjects(IMDownloadCenterSymbolName([IMDownloadProgress failedWithReceived:10 total:100]), @"arrow.clockwise.circle.fill");
    // 就绪不给按钮：绝不自动打开/播放。
    XCTAssertNil(IMDownloadCenterSymbolName([IMDownloadProgress done]));
}


#pragma mark 失败分因（草图 §08-05：网络错可 ↻ 重试 vs 服务端已清理不给重试）

- (void)testExpiredFailureHasNoRetryAffordance {
    IMDownloadProgress *netFail = [IMDownloadProgress failedWithReceived:0 total:1000];
    IMDownloadProgress *gone = [IMDownloadProgress expiredWithTotalBytes:1000];

    XCTAssertFalse(netFail.expired);
    XCTAssertTrue(gone.expired);
    XCTAssertEqual(gone.phase, IMDownloadPhaseFailed);

    // 文案分因：网络错引导重试，已失效如实说明、不承诺重试。
    XCTAssertEqualObjects(netFail.fileLineText, @"下载失败，点击重试");
    XCTAssertEqualObjects(gone.fileLineText, @"文件已失效");
    XCTAssertEqualObjects(netFail.displayText, @"下载失败");
    XCTAssertEqualObjects(gone.displayText, @"文件已失效");

    // 中心圆钮：网络错给 ↻；已失效**不给按钮**（点了也没有意义）。
    XCTAssertEqualObjects(IMDownloadCenterSymbolName(netFail), @"arrow.clockwise.circle.fill");
    XCTAssertNil(IMDownloadCenterSymbolName(gone));
}

#pragma mark 无障碍（草图 §08-09）

- (void)testAccessibilityTextPerPhase {
    XCTAssertEqualObjects([IMDownloadProgress notStartedWithTotalBytes:8249438].accessibilityText, @"下载，7.9 MB");
    XCTAssertEqualObjects([IMDownloadProgress notStartedWithTotalBytes:0].accessibilityText, @"下载");
    IMDownloadProgress *dl = [IMDownloadProgress downloadingWithReceived:4124719 total:8249438 pausable:YES];
    XCTAssertEqualObjects(dl.accessibilityText, @"下载中 50%");
    XCTAssertEqualObjects([IMDownloadProgress pausedWithReceived:1 total:2].accessibilityText, @"已暂停，点按继续");
    XCTAssertEqualObjects([IMDownloadProgress failedWithReceived:0 total:1].accessibilityText, @"下载失败，点按重试");
    XCTAssertEqualObjects([IMDownloadProgress expiredWithTotalBytes:1].accessibilityText, @"文件已失效");
    XCTAssertEqualObjects([IMDownloadProgress done].accessibilityText, @"已下载");
}

@end
