#import <XCTest/XCTest.h>

#import "../IMProgram/Models/IMDownloadSettings.h"
#import "../IMProgram/Models/IMDownloadPolicy.h"

/// 自动下载决策矩阵（M4-7）：网络 × 类别 × 大小 × 单/群 → 静默预取 or 门控。
@interface IMDownloadPolicyTests : XCTestCase
@end

@implementation IMDownloadPolicyTests

static const int64_t MB = 1LL << 20;

#pragma mark 默认解析对齐服务端

- (void)testDefaults {
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    XCTAssertTrue(s.cellular.enabled);
    XCTAssertTrue(s.wifi.enabled);
    XCTAssertEqual(s.cellular.video.maxBytes, 10 * MB); // 中档
    XCTAssertEqual(s.cellular.file.maxBytes, 1 * MB);
    XCTAssertEqual(s.wifi.video.maxBytes, 15 * MB);     // 高档
    XCTAssertEqual(s.wifi.file.maxBytes, 3 * MB);
    XCTAssertEqual(s.wifi.image.maxBytes, 0);           // 图片无上限
    XCTAssertTrue(s.wifi.video.single && s.wifi.video.group);
}

- (void)testParseFromJSON {
    NSDictionary *root = @{ @"version": @7,
        @"settings": @{ @"cellular": @{ @"enabled": @NO,
                            @"video": @{ @"single": @YES, @"group": @NO, @"max_bytes": @(20 * MB) } } } };
    IMDownloadSettings *s = [IMDownloadSettings fromJSON:root];
    XCTAssertEqual(s.version, 7);
    XCTAssertFalse(s.cellular.enabled);
    XCTAssertEqual(s.cellular.video.maxBytes, 20 * MB);
    XCTAssertFalse(s.cellular.video.group);
    // 缺失的 wifi 回退默认。
    XCTAssertEqual(s.wifi.video.maxBytes, 15 * MB);
}

#pragma mark 决策矩阵

- (void)testImageAlwaysAutoWhenEnabled {
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    // 图片无大小闸：任意大小都自动（只要网络开 + 该聊天类型开）。
    XCTAssertTrue(IMShouldAutoDownload(s, @"image", 50 * MB, NO, IMNetworkTypeWifi));
    XCTAssertTrue(IMShouldAutoDownload(s, @"image", 50 * MB, YES, IMNetworkTypeCellular));
}

- (void)testVideoSizeGate {
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    // Wi-Fi 高档 15MB：12MB 自动、20MB 门控。
    XCTAssertTrue(IMShouldAutoDownload(s, @"video", 12 * MB, NO, IMNetworkTypeWifi));
    XCTAssertFalse(IMShouldAutoDownload(s, @"video", 20 * MB, NO, IMNetworkTypeWifi));
    // 移动数据中档 10MB：8MB 自动、12MB 门控。
    XCTAssertTrue(IMShouldAutoDownload(s, @"video", 8 * MB, NO, IMNetworkTypeCellular));
    XCTAssertFalse(IMShouldAutoDownload(s, @"video", 12 * MB, NO, IMNetworkTypeCellular));
}

- (void)testFileSizeGate {
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    XCTAssertTrue(IMShouldAutoDownload(s, @"file", 512 * 1024, NO, IMNetworkTypeCellular)); // <1MB
    XCTAssertFalse(IMShouldAutoDownload(s, @"file", 2 * MB, NO, IMNetworkTypeCellular));     // >1MB
    XCTAssertTrue(IMShouldAutoDownload(s, @"file", 2 * MB, NO, IMNetworkTypeWifi));          // Wi-Fi 3MB
}

- (void)testOfflineNeverAuto {
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    XCTAssertFalse(IMShouldAutoDownload(s, @"image", 1, NO, IMNetworkTypeNone));
    XCTAssertFalse(IMShouldAutoDownload(s, @"video", 1, NO, IMNetworkTypeNone));
}

- (void)testMasterSwitchOff {
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    s.cellular.enabled = NO;
    XCTAssertFalse(IMShouldAutoDownload(s, @"image", 1, NO, IMNetworkTypeCellular));
    XCTAssertFalse(IMShouldAutoDownload(s, @"video", 1, NO, IMNetworkTypeCellular));
    // Wi-Fi 不受影响。
    XCTAssertTrue(IMShouldAutoDownload(s, @"image", 1, NO, IMNetworkTypeWifi));
}

- (void)testChatTypeToggles {
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    s.wifi.video.group = NO; // 群聊视频不自动
    XCTAssertFalse(IMShouldAutoDownload(s, @"video", 5 * MB, YES, IMNetworkTypeWifi)); // 群
    XCTAssertTrue(IMShouldAutoDownload(s, @"video", 5 * MB, NO, IMNetworkTypeWifi));   // 单
    s.wifi.video.single = NO; // 单聊也关
    XCTAssertFalse(IMShouldAutoDownload(s, @"video", 5 * MB, NO, IMNetworkTypeWifi));
}

- (void)testManualDarchAndUnknownSizeGated {
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    s.wifi.video.maxBytes = 0; // 手动档（低）
    XCTAssertFalse(IMShouldAutoDownload(s, @"video", 5 * MB, NO, IMNetworkTypeWifi));
    // 大小未知（0）保守门控。
    XCTAssertFalse(IMShouldAutoDownload([IMDownloadSettings defaultSettings], @"video", 0, NO, IMNetworkTypeWifi));
    XCTAssertFalse(IMShouldAutoDownload([IMDownloadSettings defaultSettings], @"file", 0, NO, IMNetworkTypeWifi));
}

@end
