//  IMSysEventFormatterTests.m
//  P3 i18n：sys_event/sys_args → 群系统消息分段渲染、系统通知单聊文本；reply_snapshot_kind → 引用快照渲染。
//  中英文两版输出都断言；sysEvent/replySnapshotKind 为空时的回退路径也钉住（不能因新逻辑破坏老消息展示）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMSysEventFormatter.h"
#import "../IMProgram/Common/IMMediaUtil.h"
#import "../IMProgram/Common/IMLocalization.h"
#import "../IMProgram/Models/IMMessageModel.h"

@interface IMSysEventFormatterTests : XCTestCase
@end

@implementation IMSysEventFormatterTests

- (void)tearDown {
    [IMLocalization.shared setPreference:IMLanguagePrefZhHans]; // 还原 bootstrap 默认，别影响其他用例
    [super tearDown];
}

- (IMSysSegment *)segWithUID:(NSString *)uid text:(NSString *)text {
    IMSysSegment *s = [IMSysSegment new];
    s.uid = uid;
    s.text = text;
    return s;
}

/// 测试不关心备注/群昵称解析，直接回传服务端字面（fallback），与真实 displayNameForUID 签名一致。
- (NSString *(^)(NSString *, NSString *))identityResolver {
    return ^NSString *(NSString *uid, NSString *fallback) { return fallback; };
}

- (NSString *)joinedText:(NSArray<IMSysSegment *> *)segments {
    NSMutableString *out = [NSMutableString string];
    for (IMSysSegment *s in segments) { [out appendString:s.text ?: @""]; }
    return out;
}

#pragma mark - member_remove：两个人名槽位（actor/target 均可点）

- (void)testMemberRemoveTwoNameSlots {
    NSArray<IMSysSegment *> *segs = @[[self segWithUID:@"u1" text:@"张三"], [self segWithUID:@"u2" text:@"李四"]];
    NSArray<IMSysSegment *> *out = IMSegmentsForSysEvent(@"member_remove", nil, segs, [self identityResolver]);
    XCTAssertEqualObjects([self joinedText:out], @"张三 将 李四 移出群聊");
    NSArray<NSString *> *uids = [out valueForKeyPath:@"uid"];
    // 过滤掉固定文案段（uid 为 nil，valueForKeyPath 会收进 NSNull）
    NSMutableArray<NSString *> *nonNilUIDs = [NSMutableArray array];
    for (id u in uids) { if ([u isKindOfClass:NSString.class] && [(NSString *)u length] > 0) { [nonNilUIDs addObject:u]; } }
    XCTAssertEqualObjects(nonNilUIDs, (@[@"u1", @"u2"]), @"人名槽位顺序=actor,target，且保留 uid 供点击");

    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    NSArray<IMSysSegment *> *outEn = IMSegmentsForSysEvent(@"member_remove", nil, segs, [self identityResolver]);
    XCTAssertEqualObjects([self joinedText:outEn], @"张三 removed 李四 from the group");
}

#pragma mark - group_rename：纯 args 无人名槽位

- (void)testGroupRenameNoNameSlots {
    NSArray<IMSysSegment *> *out = IMSegmentsForSysEvent(@"group_rename", @{ @"name": @"摸鱼小组" }, nil, nil);
    XCTAssertEqual(out.count, 1u);
    XCTAssertNil(out[0].uid);
    XCTAssertEqualObjects(out[0].text, @"群名已改为「摸鱼小组」");

    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    NSArray<IMSysSegment *> *outEn = IMSegmentsForSysEvent(@"group_rename", @{ @"name": @"摸鱼小组" }, nil, nil);
    XCTAssertEqualObjects(outEn[0].text, @"Group name changed to \"摸鱼小组\"");
}

#pragma mark - mute_all_on：无参数纯静态串

- (void)testMuteAllOnStaticNoParams {
    NSArray<IMSysSegment *> *out = IMSegmentsForSysEvent(@"mute_all_on", nil, nil, nil);
    XCTAssertEqual(out.count, 1u);
    XCTAssertEqualObjects(out[0].text, @"管理员开启了全员禁言");

    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    NSArray<IMSysSegment *> *outEn = IMSegmentsForSysEvent(@"mute_all_on", nil, nil, nil);
    XCTAssertEqualObjects(outEn[0].text, @"An admin turned on mute-all");
}

#pragma mark - member_invite：多人名拼接（§1.3，仅 actor 可点）

- (void)testMemberInviteJoinsInviteeNames {
    NSArray<IMSysSegment *> *segs = @[[self segWithUID:@"u1" text:@"张三"],
                                       [self segWithUID:@"u2" text:@"李四"],
                                       [self segWithUID:@"u3" text:@"王五"]];
    NSArray<IMSysSegment *> *out = IMSegmentsForSysEvent(@"member_invite", nil, segs, [self identityResolver]);
    XCTAssertEqualObjects([self joinedText:out], @"张三 邀请 李四、王五 加入群聊");
    NSMutableArray<NSString *> *clickableUIDs = [NSMutableArray array];
    for (IMSysSegment *s in out) { if (s.uid.length > 0) { [clickableUIDs addObject:s.uid]; } }
    XCTAssertEqualObjects(clickableUIDs, (@[@"u1"]), @"只有 actor 可点，被邀请者拼进纯文本（刻意取舍）");

    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    NSArray<IMSysSegment *> *outEn = IMSegmentsForSysEvent(@"member_invite", nil, segs, [self identityResolver]);
    XCTAssertEqualObjects([self joinedText:outEn], @"张三 invited 李四, 王五 to the group");
}

#pragma mark - 回退路径钉住：事件为空/未识别/数据不齐 → 必须返回 nil，交由调用方回退老消息展示

- (void)testUnrecognizedOrIncompleteEventFallsBackToNil {
    XCTAssertNil(IMSegmentsForSysEvent(nil, nil, nil, nil));
    XCTAssertNil(IMSegmentsForSysEvent(@"", nil, nil, nil));
    XCTAssertNil(IMSegmentsForSysEvent(@"some_future_event_not_yet_known", nil, nil, nil), @"未识别事件（未来新增）必须回退，不能崩溃/乱渲染");
    NSArray<IMSysSegment *> *onlyOneUID = @[[self segWithUID:@"u1" text:@"张三"]];
    XCTAssertNil(IMSegmentsForSysEvent(@"member_remove", nil, onlyOneUID, [self identityResolver]), @"member_remove 需要 2 个人名槽位，候选不够时防御性回退");
}

#pragma mark - 系统通知单聊（§1.4）：new_device_login 正常态

- (void)testNoticeNewDeviceLoginNormal {
    NSDictionary *args = @{ @"at": @"2026-09-22T10:00:00Z", @"device": @"iPhone 15", @"platform": @"iOS 18" };
    NSString *text = IMTextForNoticeSysEvent(@"new_device_login", args);
    XCTAssertNotNil(text);
    XCTAssertTrue([text containsString:@"iPhone 15"]);
    XCTAssertTrue([text containsString:@"iOS 18"]);
    XCTAssertTrue([text hasSuffix:IMLocalized(@"sys.notice.new_device.footer")]);

    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    NSString *textEn = IMTextForNoticeSysEvent(@"new_device_login", args);
    XCTAssertTrue([textEn hasPrefix:@"Your account signed in at"]);
    XCTAssertTrue([textEn containsString:@"iPhone 15"]);
}

- (void)testNoticeUnrecognizedOrEmptyEventReturnsNil {
    XCTAssertNil(IMTextForNoticeSysEvent(nil, nil));
    XCTAssertNil(IMTextForNoticeSysEvent(@"", nil));
    XCTAssertNil(IMTextForNoticeSysEvent(@"unknown_notice_event", nil));
}

#pragma mark - reply_snapshot_kind：chat_record 带标题

- (void)testReplySnapshotKindChatRecordTitled {
    IMMessageModel *m = [IMMessageModel new];
    m.replyToConvSeq = 5;
    m.replySnapshotKind = @"chat_record";
    m.replySnapshotArgs = @{ @"title": @"周末聚会安排" };
    NSString *text = nil; NSString *glyph = nil; BOOL isFile = NO; NSString *fileName = nil;
    IMRenderReplySnapshot(m, &text, &glyph, &isFile, &fileName);
    XCTAssertEqualObjects(text, @"[聊天记录] 周末聚会安排");
    XCTAssertEqualObjects(glyph, @"text.bubble.fill");
    XCTAssertFalse(isFile);
    XCTAssertNil(fileName);

    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    NSString *textEn = nil;
    IMRenderReplySnapshot(m, &textEn, NULL, NULL, NULL);
    XCTAssertEqualObjects(textEn, @"[Chat History] 周末聚会安排");
}

#pragma mark - reply_snapshot_kind 为空：回退旧 wire-token 路径（红绿钉住：老消息不受影响）

- (void)testEmptyReplySnapshotKindFallsBackToLegacyWireToken {
    IMMessageModel *m = [IMMessageModel new];
    m.replyToConvSeq = 5;
    m.replySnapshot = @"[image]"; // 老消息：服务端未下发 kind
    NSString *text = nil; NSString *glyph = nil; BOOL isFile = NO;
    IMRenderReplySnapshot(m, &text, &glyph, &isFile, NULL);
    XCTAssertEqualObjects(text, @"[图片]");
    XCTAssertEqualObjects(glyph, @"photo.fill");
    XCTAssertFalse(isFile);

    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    NSString *textEn = nil;
    IMRenderReplySnapshot(m, &textEn, NULL, NULL, NULL);
    XCTAssertEqualObjects(textEn, @"[Photo]", @"旧 wire-token 路径也要跟随语言（本批顺手修的硬编码中文 bug）");
}

- (void)testNonReplyMessageReturnsEmptyText {
    IMMessageModel *m = [IMMessageModel new];
    m.replyToConvSeq = 0;
    NSString *text = nil; NSString *glyph = @"placeholder"; BOOL isFile = YES;
    IMRenderReplySnapshot(m, &text, &glyph, &isFile, NULL);
    XCTAssertEqualObjects(text, @"");
    XCTAssertNil(glyph);
    XCTAssertFalse(isFile);
}

@end
