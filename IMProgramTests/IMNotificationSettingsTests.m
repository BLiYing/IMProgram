//  IMNotificationSettingsTests.m
//  IMNotificationSettings 偏好层：默认值、非法值回落、变更通知、重置、跨「进程」持久化（同 IMAppearance 测法：
//  直接操作 NSUserDefaults 再构造新实例模拟"重启后读回"）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMNotificationSettings.h"
#import "../IMProgram/Common/IMAlertDecision.h"

@interface IMNotificationSettingsTests : XCTestCase
@end

@implementation IMNotificationSettingsTests

- (void)setUp {
    [super setUp];
    [self clearDefaults];
}

- (void)tearDown {
    [self clearDefaults];
    [super tearDown];
}

- (void)clearDefaults {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[@"im.notif.private.enabled", @"im.notif.private.preview", @"im.notif.private.sound",
                             @"im.notif.group.enabled", @"im.notif.group.preview", @"im.notif.group.sound",
                             @"im.notif.inApp.sound", @"im.notif.inApp.vibrate", @"im.notif.inApp.preview",
                             @"im.notif.badge.includeMuted"]) {
        [d removeObjectForKey:key];
    }
}

- (void)testDefaultsAllOnExceptBadgeIncludeMuted {
    // §3.7 默认值：私聊/群聊显示通知+预览=开、提示音=默认；应用内提示音/振动=开；角标含免打扰=关。
    IMNotificationSettings *s = [IMNotificationSettings new];
    XCTAssertTrue(s.privateType.enabled);
    XCTAssertTrue(s.privateType.preview);
    XCTAssertEqualObjects(s.privateType.sound, IMNotificationSoundIDDefault);
    XCTAssertTrue(s.groupType.enabled);
    XCTAssertTrue(s.groupType.preview);
    XCTAssertEqualObjects(s.groupType.sound, IMNotificationSoundIDDefault);
    XCTAssertTrue(s.inAppSound);
    XCTAssertTrue(s.inAppVibrate);
    XCTAssertTrue(s.inAppPreview);
    XCTAssertFalse(s.badgeIncludeMuted);
}

- (void)testUnknownSoundIdFallsBackToDefaultOnLoad {
    [NSUserDefaults.standardUserDefaults setObject:@"not-a-real-sound" forKey:@"im.notif.private.sound"];
    IMNotificationSettings *s = [IMNotificationSettings new];
    XCTAssertEqualObjects(s.privateType.sound, IMNotificationSoundIDDefault);
}

- (void)testNoneIsAValidExplicitSoundId {
    [NSUserDefaults.standardUserDefaults setObject:IMNotificationSoundIDNone forKey:@"im.notif.group.sound"];
    IMNotificationSettings *s = [IMNotificationSettings new];
    XCTAssertEqualObjects(s.groupType.sound, IMNotificationSoundIDNone);
}

- (void)testSetEnabledPreviewSoundPersistsAndNormalizes {
    IMNotificationSettings *s = [IMNotificationSettings new];
    [s setEnabled:NO preview:NO sound:@"garbage" forGroup:YES];
    XCTAssertFalse(s.groupType.enabled);
    XCTAssertFalse(s.groupType.preview);
    XCTAssertEqualObjects(s.groupType.sound, IMNotificationSoundIDDefault);

    // 重新构造实例，模拟重启后读回（同一 NSUserDefaults）。
    IMNotificationSettings *reloaded = [IMNotificationSettings new];
    XCTAssertFalse(reloaded.groupType.enabled);
    XCTAssertFalse(reloaded.groupType.preview);
    XCTAssertEqualObjects(reloaded.groupType.sound, IMNotificationSoundIDDefault);
    // 私聊分组不受影响（不同 key）。
    XCTAssertTrue(reloaded.privateType.enabled);
}

- (void)testBadgeIncludeMutedSetterPersists {
    IMNotificationSettings *s = [IMNotificationSettings new];
    s.badgeIncludeMuted = YES;
    IMNotificationSettings *reloaded = [IMNotificationSettings new];
    XCTAssertTrue(reloaded.badgeIncludeMuted);
}

- (void)testChangeNotificationFiresOnMutation {
    IMNotificationSettings *s = [IMNotificationSettings new];
    XCTestExpectation *expectation = [self expectationWithDescription:@"changed"];
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:IMNotificationSettingsDidChangeNotification
                                                                   object:nil queue:nil usingBlock:^(NSNotification *note) {
        [expectation fulfill];
    }];
    s.inAppSound = NO;
    [self waitForExpectations:@[expectation] timeout:1.0];
    [NSNotificationCenter.defaultCenter removeObserver:observer];
}

- (void)testResetToDefaultsRestoresEverythingAndNotifies {
    IMNotificationSettings *s = [IMNotificationSettings new];
    [s setEnabled:NO preview:NO sound:@"chord" forGroup:NO];
    s.inAppSound = NO;
    s.inAppVibrate = NO;
    s.badgeIncludeMuted = YES;

    XCTestExpectation *expectation = [self expectationWithDescription:@"reset-notified"];
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:IMNotificationSettingsDidChangeNotification
                                                                   object:nil queue:nil usingBlock:^(NSNotification *note) {
        [expectation fulfill];
    }];
    [s resetToDefaults];
    [self waitForExpectations:@[expectation] timeout:1.0];
    [NSNotificationCenter.defaultCenter removeObserver:observer];

    XCTAssertTrue(s.privateType.enabled);
    XCTAssertEqualObjects(s.privateType.sound, IMNotificationSoundIDDefault);
    XCTAssertTrue(s.inAppSound);
    XCTAssertTrue(s.inAppVibrate);
    XCTAssertFalse(s.badgeIncludeMuted);
}

- (void)testAlertSnapshotReflectsCurrentValues {
    IMNotificationSettings *s = [IMNotificationSettings new];
    [s setEnabled:NO preview:YES sound:@"chime" forGroup:NO];
    s.inAppVibrate = NO;
    s.badgeIncludeMuted = YES;
    IMAlertSettingsSnapshot *snapshot = [s alertSnapshot];
    XCTAssertFalse(snapshot.privateType.enabled);
    XCTAssertEqualObjects(snapshot.privateType.sound, @"chime");
    XCTAssertTrue(snapshot.groupType.enabled); // 未改，仍默认开
    XCTAssertFalse(snapshot.inApp.vibrate);
    XCTAssertTrue(snapshot.badge.includeMuted);
}

@end
