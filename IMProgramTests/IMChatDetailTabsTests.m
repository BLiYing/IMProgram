//  IMChatDetailTabsTests.m
//  会话详情页分类页签推导单测：动态按消息类型生成、群成员恒首位、Telegram 式过滤
//  （文本/系统/合并转发/撤回/空内容不成签；文本形如 URL 归「链接」）。
//  app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Detail/IMChatDetailTabs.h"
#import "../IMProgram/Models/IMMessageModel.h"

@interface IMChatDetailTabsTests : XCTestCase
@end

@implementation IMChatDetailTabsTests

/// 造一条消息（默认非撤回、有内容）。
static IMMessageModel *msg(NSString *type, NSString *content) {
    IMMessageModel *m = [IMMessageModel new];
    m.contentType = type;
    m.content = content;
    return m;
}

- (NSArray<NSNumber *> *)kindsOf:(NSArray<IMChatDetailTab *> *)tabs {
    NSMutableArray *k = [NSMutableArray array];
    for (IMChatDetailTab *t in tabs) { [k addObject:@(t.kind)]; }
    return k;
}

#pragma mark - 群聊：成员恒第一

- (void)testGroupAlwaysHasMembersFirstEvenEmpty {
    NSArray *tabs = [IMChatDetailTabs tabsForMessages:@[] isGroup:YES];
    XCTAssertEqual(tabs.count, 1u);
    XCTAssertEqual(((IMChatDetailTab *)tabs.firstObject).kind, IMDetailTabKindMembers);
    XCTAssertEqualObjects(((IMChatDetailTab *)tabs.firstObject).title, @"成员");
}

- (void)testGroupMembersStaysFirstBeforeMedia {
    NSArray *msgs = @[ msg(@"image", @"/u/a.jpg"), msg(@"text", @"hi") ];
    NSArray *tabs = [IMChatDetailTabs tabsForMessages:msgs isGroup:YES];
    NSArray *kinds = [self kindsOf:tabs];
    XCTAssertEqualObjects(kinds, (@[ @(IMDetailTabKindMembers), @(IMDetailTabKindMedia) ]));
}

#pragma mark - 单聊：无成员签，按类型动态

- (void)testSingleNoMembersTab {
    NSArray *tabs = [IMChatDetailTabs tabsForMessages:@[ msg(@"file", @"/u/x.pdf") ] isGroup:NO];
    NSArray *kinds = [self kindsOf:tabs];
    XCTAssertEqualObjects(kinds, (@[ @(IMDetailTabKindFiles) ]));
}

- (void)testSinglePureTextYieldsNoTabs {
    // 纯文本（非链接）不成任何签 → 单聊返回空（调用方隐藏页签区）。
    NSArray *tabs = [IMChatDetailTabs tabsForMessages:@[ msg(@"text", @"你好"), msg(@"text", @"在吗") ] isGroup:NO];
    XCTAssertEqual(tabs.count, 0u);
}

#pragma mark - 类别顺序固定：媒体→文件→语音→链接

- (void)testFixedOrderRegardlessOfMessageOrder {
    // 消息乱序到达，页签顺序仍固定。
    NSArray *msgs = @[ msg(@"audio", @"/u/v.m4a"), msg(@"file", @"/u/x.zip"),
                       msg(@"video", @"/u/m.mp4"), msg(@"text", @"https://a.com") ];
    NSArray *tabs = [IMChatDetailTabs tabsForMessages:msgs isGroup:NO];
    NSArray *kinds = [self kindsOf:tabs];
    XCTAssertEqualObjects(kinds, (@[ @(IMDetailTabKindMedia), @(IMDetailTabKindFiles),
                                     @(IMDetailTabKindVoice), @(IMDetailTabKindLinks) ]));
}

- (void)testImageAndVideoBothCountAsMediaOnce {
    NSArray *msgs = @[ msg(@"image", @"/u/a.jpg"), msg(@"video", @"/u/b.mp4") ];
    NSArray *tabs = [IMChatDetailTabs tabsForMessages:msgs isGroup:NO];
    XCTAssertEqualObjects([self kindsOf:tabs], (@[ @(IMDetailTabKindMedia) ]), @"媒体只出现一次");
}

#pragma mark - 链接：文本形如 URL 归链接，普通文本不归

- (void)testTextURLCountsAsLink {
    NSArray *tabs = [IMChatDetailTabs tabsForMessages:@[ msg(@"text", @"http://t.me/foo") ] isGroup:NO];
    XCTAssertEqualObjects([self kindsOf:tabs], (@[ @(IMDetailTabKindLinks) ]));
}

- (void)testLinkTypeCountsAsLink {
    NSArray *tabs = [IMChatDetailTabs tabsForMessages:@[ msg(@"link", @"https://x.com") ] isGroup:NO];
    XCTAssertEqualObjects([self kindsOf:tabs], (@[ @(IMDetailTabKindLinks) ]));
}

#pragma mark - Telegram 式过滤：系统/合并转发/撤回/空内容不计

- (void)testSystemAndChatRecordExcluded {
    NSArray *msgs = @[ msg(@"system", @"xx 加入群聊"), msg(@"chat_record", @"{...}") ];
    NSArray *tabs = [IMChatDetailTabs tabsForMessages:msgs isGroup:NO];
    XCTAssertEqual(tabs.count, 0u);
}

- (void)testRecalledMediaExcluded {
    IMMessageModel *m = msg(@"image", @"/u/a.jpg");
    m.recalledAt = 123;
    NSArray *tabs = [IMChatDetailTabs tabsForMessages:@[ m ] isGroup:NO];
    XCTAssertEqual(tabs.count, 0u, @"撤回的图片不进媒体签");
    XCTAssertFalse([IMChatDetailTabs message:m matchesKind:IMDetailTabKindMedia]);
}

- (void)testEmptyContentExcluded {
    NSArray *tabs = [IMChatDetailTabs tabsForMessages:@[ msg(@"file", @"") ] isGroup:NO];
    XCTAssertEqual(tabs.count, 0u);
}

- (void)testMatchesKindMembersAlwaysNo {
    XCTAssertFalse([IMChatDetailTabs message:msg(@"image", @"/a.jpg") matchesKind:IMDetailTabKindMembers]);
}

@end
