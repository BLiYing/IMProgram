//  IMAlertPlayerTests.m
//  IMAlertPlayer：节流时钟推进（playSoundNamed 更新 lastSoundAtMs，previewSoundNamed 不更新）、
//  "none" 不播放。同时顺带验证 Resources/Sounds/*.caf 确实随 file-system-synchronized 组进了测试
//  bundle（找不到资源时 playSoundNamed 静默跳过、lastSoundAtMs 不会推进——本测试能捕捉资源丢失回归）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMAlertPlayer.h"
#import "../IMProgram/Common/IMNotificationSettings.h"

@interface IMAlertPlayerTests : XCTestCase
@end

@implementation IMAlertPlayerTests

- (void)testSharedIsSingleton {
    XCTAssertEqualObjects(IMAlertPlayer.shared, IMAlertPlayer.shared);
}

- (void)testPlayingDefaultSoundAdvancesThrottleClock {
    IMAlertPlayer *player = IMAlertPlayer.shared;
    int64_t before = player.lastSoundAtMs;
    [player playSoundNamed:IMNotificationSoundIDDefault];
    XCTAssertGreaterThan(player.lastSoundAtMs, before, @"bundle 里应能找到 notif_default.caf 并成功播放");
}

- (void)testPlayingNoneDoesNotAdvanceThrottleClock {
    IMAlertPlayer *player = IMAlertPlayer.shared;
    [player playSoundNamed:IMNotificationSoundIDDefault]; // 先推进一次，确认 none 之后确实没有再变
    int64_t before = player.lastSoundAtMs;
    [player playSoundNamed:IMNotificationSoundIDNone];
    XCTAssertEqual(player.lastSoundAtMs, before);
}

- (void)testPreviewDoesNotAdvanceThrottleClock {
    IMAlertPlayer *player = IMAlertPlayer.shared;
    [player playSoundNamed:IMNotificationSoundIDDefault];
    int64_t before = player.lastSoundAtMs;
    [player previewSoundNamed:IMNotificationSoundIDChord];
    XCTAssertEqual(player.lastSoundAtMs, before, @"试听不占用实时消息的节流时钟");
}

- (void)testVibrateAndStopPreviewDoNotCrash {
    XCTAssertNoThrow([IMAlertPlayer.shared vibrate]);
    XCTAssertNoThrow([IMAlertPlayer.shared stopPreview]);
}

@end
