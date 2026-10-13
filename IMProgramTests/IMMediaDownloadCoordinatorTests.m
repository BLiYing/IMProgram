#import <XCTest/XCTest.h>

#import "../IMProgram/Network/IMMediaDownloadCoordinator.h"
#import "../IMProgram/Network/IMDownloadSettingsStore.h"
#import "../IMProgram/Models/IMDownloadSettings.h"
#import "../IMProgram/Models/IMDownloadProgress.h"
#import "../IMProgram/Models/IMMessageModel.h"
#import "../IMProgram/Common/IMPowerSaving.h"
#import "../IMProgram/Common/IMViewedMediaStore.h"
#import "../IMProgram/Common/IMImageLoader.h"

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
    [self isolatePowerSaving:IMPowerSaving.shared]; // 自动下载判定读省电生效值：每条用例都要排除环境因素
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

#pragma mark - 查看器看过即解门控（共享登记 IMViewedMediaStore）

/// 把共享登记切到一个固定账号，用例结束还原并清掉本账号登记，别污染其它用例 / 真机数据。
- (void)useViewedStoreAsUser:(NSString *)uid {
    IMViewedMediaStore *store = IMViewedMediaStore.shared;
    NSString *(^saved)(void) = store.userIDProvider;
    store.userIDProvider = ^NSString *{ return uid; };
    [store clearCurrentUser];
    [self addTeardownBlock:^{
        [store clearCurrentUser];
        store.userIDProvider = saved;
    }];
}

- (void)testViewedInViewerReleasesGateForImage {
    [self useViewedStoreAsUser:@"viewer-u1"];
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    for (IMDownloadNetworkPolicy *p in @[s.cellular, s.wifi]) { p.image.single = NO; p.image.group = NO; }
    [[IMDownloadSettingsStore shared] applySettings:s];

    IMMessageModel *m = [self received:@"image"];
    XCTAssertNotNil([_coord stateForMessage:m]);       // 门控中
    XCTestExpectation *changed = [self expectationWithDescription:@"onStateChanged"];
    changed.assertForOverFulfill = NO;                 // 上一条用例 teardown 的清空广播可能晚到，不按次数断言
    _coord.onStateChanged = ^(IMMessageModel *mm) { [changed fulfill]; };
    [IMViewedMediaStore.shared markViewedURL:@"http://localhost:8080/uploads/uuid__x.bin"];
    [IMViewedMediaStore.shared markViewedURL:@"http://localhost:8080/uploads/uuid__x.bin"]; // 幂等：不重复通知
    [self waitForExpectations:@[changed] timeout:2];
    // 摘掉回调：teardown 的清空登记也会广播，协调器实例活到整个套件结束，再 fulfill 已结束的期望会崩
    _coord.onStateChanged = nil;
    XCTAssertNil([_coord stateForMessage:m]);          // 返回聊天页：不再磨砂 + ↓
}

/// 回归（模拟器实测）：查看器加载图片会把它写进 IMImageLoader 缓存（isCached=YES），
/// 此时登记变化仍须通知聊天页重配——否则返回时那一行还是看过之前画的磨砂 + ↓。
- (void)testViewedImageAlreadyInImageCacheStillNotifiesRow {
    [self useViewedStoreAsUser:@"viewer-u1"];
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    for (IMDownloadNetworkPolicy *p in @[s.cellular, s.wifi]) { p.image.single = NO; p.image.group = NO; }
    [[IMDownloadSettingsStore shared] applySettings:s];

    IMMessageModel *m = [self received:@"image"];
    XCTAssertNotNil([_coord stateForMessage:m]);       // 先画成磨砂（并被协调器记住）
    NSString *full = @"http://localhost:8080/uploads/uuid__x.bin";
    UIGraphicsBeginImageContext(CGSizeMake(2, 2));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [[IMImageLoader shared] cacheImage:img forURL:full]; // 查看器加载完成 → 进缓存

    XCTestExpectation *changed = [self expectationWithDescription:@"onStateChanged"];
    changed.assertForOverFulfill = NO;
    _coord.onStateChanged = ^(IMMessageModel *mm) { [changed fulfill]; };
    [IMViewedMediaStore.shared markViewedURL:full];
    [self waitForExpectations:@[changed] timeout:2];
    _coord.onStateChanged = nil;
    [[IMImageLoader shared] clearCache];
}

- (void)testViewedInViewerReleasesGateForVideoWithoutDownload {
    [self useViewedStoreAsUser:@"viewer-u1"];
    // 视频 5MB 默认在上限内会自动下；把上限调到 0（手动）才门控。
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    for (IMDownloadNetworkPolicy *p in @[s.cellular, s.wifi]) { p.video.maxBytes = 0; }
    [[IMDownloadSettingsStore shared] applySettings:s];

    IMMessageModel *m = [self received:@"video"];
    m.content = @"/uploads/uuid__viewed.mp4";
    XCTAssertEqual([_coord stateForMessage:m].phase, IMDownloadPhaseNotStarted);
    [IMViewedMediaStore.shared markViewedURL:@"http://localhost:8080/uploads/uuid__viewed.mp4"];
    XCTAssertNil([_coord stateForMessage:m]);          // 看过的视频不再要求「点下载」
    XCTAssertNil([_coord localFileForMessage:m]);      // 但本机并没有原件（看过 ≠ 已下载）
}

- (void)testViewedStoreSharedAcrossCoordinators {
    // 详情页 / 媒体库各自有协调器实例：一处看过，另一处同样放行（这是共享登记的意义）。
    [self useViewedStoreAsUser:@"viewer-u1"];
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    for (IMDownloadNetworkPolicy *p in @[s.cellular, s.wifi]) { p.image.single = NO; p.image.group = NO; }
    [[IMDownloadSettingsStore shared] applySettings:s];
    IMMediaDownloadCoordinator *other = [[IMMediaDownloadCoordinator alloc] initWithHost:@"localhost:8080" myUserID:@"me" isGroup:NO];

    IMMessageModel *m = [self received:@"image"];
    XCTAssertNotNil([other stateForMessage:m]);
    [IMViewedMediaStore.shared markViewedURL:@"http://localhost:8080/uploads/uuid__x.bin"]; // 在别处看过
    XCTAssertNil([other stateForMessage:m]);
}

- (void)testViewedStoreClearRegatesAndOtherUserIsolated {
    [self useViewedStoreAsUser:@"viewer-u1"];
    IMDownloadSettings *s = [IMDownloadSettings defaultSettings];
    for (IMDownloadNetworkPolicy *p in @[s.cellular, s.wifi]) { p.image.single = NO; p.image.group = NO; }
    [[IMDownloadSettingsStore shared] applySettings:s];
    IMMessageModel *m = [self received:@"image"];
    [IMViewedMediaStore.shared markViewedURL:@"http://localhost:8080/uploads/uuid__x.bin"];
    XCTAssertNil([_coord stateForMessage:m]);

    IMViewedMediaStore.shared.userIDProvider = ^NSString *{ return @"viewer-u2"; }; // 换账号：不串
    XCTAssertNotNil([_coord stateForMessage:m]);
    IMViewedMediaStore.shared.userIDProvider = ^NSString *{ return @"viewer-u1"; };
    XCTAssertNil([_coord stateForMessage:m]);
    [IMViewedMediaStore.shared clearCurrentUser];      // 清缓存：回到按策略判定
    XCTAssertNotNil([_coord stateForMessage:m]);
}

#pragma mark - 出作用域点击不崩

- (void)testHandleTapOutOfScopeIsNoop {
    IMMessageModel *m = [self received:@"text"];
    XCTAssertNoThrow([_coord handleTapForMessage:m]);
    XCTAssertNoThrow([_coord cancelDownloadForMessage:m]);
    XCTAssertNil([_coord localFileForMessage:m]);
}

#pragma mark - 省电模式切换时重配已展示的行（P3）

/// 用例读 / 改的是 IMPowerSaving.shared（落在宿主的 standardUserDefaults）：先隔离环境因素——
/// 模拟器开着低电量模式 + 跟随系统、或残留 DEBUG 电量覆盖，都会让 mode=Off 时仍然生效，用例误判。
- (void)isolatePowerSaving:(IMPowerSaving *)ps {
    IMPowerSaveMode savedMode = ps.mode;
    BOOL savedFollow = ps.followSystem;
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSString *savedDebug = [ud stringForKey:@"im.debug.battery"];
    [self addTeardownBlock:^{
        ps.mode = savedMode;
        ps.followSystem = savedFollow;
        if (savedDebug) { [ud setObject:savedDebug forKey:@"im.debug.battery"]; }
    }];
    if (savedDebug) { [ud removeObjectForKey:@"im.debug.battery"]; }
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    ps.followSystem = NO;
    ps.mode = IMPowerSaveModeOff;
}

- (void)testPowerSavingFlipReconfiguresRememberedMediaRows {
    IMPowerSaving *ps = IMPowerSaving.shared;
    IMMediaDownloadCoordinator *coord = [[IMMediaDownloadCoordinator alloc] initWithHost:@"localhost:8080" myUserID:@"me" isGroup:NO];
    IMMessageModel *img = [self received:@"image"];
    IMMessageModel *vid = [self received:@"video"];
    vid.content = @"/uploads/uuid__v.mp4";
    [coord stateForMessage:img];
    [coord stateForMessage:vid];
    NSMutableArray<IMMessageModel *> *changed = [NSMutableArray array];
    coord.onStateChanged = ^(IMMessageModel *m) { [changed addObject:m]; };

    ps.mode = IMPowerSaveModeAlways;                    // 自动下载 / 视频预加载生效值同时翻转
    XCTAssertTrue([changed containsObject:img]);
    XCTAssertTrue([changed containsObject:vid]);

    [changed removeAllObjects];
    ps.threshold = ps.threshold;                        // 偏好没变：不通知
    ps.followSystem = ps.followSystem;
    XCTAssertEqual(changed.count, 0u);

    ps.mode = IMPowerSaveModeOff;                       // 退出省电：再翻回来，行要重跑（才会按策略自动预取）
    XCTAssertTrue([changed containsObject:img]);
}

- (void)testPowerSavingChangeWithoutFlipDoesNotReconfigure {
    IMPowerSaving *ps = IMPowerSaving.shared;
    IMMediaDownloadCoordinator *coord = [[IMMediaDownloadCoordinator alloc] initWithHost:@"localhost:8080" myUserID:@"me" isGroup:NO];
    [coord stateForMessage:[self received:@"image"]];
    __block int n = 0;
    coord.onStateChanged = ^(IMMessageModel *m) { n++; };
    ps.mode = IMPowerSaveModeAuto;                      // 电量未知 → 不生效，生效值没翻转
    XCTAssertEqual(n, 0);
}

@end
