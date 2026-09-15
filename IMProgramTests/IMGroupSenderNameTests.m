//  IMGroupSenderNameTests.m
//  群聊气泡发送者名字的取值口径（IMGroupSenderName.h）。与 im-web `src/chatNaming.test.ts`、
//  im-android `SenderNamesTest.kt` 钉的是同一条链：成员表 > 本窗该发送者最新快照 > 本条快照。

#import <XCTest/XCTest.h>
#import "IMGroupSenderName.h"
#import "IMMessageModel.h"

@interface IMGroupSenderNameTests : XCTestCase
@end

@implementation IMGroupSenderNameTests

static IMMessageModel *Msg(NSString *from, NSString *nick) {
    IMMessageModel *m = [IMMessageModel new];
    m.from = from;
    m.fromNickname = nick;
    return m;
}

/// 用户报的那一幕：A 改名后，老消息带的是旧快照、成员表已是新名 —— 老消息也要显示新名。
- (void)testMemberTableBeatsStaleSnapshot {
    XCTAssertEqualObjects(IMGroupSenderPublicName(@"新昵称", @"新昵称", @"旧昵称"), @"新昵称");
    XCTAssertEqualObjects(IMGroupSenderPublicName(@"新昵称", nil, @"旧昵称"), @"新昵称");
}

/// 超级群普通成员不在成员表里：取本窗里他最新一条的快照，而不是这条自己的旧快照。
- (void)testLatestSnapshotBeatsOwnSnapshotWhenNotInMemberTable {
    XCTAssertEqualObjects(IMGroupSenderPublicName(nil, @"新昵称", @"旧昵称"), @"新昵称");
    XCTAssertEqualObjects(IMGroupSenderPublicName(@"", nil, @"旧昵称"), @"旧昵称");
    XCTAssertNil(IMGroupSenderPublicName(@"", @"", nil));
}

- (void)testLatestSnapshotScansFromNewestAndSkipsOtherSendersAndEmpty {
    NSArray *msgs = @[ Msg(@"a", @"旧昵称"), Msg(@"b", @"别人"), Msg(@"a", @"新昵称"), Msg(@"a", nil), Msg(@"b", @"") ];
    XCTAssertEqualObjects(IMLatestSenderNickname(msgs, @"a"), @"新昵称");
    XCTAssertEqualObjects(IMLatestSenderNickname(msgs, @"b"), @"别人");
    XCTAssertNil(IMLatestSenderNickname(msgs, @"c"));
    XCTAssertNil(IMLatestSenderNickname(msgs, @""));
}

/// 会话开着时对方改名再发消息：成员表是进会话时拉的旧名，要判出来重拉；否则成员表优先会把新消息也显示成旧名。
- (void)testMemberNicknameStaleOnlyWhenBothPresentAndDiffer {
    XCTAssertTrue(IMGroupMemberNicknameStale(@"旧昵称", @"新昵称"));
    XCTAssertFalse(IMGroupMemberNicknameStale(@"新昵称", @"新昵称"));
    XCTAssertFalse(IMGroupMemberNicknameStale(nil, @"新昵称"));   // 超级群普通成员：重拉也拿不到
    XCTAssertFalse(IMGroupMemberNicknameStale(@"旧昵称", nil));   // 系统消息 / 老消息没带昵称
    XCTAssertFalse(IMGroupMemberNicknameStale(@"旧昵称", @""));
}

@end
