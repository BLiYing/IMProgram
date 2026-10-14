//  IMChatFolderLogicTests.m
//  聊天文件夹纯逻辑（Tab 角标口径 / 尾部区域 / 横滑判定）：读三端共用向量
//  IMServer/docs/conformance/chat_folder_logic.json（改口径先改向量；找不到时失败而不是跳过）。

#import <XCTest/XCTest.h>

#import "../IMProgram/Common/IMChatFolderLogic.h"
#import "../IMProgram/Models/IMChatFolder.h"
#import "../IMProgram/Models/IMConversation.h"

@interface IMChatFolderLogicTests : XCTestCase
@end

@implementation IMChatFolderLogicTests

- (NSDictionary *)vectors {
    NSString *path = NSProcessInfo.processInfo.environment[@"IM_CHAT_FOLDER_VECTORS"];
    if (path.length == 0) {
        NSString *repo = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        path = [[repo stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"IMServer/docs/conformance/chat_folder_logic.json"];
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"找不到共用向量 %@（IM_CHAT_FOLDER_VECTORS 可指定）", path);
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : @{};
}

- (void)testTailZone {
    NSArray *cases = [self vectors][@"tail_zone"];
    XCTAssertGreaterThan(cases.count, 0u);
    for (NSDictionary *c in cases) {
        CGFloat got = [IMChatFolderLogic tailZoneWidthForListWidth:[c[@"list_width"] doubleValue]
                                                      actionsWidth:[c[@"actions_width"] doubleValue]];
        XCTAssertEqualWithAccuracy(got, [c[@"expect"] doubleValue], 0.001, @"%@", c[@"name"]);
    }
}

- (void)testSwipeOutcomes {
    NSArray *cases = [self vectors][@"swipe"];
    XCTAssertGreaterThan(cases.count, 0u);
    NSDictionary *names = @{ @"none": @(IMChatFolderSwipeOutcomeNone), @"next": @(IMChatFolderSwipeOutcomeNextTab),
                             @"prev": @(IMChatFolderSwipeOutcomePrevTab), @"row": @(IMChatFolderSwipeOutcomeRowSwipe) };
    for (NSDictionary *c in cases) {
        IMChatFolderSwipeOutcome got = [IMChatFolderLogic
            swipeOutcomeForTranslationX:[c[@"tx"] doubleValue] startX:[c[@"start_x"] doubleValue]
                              listWidth:[c[@"list_width"] doubleValue] actionsWidth:[c[@"actions_width"] doubleValue]
                                hasNext:[c[@"has_next"] boolValue] hasPrev:[c[@"has_prev"] boolValue]
                                rowOpen:[c[@"row_open"] boolValue]];
        XCTAssertEqual(got, [names[c[@"expect"]] integerValue], @"%@", c[@"name"]);
    }
}

- (void)testBadgeVectors {
    NSArray *cases = [self vectors][@"badge"];
    XCTAssertGreaterThan(cases.count, 0u);
    for (NSDictionary *c in cases) {
        NSMutableArray<IMConversation *> *convs = [NSMutableArray array];
        for (NSDictionary *d in c[@"convs"]) {
            IMConversation *conv = [IMConversation new];
            conv.convID = d[@"conv_id"];
            conv.unread = [d[@"unread"] integerValue];
            conv.muted = [d[@"muted"] boolValue];
            conv.muteUntil = [d[@"mute_until"] longLongValue];
            conv.markedUnread = [d[@"marked_unread"] boolValue];
            conv.mentionUnread = [d[@"mention_unread"] boolValue];
            [convs addObject:conv];
        }
        IMChatFolder *folder = nil;
        if ([c[@"folder"] isKindOfClass:NSArray.class]) {
            folder = [[IMChatFolder alloc] initWithID:@"f" name:@"x" position:0 convIDs:c[@"folder"]];
        }
        IMChatFolderBadge b = [IMChatFolderLogic badgeForConversations:convs inFolder:folder nowMillis:[c[@"now"] longLongValue]];
        XCTAssertEqual(b.count, [c[@"expect"][@"count"] integerValue], @"%@ count", c[@"name"]);
        XCTAssertEqual(b.muted, [c[@"expect"][@"muted"] boolValue], @"%@ muted", c[@"name"]);
    }
}

- (void)testFilterKeepsOrderAndAllReturnsSame {
    IMConversation *a = [IMConversation new]; a.convID = @"a";
    IMConversation *b = [IMConversation new]; b.convID = @"b";
    IMConversation *c = [IMConversation new]; c.convID = @"c";
    NSArray *all = @[a, b, c];
    IMChatFolder *f = [[IMChatFolder alloc] initWithID:@"f" name:@"x" position:0 convIDs:@[@"c", @"a"]];
    XCTAssertEqualObjects([IMChatFolderLogic conversations:all inFolder:f], (@[a, c])); // 保持会话列表顺序，而非文件夹加入顺序
    XCTAssertTrue([IMChatFolderLogic conversations:all inFolder:nil] == all);          // 「全部」原样返回同一对象
}

- (void)testIndexOfFolderID {
    IMChatFolder *f1 = [[IMChatFolder alloc] initWithID:@"f1" name:@"a" position:0 convIDs:@[]];
    IMChatFolder *f2 = [[IMChatFolder alloc] initWithID:@"f2" name:@"b" position:1 convIDs:@[]];
    NSArray *fs = @[f1, f2];
    XCTAssertEqual([IMChatFolderLogic indexOfFolderID:nil inFolders:fs], -1);
    XCTAssertEqual([IMChatFolderLogic indexOfFolderID:@"f2" inFolders:fs], 1);
    XCTAssertEqual([IMChatFolderLogic indexOfFolderID:@"gone" inFolders:fs], -1); // 被删 → 回「全部」
}

@end
