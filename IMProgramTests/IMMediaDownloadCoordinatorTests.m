#import <XCTest/XCTest.h>

#import "../IMProgram/Network/IMMediaDownloadCoordinator.h"
#import "../IMProgram/Network/IMDownloadSettingsStore.h"
#import "../IMProgram/Models/IMDownloadSettings.h"
#import "../IMProgram/Models/IMDownloadProgress.h"
#import "../IMProgram/Models/IMMessageModel.h"

/// 下载编排（M4-7）的门控决策与作用域判定。覆盖 stateForMessage: 的分支：
/// 出作用域（自己发/撤回/非媒体/无地址/本地待发）恒 nil；图片按策略门控（默认放行→nil，关掉→未下载）。
/// 视频/文件的分片下载态依赖真实网络与磁盘，不在纯逻辑单测覆盖（靠手测）。
@interface IMMediaDownloadCoordinatorTests : XCTestCase
@end

@implementation IMMediaDownloadCoordinatorTests {
    IMMediaDownloadCoordinator *_coord;
    IMDownloadSettings *_savedSettings; // 用例会改共享 store，跑完还原，别污染其它用例
}

- (void)setUp {
    [super setUp];
    _coord = [[IMMediaDownloadCoordinator alloc] initWithHost:@"localhost:8080" myUserID:@"me" isGroup:NO];
    _savedSettings = [IMDownloadSettingsStore shared].settings;
    [[IMDownloadSettingsStore shared] applySettings:[IMDownloadSettings defaultSettings]];
}

- (void)tearDown {
    [[IMDownloadSettingsStore shared] applySettings:_savedSettings];
    [super tearDown];
}

/// 造一条「收到的」媒体消息（from=peer，有远端地址）。
- (IMMessageModel *)received:(NSString *)contentType {
    IMMessageModel *m = [IMMessageModel new];
    m.from = @"peer";
    m.convID = @"conv";
    m.convSeq = 10;
    m.contentType = contentType;
    m.content = @"/uploads/uuid__x.bin";
    m.fileSize = 5 * 1024 * 1024;
    return m;
}

#pragma mark - 出作用域：恒 nil（不门控）

- (void)testSelfSentNotGated {
    IMMessageModel *m = [self received:@"image"];
    m.from = @"me"; // 自己发的，本地就有原件
    XCTAssertNil([_coord stateForMessage:m]);
}

- (void)testRecalledNotGated {
    IMMessageModel *m = [self received:@"image"];
    m.recalledAt = 123;
    XCTAssertNil([_coord stateForMessage:m]);
}

- (void)testNonMediaNotGated {
    XCTAssertNil([_coord stateForMessage:[self received:@"text"]]);
    XCTAssertNil([_coord stateForMessage:[self received:@"system"]]);
}

- (void)testEmptyContentNotGated {
    IMMessageModel *m = [self received:@"image"];
    m.content = @"";
    XCTAssertNil([_coord stateForMessage:m]);
}

- (void)testLocalPendingRefNotGated {
    IMMessageModel *m = [self received:@"image"];
    m.content = @"im-pending://abc"; // 本地待发引用，不是网络地址
    XCTAssertNil([_coord stateForMessage:m]);
}

#pragma mark - 图片门控随策略切换

- (void)testImageGatedWhenPolicyOff {
    // 关掉两网络的图片自动下载 → 收到的图片应门控为"未下载"。
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    for (IMDownloadNetworkPolicy *p in @[s.cellular, s.wifi]) { p.image.single = NO; p.image.group = NO; }
    [[IMDownloadSettingsStore shared] applySettings:s];

    IMDownloadProgress *st = [_coord stateForMessage:[self received:@"image"]];
    XCTAssertNotNil(st);
    XCTAssertEqual(st.phase, IMDownloadPhaseNotStarted);
}

- (void)testImageNotGatedWhenPolicyOn {
    // 默认策略图片单群均开 → 放行，直接由 cell 加载，不门控。
    XCTAssertNil([_coord stateForMessage:[self received:@"image"]]);
}

- (void)testImageManualTapReleasesGate {
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    for (IMDownloadNetworkPolicy *p in @[s.cellular, s.wifi]) { p.image.single = NO; p.image.group = NO; }
    [[IMDownloadSettingsStore shared] applySettings:s];

    IMMessageModel *m = [self received:@"image"];
    XCTAssertNotNil([_coord stateForMessage:m]);   // 门控中
    [_coord handleTapForMessage:m];                // 用户点 ↓ → 记为已请求
    XCTAssertNil([_coord stateForMessage:m]);      // 门控解除，交给 cell 加载原图
}

#pragma mark - 出作用域点击不崩

- (void)testHandleTapOutOfScopeIsNoop {
    IMMessageModel *m = [self received:@"text"];
    XCTAssertNoThrow([_coord handleTapForMessage:m]);
    XCTAssertNoThrow([_coord cancelDownloadForMessage:m]);
    XCTAssertNil([_coord localFileForMessage:m]);
}

@end
