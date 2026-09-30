//  IMNotifySettingsMigrationTests.m
//  账号级通知设置迁移/合并的纯逻辑（M5，PROTOCOL §6.13）：同步动作判定、版本比较、JSON 互转。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMNotifySettingsMigration.h"
#import "../IMProgram/Common/IMNotificationSettings.h"

@interface IMNotifySettingsMigrationTests : XCTestCase
@end

@implementation IMNotifySettingsMigrationTests

#pragma mark - IMNotifySettingsSyncDecideAction

- (void)testDirtyAlwaysPushesRegardlessOfServerExists {
    XCTAssertEqual(IMNotifySettingsSyncDecideAction(YES, YES), IMNotifySettingsSyncActionPush);
    XCTAssertEqual(IMNotifySettingsSyncDecideAction(YES, NO), IMNotifySettingsSyncActionPush);
}

- (void)testNotDirtyAndServerExistsAppliesServer {
    XCTAssertEqual(IMNotifySettingsSyncDecideAction(NO, YES), IMNotifySettingsSyncActionApplyServer);
}

- (void)testNotDirtyAndServerMissingPushesLocalAsMigration {
    XCTAssertEqual(IMNotifySettingsSyncDecideAction(NO, NO), IMNotifySettingsSyncActionPush);
}

#pragma mark - IMNotifySettingsShouldRefetchForVersion

- (void)testShouldRefetchWhenIncomingNewer {
    XCTAssertTrue(IMNotifySettingsShouldRefetchForVersion(3, 4));
}

- (void)testShouldNotRefetchWhenSameVersion {
    XCTAssertFalse(IMNotifySettingsShouldRefetchForVersion(4, 4));
}

- (void)testShouldNotRefetchWhenIncomingOlderOrEqual {
    XCTAssertFalse(IMNotifySettingsShouldRefetchForVersion(5, 4));
}

#pragma mark - IMNotifySettingsOwnerSwitched

- (void)testOwnerSwitchedOnlyWhenBothSetAndDifferent {
    XCTAssertTrue(IMNotifySettingsOwnerSwitched(@"1001", @"1002"));
    XCTAssertFalse(IMNotifySettingsOwnerSwitched(@"1001", @"1001"));
    XCTAssertFalse(IMNotifySettingsOwnerSwitched(nil, @"1002"));   // 升级前老数据：归当前账号
    XCTAssertFalse(IMNotifySettingsOwnerSwitched(@"", @"1002"));
    XCTAssertFalse(IMNotifySettingsOwnerSwitched(@"1001", nil));   // 还不知道是谁：不动
}

#pragma mark - IMNotifySettingsValuesFromServerJSON

- (void)testFromServerJSONParsesFullPayload {
    NSDictionary *json = @{
        @"private": @{ @"enabled": @NO, @"preview": @YES, @"sound": @"chord" },
        @"group":   @{ @"enabled": @YES, @"preview": @NO, @"sound": @"chime" },
        @"badge":   @{ @"include_muted": @YES },
    };
    IMNotifySettingsValues *v = IMNotifySettingsValuesFromServerJSON(json);
    XCTAssertFalse(v.privateEnabled);
    XCTAssertTrue(v.privatePreview);
    XCTAssertEqualObjects(v.privateSound, @"chord");
    XCTAssertTrue(v.groupEnabled);
    XCTAssertFalse(v.groupPreview);
    XCTAssertEqualObjects(v.groupSound, @"chime");
    XCTAssertTrue(v.badgeIncludeMuted);
}

- (void)testFromServerJSONFallsBackOnMissingFields {
    // exists=false 时服务端也可能给空 settings；调用方不该崩，字段一律回默认。
    IMNotifySettingsValues *v = IMNotifySettingsValuesFromServerJSON(@{});
    XCTAssertTrue(v.privateEnabled);
    XCTAssertTrue(v.privatePreview);
    XCTAssertEqualObjects(v.privateSound, IMNotificationSoundIDDefault);
    XCTAssertTrue(v.groupEnabled);
    XCTAssertTrue(v.groupPreview);
    XCTAssertEqualObjects(v.groupSound, IMNotificationSoundIDDefault);
    XCTAssertFalse(v.badgeIncludeMuted);
}

- (void)testFromServerJSONNormalizesUnknownSound {
    NSDictionary *json = @{ @"private": @{ @"sound": @"not-a-real-sound" } };
    IMNotifySettingsValues *v = IMNotifySettingsValuesFromServerJSON(json);
    XCTAssertEqualObjects(v.privateSound, IMNotificationSoundIDDefault);
}

- (void)testFromServerJSONHandlesNilInput {
    IMNotifySettingsValues *v = IMNotifySettingsValuesFromServerJSON(nil);
    XCTAssertTrue(v.privateEnabled);
    XCTAssertEqualObjects(v.privateSound, IMNotificationSoundIDDefault);
}

#pragma mark - IMNotifySettingsValuesToServerJSON (往返)

- (void)testToServerJSONRoundTripsWithFromServerJSON {
    IMNotifySettingsValues *original = [IMNotifySettingsValues new];
    original.privateEnabled = NO; original.privatePreview = YES; original.privateSound = IMNotificationSoundIDChord;
    original.groupEnabled = YES; original.groupPreview = NO; original.groupSound = IMNotificationSoundIDNone;
    original.badgeIncludeMuted = YES;

    NSDictionary *json = IMNotifySettingsValuesToServerJSON(original);
    IMNotifySettingsValues *reparsed = IMNotifySettingsValuesFromServerJSON(json);

    XCTAssertEqual(reparsed.privateEnabled, original.privateEnabled);
    XCTAssertEqual(reparsed.privatePreview, original.privatePreview);
    XCTAssertEqualObjects(reparsed.privateSound, original.privateSound);
    XCTAssertEqual(reparsed.groupEnabled, original.groupEnabled);
    XCTAssertEqual(reparsed.groupPreview, original.groupPreview);
    XCTAssertEqualObjects(reparsed.groupSound, original.groupSound);
    XCTAssertEqual(reparsed.badgeIncludeMuted, original.badgeIncludeMuted);
}

- (void)testToServerJSONHandlesNilInput {
    XCTAssertEqualObjects(IMNotifySettingsValuesToServerJSON(nil), @{});
}

@end
