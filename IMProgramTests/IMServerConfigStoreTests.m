//  IMServerConfigStoreTests.m
//  后台「系统设置」S2：GET /api/v1/server-config 六个运行中可变字段的解析（PROTOCOL 该行）。
//  钉死三条：**字段缺失 → 内置默认**（尤其撤回窗口：缺失被当 0 = 永远可撤回）、**0 → 不限**（仅两个时间窗）、
//  **有值 → 用值**；以及撤回 / 编辑菜单的可见性判定、刷新合并判定、群名限长放行规则。

#import <XCTest/XCTest.h>

#import "../IMProgram/Network/IMServerConfigStore.h"
#import "../IMProgram/Modules/Chat/IMChatMessageLogic.h"
#import "../IMProgram/Models/IMMessageModel.h"
#import "../IMProgram/Common/IMGroupNameDefault.h"

@interface IMServerConfigStoreTests : XCTestCase
@end

@implementation IMServerConfigStoreTests

#pragma mark - 解析

#pragma mark S3a 上传策略

- (void)testUploadPolicyDefaultsOnFreshStore {
    IMServerConfigStore *s = [IMServerConfigStore new];
    XCTAssertTrue(s.uploadEnabled);
    XCTAssertEqual(s.uploadMaxFileBytes, 2147483648LL);
    XCTAssertEqual(s.uploadBlockedExtensions.count, 0u);
}

- (void)testUploadPolicyMissingFieldsMeanAllowedNotZero {
    // 老服务端没有这三项：必须按允许 / 2 GiB / 无禁止，不能当成 NO / 0（那会把所有发送都拦掉）。
    IMServerConfigStore *s = [IMServerConfigStore new];
    [s applyServerConfig:@{ @"max_group_members": @500 }];
    XCTAssertTrue(s.uploadEnabled);
    XCTAssertEqual(s.uploadMaxFileBytes, 2147483648LL);
    XCTAssertEqualObjects(s.uploadBlockedExtensions, @[]);
}

- (void)testUploadPolicyNullAndJunkCountAsMissing {
    IMServerConfigStore *s = [IMServerConfigStore new];
    [s applyServerConfig:@{ @"upload_enabled": NSNull.null, @"upload_max_file_bytes": NSNull.null,
                            @"upload_blocked_extensions": NSNull.null }];
    XCTAssertTrue(s.uploadEnabled);
    XCTAssertEqual(s.uploadMaxFileBytes, 2147483648LL);
    XCTAssertEqualObjects(s.uploadBlockedExtensions, @[]);
    [s applyServerConfig:@{ @"upload_max_file_bytes": @0, @"upload_blocked_extensions": @".exe" }];
    XCTAssertEqual(s.uploadMaxFileBytes, 2147483648LL, @"<=0 当非法 → 默认");
    XCTAssertEqualObjects(s.uploadBlockedExtensions, @[], @"非数组当缺失");
    [s applyServerConfig:@{ @"upload_max_file_bytes": @-5 }];
    XCTAssertEqual(s.uploadMaxFileBytes, 2147483648LL);
}

- (void)testUploadPolicyPresentValuesAreUsed {
    IMServerConfigStore *s = [IMServerConfigStore new];
    [s applyServerConfig:@{ @"upload_enabled": @NO, @"upload_max_file_bytes": @(5LL << 30),
                            @"upload_blocked_extensions": @[ @".exe", @"APK", NSNull.null, @"", @".exe" ] }];
    XCTAssertFalse(s.uploadEnabled);
    XCTAssertEqual(s.uploadMaxFileBytes, 5LL << 30, @"int64：超过 32 位也不能截断");
    XCTAssertEqualObjects(s.uploadBlockedExtensions, (@[ @".exe", @".apk" ]), @"小写、补点、去空去重");
}

- (void)testUploadPolicyChangeIsDetected {
    IMServerConfigStore *s = [IMServerConfigStore new];
    NSDictionary *off = @{ @"upload_enabled": @NO };
    NSDictionary *offMax = @{ @"upload_enabled": @NO, @"upload_max_file_bytes": @(100LL << 20) };
    NSDictionary *offMaxExe = @{ @"upload_enabled": @NO, @"upload_max_file_bytes": @(100LL << 20),
                                 @"upload_blocked_extensions": @[ @".exe" ] };
    XCTAssertTrue([s applyServerConfig:@{}]); // 首次
    XCTAssertFalse([s applyServerConfig:@{}]);
    XCTAssertTrue([s applyServerConfig:off]);
    XCTAssertFalse([s applyServerConfig:off]);
    XCTAssertTrue([s applyServerConfig:offMax]);
    XCTAssertTrue([s applyServerConfig:offMaxExe]);
    XCTAssertFalse([s applyServerConfig:offMaxExe]);
}

- (void)testFreshStoreUsesBuiltInDefaults {
    IMServerConfigStore *s = [IMServerConfigStore new];
    XCTAssertFalse(s.loaded);
    XCTAssertEqual(s.recallWindowSec, 120);
    XCTAssertEqual(s.editWindowSec, 0);
    XCTAssertEqual(s.forwardMaxTargets, 9);
    XCTAssertEqual(s.mergeForwardMax, 100);
    XCTAssertEqual(s.groupNameMaxLen, 30);
    XCTAssertEqual(s.groupAnnouncementMaxLen, 500);
}

- (void)testMissingFieldsFallBackToDefaultsNotZero {
    // 老服务端：只有群上限三项。
    IMServerConfigStore *s = [IMServerConfigStore new];
    [s applyServerConfig:@{ @"max_group_members": @500, @"supergroup_enabled": @YES, @"max_supergroup_members": @20000 }];
    XCTAssertTrue(s.loaded);
    XCTAssertEqual(s.maxGroupMembers, 500);
    XCTAssertEqual(s.recallWindowSec, 120, @"缺失的撤回窗口必须是 120 秒，不能当成 0（= 永远可撤回）");
    XCTAssertEqual(s.editWindowSec, 0);
    XCTAssertEqual(s.forwardMaxTargets, 9);
    XCTAssertEqual(s.mergeForwardMax, 100);
    XCTAssertEqual(s.groupNameMaxLen, 30);
    XCTAssertEqual(s.groupAnnouncementMaxLen, 500);
}

- (void)testNullFieldsCountAsMissing {
    IMServerConfigStore *s = [IMServerConfigStore new];
    [s applyServerConfig:@{ @"recall_window_sec": NSNull.null, @"forward_max_targets": @"12" }];
    XCTAssertEqual(s.recallWindowSec, 120);
    XCTAssertEqual(s.forwardMaxTargets, 9, @"非数字当缺失");
}

- (void)testZeroMeansUnlimitedForTimeWindows {
    IMServerConfigStore *s = [IMServerConfigStore new];
    [s applyServerConfig:@{ @"recall_window_sec": @0, @"edit_window_sec": @0 }];
    XCTAssertEqual(s.recallWindowSec, 0);
    XCTAssertEqual(s.editWindowSec, 0);
    int64_t sent = 1000;
    int64_t aYearLater = sent + 365LL * 24 * 3600 * 1000;
    XCTAssertTrue([s canRecallMessageSentAt:sent nowMs:aYearLater]);
    XCTAssertTrue([s canEditMessageSentAt:sent nowMs:aYearLater]);
}

- (void)testZeroOrNegativeCountsFallBackForNonWindowFields {
    // 这四项服务端范围下限都是 1：0 / 负数是非法值，按默认处理而不是「一个都不能选」。
    IMServerConfigStore *s = [IMServerConfigStore new];
    [s applyServerConfig:@{ @"forward_max_targets": @0, @"merge_forward_max": @0,
                            @"group_name_max_len": @-1, @"group_announcement_max_len": @0,
                            @"recall_window_sec": @-5 }];
    XCTAssertEqual(s.forwardMaxTargets, 9);
    XCTAssertEqual(s.mergeForwardMax, 100);
    XCTAssertEqual(s.groupNameMaxLen, 30);
    XCTAssertEqual(s.groupAnnouncementMaxLen, 500);
    XCTAssertEqual(s.recallWindowSec, 120, @"负的时间窗当非法 → 默认");
}

- (void)testPresentValuesAreUsed {
    IMServerConfigStore *s = [IMServerConfigStore new];
    BOOL changed = [s applyServerConfig:@{ @"recall_window_sec": @600, @"edit_window_sec": @3600,
                                           @"forward_max_targets": @20, @"merge_forward_max": @50,
                                           @"group_name_max_len": @60, @"group_announcement_max_len": @2000 }];
    XCTAssertTrue(changed);
    XCTAssertEqual(s.recallWindowSec, 600);
    XCTAssertEqual(s.editWindowSec, 3600);
    XCTAssertEqual(s.forwardMaxTargets, 20);
    XCTAssertEqual(s.mergeForwardMax, 50);
    XCTAssertEqual(s.groupNameMaxLen, 60);
    XCTAssertEqual(s.groupAnnouncementMaxLen, 2000);
}

- (void)testMergeForwardMaxCappedByMultiSelectLimit {
    IMServerConfigStore *s = [IMServerConfigStore new];
    [s applyServerConfig:@{ @"merge_forward_max": @500 }];
    XCTAssertEqual(s.mergeForwardMax, 100, @"合并转发上限 = min(多选上限 100, 下发值)");
}

- (void)testApplyReportsChangeOnlyWhenValuesDiffer {
    IMServerConfigStore *s = [IMServerConfigStore new];
    NSDictionary *d = @{ @"max_group_members": @500, @"recall_window_sec": @300 };
    XCTAssertTrue([s applyServerConfig:d], @"首次拉到算变化");
    XCTAssertFalse([s applyServerConfig:d], @"同值重拉不发通知");
    NSDictionary *d2 = @{ @"max_group_members": @500, @"recall_window_sec": @0 };
    XCTAssertTrue([s applyServerConfig:d2]);
}

#pragma mark - 时间窗

- (void)testWithinWindowBoundary {
    XCTAssertTrue(IMServerConfigWithinWindow(0, 120 * 1000, 120), @"边界含等号（与原 kIMRecallWindowMs 同口径）");
    XCTAssertFalse(IMServerConfigWithinWindow(0, 120 * 1000 + 1, 120));
    XCTAssertTrue(IMServerConfigWithinWindow(0, INT64_MAX / 2, 0), @"0 = 不限");
}

- (IMMessageModel *)mineText:(int64_t)ts {
    IMMessageModel *m = [IMMessageModel new];
    m.contentType = @"text";
    m.content = @"hi";
    m.convSeq = 7;
    m.timestamp = ts;
    return m;
}

- (void)testRecallVisibility {
    IMMessageModel *m = [self mineText:1000];
    int64_t now = 1000 + 121 * 1000;
    XCTAssertFalse(IMChatCanShowRecall(m, YES, now, 120), @"默认 2 分钟：超窗隐藏");
    XCTAssertTrue(IMChatCanShowRecall(m, YES, 1000 + 60 * 1000, 120));
    XCTAssertTrue(IMChatCanShowRecall(m, YES, now, 0), @"0 = 不限");
    XCTAssertTrue(IMChatCanShowRecall(m, YES, now, 600), @"后台放宽到 10 分钟");
    XCTAssertFalse(IMChatCanShowRecall(m, NO, 1001, 0), @"非本人");
    m.recalledAt = 5;
    XCTAssertFalse(IMChatCanShowRecall(m, YES, 1001, 0), @"已撤回");
    m.recalledAt = 0; m.convSeq = 0;
    XCTAssertFalse(IMChatCanShowRecall(m, YES, 1001, 0), @"未拿到 conv_seq");
}

- (void)testEditVisibility {
    IMMessageModel *m = [self mineText:1000];
    int64_t aDayLater = 1000 + 24LL * 3600 * 1000;
    XCTAssertTrue(IMChatCanShowEdit(m, YES, aDayLater, 0), @"默认不限：保持现状");
    XCTAssertFalse(IMChatCanShowEdit(m, YES, aDayLater, 3600), @"超出编辑窗隐藏");
    XCTAssertTrue(IMChatCanShowEdit(m, YES, 1000 + 3600 * 1000, 3600));
    XCTAssertFalse(IMChatCanShowEdit(m, NO, 1001, 0), @"非本人");
    m.contentType = @"image";
    XCTAssertFalse(IMChatCanShowEdit(m, YES, 1001, 0), @"仅文本");
    m.contentType = @"text"; m.convSeq = 0;
    XCTAssertFalse(IMChatCanShowEdit(m, YES, 1001, 0), @"发送中的行不可编辑");
    m.convSeq = 7; m.recalledAt = 9;
    XCTAssertFalse(IMChatCanShowEdit(m, YES, 1001, 0), @"已撤回");
}

#pragma mark - 刷新合并

- (void)testShouldFetchCoalescesForegroundAndConnected {
    XCTAssertTrue([IMServerConfigStore shouldFetchWithInFlight:NO lastSuccessMs:0 nowMs:10000 minIntervalMs:5000], @"从没拉到过");
    XCTAssertFalse([IMServerConfigStore shouldFetchWithInFlight:YES lastSuccessMs:0 nowMs:10000 minIntervalMs:5000], @"在途不重发");
    XCTAssertFalse([IMServerConfigStore shouldFetchWithInFlight:NO lastSuccessMs:8000 nowMs:10000 minIntervalMs:5000], @"刚拉到");
    XCTAssertTrue([IMServerConfigStore shouldFetchWithInFlight:NO lastSuccessMs:4000 nowMs:10000 minIntervalMs:5000]);
    XCTAssertTrue([IMServerConfigStore shouldFetchWithInFlight:NO lastSuccessMs:20000 nowMs:10000 minIntervalMs:5000], @"时钟回拨不卡死");
}

#pragma mark - 群名限长

- (void)testGroupNameEditAllowed {
    XCTAssertTrue(IMGroupNameEditAllowed(@"", @"12345", 5));
    XCTAssertFalse(IMGroupNameEditAllowed(@"12345", @"123456", 5));
    XCTAssertTrue(IMGroupNameEditAllowed(@"1234567", @"123456", 5), @"上限调小后已超长的旧群名可往短里删");
    XCTAssertFalse(IMGroupNameEditAllowed(@"1234567", @"12345678", 5));
    XCTAssertTrue(IMGroupNameEditAllowed(@"", @"😀😀", 2), @"按 rune 计（emoji 算 1）");
}

- (void)testGroupNameShouldTruncate {
    XCTAssertFalse(IMGroupNameShouldTruncate(4, @"12345", 5, NO), @"未超限");
    XCTAssertTrue(IMGroupNameShouldTruncate(5, @"123456", 5, NO), @"变长且超限 → 截");
    XCTAssertFalse(IMGroupNameShouldTruncate(5, @"123456", 5, YES), @"拼音组合态不截");
    XCTAssertFalse(IMGroupNameShouldTruncate(8, @"1234567", 5, NO), @"已超长的旧群名往短里删不截");
    XCTAssertFalse(IMGroupNameShouldTruncate(7, @"1234567", 5, NO), @"长度没变（如替换选区）不截");
    XCTAssertTrue(IMGroupNameShouldTruncate(7, @"12345678", 5, NO), @"旧群名已超长又往长里加 → 截");
}

- (void)testGroupNameTruncateForEditingKeepsComposedCharacters {
    XCTAssertEqualObjects(IMGroupNameTruncateForEditing(@"一二三四五六", 5), @"一二三四五");
    // 👍🏽 = 2 个 rune（👍 + 肤色修饰），截在中间要整簇丢掉，不能留半个。
    XCTAssertEqualObjects(IMGroupNameTruncateForEditing(@"1234👍🏽", 5), @"1234");
    XCTAssertEqualObjects(IMGroupNameTruncateForEditing(@"123👍🏽", 5), @"123👍🏽");
    XCTAssertLessThanOrEqual(IMGroupNameRuneLength(IMGroupNameTruncateForEditing(@"🇨🇳🇨🇳🇨🇳", 3)), 3u);
}

- (void)testLegacyFieldsNullDoesNotCrash {
    IMServerConfigStore *s = [IMServerConfigStore new];
    NSDictionary *d = @{ @"max_group_members": NSNull.null, @"supergroup_enabled": NSNull.null,
                         @"max_supergroup_members": NSNull.null };
    XCTAssertNoThrow([s applyServerConfig:d]);
    XCTAssertEqual(s.maxGroupMembers, 0);
    XCTAssertFalse(s.supergroupEnabled);
    NSDictionary *d2 = @{ @"max_group_members": @2000, @"supergroup_enabled": @YES, @"max_supergroup_members": @20000 };
    [s applyServerConfig:d2];
    XCTAssertEqual(s.maxGroupMembers, 2000);
    XCTAssertTrue(s.supergroupEnabled);
    XCTAssertEqual(s.maxSupergroupMembers, 20000);
}

- (void)testGroupTextLimitedAfterEdit {
    XCTAssertNil(IMGroupTextLimitedAfterEdit(3, @"1234", 5, NO), @"未超限不动");
    XCTAssertEqualObjects(IMGroupTextLimitedAfterEdit(5, @"123456", 5, NO), @"12345", @"变长且超限 → 截到上限");
    XCTAssertNil(IMGroupTextLimitedAfterEdit(5, @"123456", 5, YES), @"拼音组合态不截");
    XCTAssertNil(IMGroupTextLimitedAfterEdit(9, @"12345678", 5, NO), @"调低上限前的旧公告往短里删不截");
    XCTAssertNil(IMGroupTextLimitedAfterEdit(2, @"😀😀😀", 3, NO), @"按码点计：3 个 emoji = 3（UTF-16 是 6）");
    XCTAssertEqualObjects(IMGroupTextLimitedAfterEdit(4, @"1234👍🏽", 5, NO), @"1234", @"截在完整字符边界");
}

@end
