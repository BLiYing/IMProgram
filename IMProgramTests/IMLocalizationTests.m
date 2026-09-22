//  IMLocalizationTests.m
//  多语言：语言解析、偏好持久化与通知、取词回落、占位符/复数、时间与在线态的中英文口径。契约见 I18N_DESIGN。

#import <XCTest/XCTest.h>
#import "IMLocalization.h"
#import "IMTheme.h"
#import "IMPresence.h"
#import "IMCallRecord.h"
#import "IMMediaFormat.h"
#import "IMHTTPService.h"

@interface IMLocalizationTests : XCTestCase
@end

@implementation IMLocalizationTests

- (void)tearDown {
    [IMLocalization.shared setPreference:IMLanguagePrefZhHans]; // 还原 bootstrap 的默认，别影响其他用例
    [super tearDown];
}

- (IMLocalization *)isolatedWithSystem:(NSArray<NSString *> *)sys suite:(NSString *)suite {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [d removePersistentDomainForName:suite];
    return [[IMLocalization alloc] initWithDefaults:d bundle:NSBundle.mainBundle systemLanguages:^NSArray<NSString *> * { return sys; }];
}

#pragma mark - 解析

- (void)testResolveSystemPicksFirstSupported {
    XCTAssertEqualObjects([IMLocalization resolveLanguageForPreference:@"system" systemLanguages:(@[@"fr-FR", @"en-US"])], @"en");
    XCTAssertEqualObjects([IMLocalization resolveLanguageForPreference:@"system" systemLanguages:(@[@"zh-Hans-CN", @"en"])], @"zh-Hans");
    XCTAssertEqualObjects([IMLocalization resolveLanguageForPreference:@"system" systemLanguages:(@[@"zh-Hant-TW"])], @"zh-Hans", @"繁体暂归简体");
}

- (void)testResolveUnsupportedFallsBackToEnglishNotChinese {
    XCTAssertEqualObjects([IMLocalization resolveLanguageForPreference:@"system" systemLanguages:(@[@"fr", @"de"])], @"en");
    XCTAssertEqualObjects([IMLocalization resolveLanguageForPreference:@"system" systemLanguages:(@[])], @"en");
}

- (void)testExplicitPreferenceIgnoresSystem {
    XCTAssertEqualObjects([IMLocalization resolveLanguageForPreference:@"zh-Hans" systemLanguages:(@[@"en-US"])], @"zh-Hans");
    XCTAssertEqualObjects([IMLocalization resolveLanguageForPreference:@"en" systemLanguages:(@[@"zh-CN"])], @"en");
}

#pragma mark - 偏好

- (void)testPreferencePersistsAndNotifiesOnlyWhenChanged {
    IMLocalization *loc = [self isolatedWithSystem:@[@"zh-CN"] suite:@"im.test.loc1"];
    XCTAssertEqualObjects(loc.preference, @"system");
    __block int hits = 0;
    id tok = [NSNotificationCenter.defaultCenter addObserverForName:IMLanguageDidChangeNotification object:loc queue:nil
                                                         usingBlock:^(NSNotification *n) { hits++; }];
    [loc setPreference:@"en"];
    [loc setPreference:@"en"];   // 没变：不重复通知
    [loc setPreference:@"klingon"]; // 非法：忽略
    XCTAssertEqual(hits, 1);
    XCTAssertEqualObjects(loc.preference, @"en");
    XCTAssertEqualObjects(loc.language, @"en");
    // 换一个实例读同一个 defaults → 恢复（模拟重启）
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:@"im.test.loc1"];
    IMLocalization *again = [[IMLocalization alloc] initWithDefaults:d bundle:NSBundle.mainBundle
                                                     systemLanguages:^NSArray<NSString *> * { return @[@"zh-CN"]; }];
    XCTAssertEqualObjects(again.preference, @"en");
    [loc setPreference:@"system"];
    XCTAssertNil([d stringForKey:@"im.language"], @"选回跟随系统要清掉存储值，而不是存 @\"system\"");
    [NSNotificationCenter.defaultCenter removeObserver:tok];
}

#pragma mark - 取词

- (void)testStringsPerLanguageAndFallbackToKey {
    IMLocalization *loc = [self isolatedWithSystem:@[@"zh-CN"] suite:@"im.test.loc2"];
    XCTAssertEqualObjects([loc stringForKey:@"settings.language.title"], @"语言");
    [loc setPreference:@"en"];
    XCTAssertEqualObjects([loc stringForKey:@"settings.language.title"], @"Language");
    XCTAssertEqualObjects([loc stringForKey:@"no.such.key"], @"no.such.key", @"缺键返回键本身，不返回空串");
}

- (void)testFormattedPlaceholders {
    IMLocalization *loc = [self isolatedWithSystem:@[@"en-US"] suite:@"im.test.loc3"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"common.coming_soon", @"Recent calls"]), @"Recent calls (coming soon)");
    [loc setPreference:@"zh-Hans"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"common.coming_soon", @"最近通话"]), @"最近通话（开发中）");
}

- (void)testPluralViaStringsdict {
    IMLocalization *loc = [self isolatedWithSystem:@[@"en-US"] suite:@"im.test.loc4"];
    [loc setPreference:@"en"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"presence.minutes_ago", (long)1]), @"Last seen 1 minute ago");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"presence.minutes_ago", (long)5]), @"Last seen 5 minutes ago");
    [loc setPreference:@"zh-Hans"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"presence.minutes_ago", (long)5]), @"5 分钟前在线");
}

- (void)testCurrentPreferenceLabelUsesNativeNames {
    IMLocalization *loc = [self isolatedWithSystem:@[@"en-US"] suite:@"im.test.loc5"];
    XCTAssertEqualObjects(loc.currentPreferenceLabel, @"Follow system (English)");
    [loc setPreference:@"zh-Hans"];
    XCTAssertEqualObjects(loc.currentPreferenceLabel, @"简体中文");
    [loc setPreference:@"en"];
    XCTAssertEqualObjects(loc.currentPreferenceLabel, @"English", @"自称不随界面语言翻译");
}

#pragma mark - 时间 / 在线态（走全局 shared，tearDown 还原）

- (void)testDateLabelsFollowAppLanguage {
    NSDateComponents *c = [NSDateComponents new]; c.year = 2020; c.month = 9; c.day = 21; c.hour = 10;
    NSDate *old = [NSCalendar.currentCalendar dateFromComponents:c];
    int64_t ms = (int64_t)(old.timeIntervalSince1970 * 1000);
    XCTAssertEqualObjects([IMTheme conversationTimeStringFromMillis:ms], @"2020年9月21日");
    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    XCTAssertEqualObjects([IMTheme conversationTimeStringFromMillis:ms], @"Sep 21, 2020");
    XCTAssertEqualObjects([IMTheme dayHeaderStringFromMillis:ms], @"Sep 21, 2020");
}

- (void)testYesterdayAndTodayWords {
    int64_t yest = (int64_t)(([NSDate date].timeIntervalSince1970 - 86400) * 1000);
    int64_t now = (int64_t)([NSDate date].timeIntervalSince1970 * 1000);
    XCTAssertEqualObjects([IMTheme conversationTimeStringFromMillis:yest], @"昨天");
    XCTAssertEqualObjects([IMTheme dayHeaderStringFromMillis:now], @"今天");
    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    XCTAssertEqualObjects([IMTheme conversationTimeStringFromMillis:yest], @"Yesterday");
    XCTAssertEqualObjects([IMTheme dayHeaderStringFromMillis:now], @"Today");
}

- (void)testChineseBubbleTimeIsAlways24Hour {
    NSDateComponents *c = [NSDateComponents new]; c.year = 2020; c.month = 9; c.day = 21; c.hour = 14; c.minute = 5;
    int64_t ms = (int64_t)([NSCalendar.currentCalendar dateFromComponents:c].timeIntervalSince1970 * 1000);
    XCTAssertEqualObjects([IMTheme timeStringFromMillis:ms], @"14:05", @"UI_SPEC §5.3：中文恒 HH:mm");
}

#pragma mark - I1 批：格式化 / 复数 / 通话记录

- (void)testI1PluralAndFormatKeys {
    IMLocalization *loc = [self isolatedWithSystem:@[@"en-US"] suite:@"im.test.loc_i1"];
    [loc setPreference:@"en"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"media.picker.selected_count", (long)1]), @"1 item selected");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"media.picker.selected_count", (long)3]), @"3 items selected");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"common.sent_to_chats", (long)2]), @"Sent to 2 chats");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"search.user.row_title", @"abc"]), @"Search for user \u201cabc\u201d");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"preview.voice_duration", @"0:07"]), @"[Voice] 0:07");
    [loc setPreference:@"zh-Hans"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"media.picker.selected_count", (long)3]), @"已选 3 项");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"search.user.row_title", @"abc"]), @"搜索用户「abc」");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"preview.voice_duration", @"0:07"]), @"[语音] 0:07");
}

- (void)testCallRecordRenderFollowsLanguage {
    NSString *content = @"{\"cid\":\"c1\",\"m\":\"video\",\"r\":\"no_answer\",\"d\":0,\"g\":1}";
    IMCallRecordDisplay *zh = IMCallRecordRender(content, YES, YES, nil);
    XCTAssertEqualObjects(zh.text, @"你发起的群视频通话，无人接听");
    XCTAssertEqualObjects(zh.preview, @"[群视频通话] 无人接听");
    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    IMCallRecordDisplay *en = IMCallRecordRender(content, YES, YES, nil);
    XCTAssertEqualObjects(en.text, @"You started a group video call, no one answered");
    XCTAssertEqualObjects(en.preview, @"[Group video call] No answer");
    XCTAssertEqualObjects(IMCallRecordUnsupportedText, @"[Voice/video call] Update the app to view it");
    XCTAssertEqualObjects(IMFormatUploadProgress(0, 0), @"Waiting\u2026");
}

#pragma mark - I2 批：通讯录 / 群 / Models

- (void)testI2FormatAndPluralKeys {
    IMLocalization *loc = [self isolatedWithSystem:@[@"en-US"] suite:@"im.test.loc_i2"];
    [loc setPreference:@"en"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"device.active.minutes_ago", (long)1]), @"Active 1 minute ago");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"device.active.days_ago", (long)3]), @"Active 3 days ago");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"media.upload.compressing", (long)42]), @"Compressing 42%");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"group.info.invite_partial", (long)2, (long)3]),
                          @"Invited 2; the other 3 were already in the group");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"friend.picker.selected_of_max", (long)2, (long)9]), @"2/9 selected");
    [loc setPreference:@"zh-Hans"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"device.active.minutes_ago", (long)5]), @"5 分钟前活跃");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"media.upload.compressing", (long)42]), @"压缩中 42%");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"group.info.invite_partial", (long)2, (long)3]), @"已邀请 2 人，其余 3 人已在群里");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"friend.picker.selected_of_max", (long)2, (long)9]), @"已选 2/9 人");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"group.member.me_suffix", @"Bob"]), @"Bob（我）");
}

#pragma mark - I3 批：二维码 / 网络层

- (void)testI3QRFormatAndPluralKeys {
    IMLocalization *loc = [self isolatedWithSystem:@[@"en-US"] suite:@"im.test.loc_i3"];
    [loc setPreference:@"en"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"qr.preview.meta", (long)1]), @"1 member");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"qr.preview.meta", (long)5]), @"5 members");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"qr.preview.meta_invited", (long)3, @"Ann"]), @"3 members · Ann invited you");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"net.error.bad_response", @"502"]), @"Unexpected server response (HTTP 502)");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"qr.scan.label_url", @"a.com"]), @"Link · a.com");
    [loc setPreference:@"zh-Hans"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"qr.preview.meta", (long)5]), @"5 位成员");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"qr.preview.meta_invited", (long)3, @"Ann"]), @"3 位成员 · Ann 邀请你加入");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"net.error.bad_response", @"502"]), @"服务器响应异常 (HTTP 502)");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"qr.scan.label_url", @"a.com"]), @"网址 · a.com");
}

/// 业务错误码 → 提示：随 App 语言变；未收录码仍返回 nil（回退服务端原文的逻辑不能变）。
- (void)testI3FriendlyMessageForCodeFollowsLanguage {
    [IMLocalization.shared setPreference:IMLanguagePrefZhHans];
    XCTAssertEqualObjects(IMFriendlyMessageForCode(200002), @"密码错误");
    XCTAssertEqualObjects(IMFriendlyMessageForCode(100102), @"登录已失效，请重新登录");
    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    XCTAssertEqualObjects(IMFriendlyMessageForCode(200002), @"Wrong password");
    XCTAssertEqualObjects(IMFriendlyMessageForCode(100101), @"Your session has expired. Log in again.");
    XCTAssertEqualObjects(IMFriendlyMessageForCode(300208), @"You’ve been muted by an admin");
    XCTAssertNil(IMFriendlyMessageForCode(300204), @"未收录的码必须仍返回 nil，让调用方透传服务端原文");
}

#pragma mark - I4 批：我（收藏 / 外观 / 设备 / 密码）

- (void)testI4FavoritesPluralAndFormatKeys {
    IMLocalization *loc = [self isolatedWithSystem:@[@"en-US"] suite:@"im.test.loc_i4"];
    [loc setPreference:@"en"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"favorites.source.count", (long)1]), @"1 saved item");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"favorites.source.count", (long)3]), @"3 saved items");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"favorites.pick.max_selection", (long)1]), @"You can select up to 1 item");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"favorites.pick.max_selection", (long)9]), @"You can select up to 9 items");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"favorites.forward.success_count", (long)2]), @"Forwarded to 2 chats");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"favorites.source.title", @"张三"]), @"From 张三");
    [loc setPreference:@"zh-Hans"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"favorites.source.count", (long)3]), @"3 条收藏");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"favorites.pick.max_selection", (long)9]), @"最多选择 9 项");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"favorites.forward.success_count", (long)2]), @"已转发到 2 个会话");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"favorites.source.title", @"张三"]), @"来自 张三");
}

#pragma mark - I5 批：详情页 / 群管理 / 群管理员

- (void)testI5DetailFormatAndPluralKeys {
    IMLocalization *loc = [self isolatedWithSystem:@[@"en-US"] suite:@"im.test.loc_i5"];
    [loc setPreference:@"en"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"group.transfer_owner.done", @"Bob"]), @"Transferred to Bob");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.detail.remove_member_confirm_title", @"Ann"]), @"Remove \"Ann\"?");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.detail.group_call_pick_max", (long)8]), @"Up to 8 people");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"detail.file.a11y_downloaded", @"report.pdf"]), @"report.pdf, downloaded");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"group.admin_list.revoke_confirm_message", @"Cara"]), @"Revoke admin status from Cara?");
    [loc setPreference:@"zh-Hans"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"group.transfer_owner.done", @"Bob"]), @"已转让给 Bob");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.detail.remove_member_confirm_title", @"Ann"]), @"移出「Ann」？");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.detail.group_call_pick_max", (long)8]), @"最多呼叫 8 人");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"detail.file.a11y_downloaded", @"report.pdf"]), @"report.pdf，已下载");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"group.admin_list.revoke_confirm_message", @"Cara"]), @"撤销 Cara 的管理员身份？");
}

#pragma mark - I6 批：聊天页（多选 / 转发 / 引用 / 举报）

- (void)testI6ChatFormatAndPluralKeys {
    IMLocalization *loc = [self isolatedWithSystem:@[@"en-US"] suite:@"im.test.loc_i6"];
    [loc setPreference:@"en"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.selection.selected_count", (long)1]), @"Selected 1");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.selection.selected_count", (long)5]), @"Selected 5");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.reply.header", @"Ann"]), @"Reply to Ann");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.forward.expired_suffix", (long)1]), @"(1 item expired, not forwarded)");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.forward.expired_suffix", (long)3]), @"(3 items expired, not forwarded)");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.report.multi_title", @"Ann", (long)2]), @"Report 2 messages from Ann");
    [loc setPreference:@"zh-Hans"];
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.selection.selected_count", (long)5]), @"已选择 5 条");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.reply.header", @"小明"]), @"回复 小明");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.forward.expired_suffix", (long)3]), @"（3 条已失效未转发）");
    XCTAssertEqualObjects(([loc formattedStringForKey:@"chat.report.multi_title", @"小明", (long)2]), @"举报 小明 的 2 条消息");
}
@end
