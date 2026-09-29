//  IMInAppBannerContentTests.m
//  IMInAppBannerContentBuild 纯函数单测（Common/IMInAppBannerContent.h）：应用内横幅标题/正文拼装
//  （NOTIFICATIONS_P1_DESIGN §1.2）。覆盖私聊 / 群聊 / 预览关 / 系统通知会话四类。

#import <XCTest/XCTest.h>
#import "../IMProgram/Common/IMInAppBannerContent.h"
#import "../IMProgram/Common/IMAccountIdentity.h"
#import "../IMProgram/Common/IMLocalization.h"

@interface IMInAppBannerContentTests : XCTestCase
@end

@implementation IMInAppBannerContentTests

- (void)testPrivateChatBodyIsPlainSummaryNoSenderPrefix {
    IMInAppBannerContent *c = IMInAppBannerContentBuild(@"张三", NO, @"http://x/a.png", @"u_zhang",
        YES, @"text", nil, @"在吗", 0, nil);
    XCTAssertEqualObjects(c.title, @"张三");
    XCTAssertEqualObjects(c.body, @"在吗"); // 私聊不带「发送者：」前缀
    XCTAssertEqualObjects(c.avatarURL, @"http://x/a.png");
    XCTAssertEqualObjects(c.avatarSeed, @"u_zhang");
    XCTAssertEqualObjects(c.avatarDisplayName, @"张三");
}

- (void)testGroupChatBodyHasSenderPrefix {
    IMInAppBannerContent *c = IMInAppBannerContentBuild(@"产品讨论组", YES, nil, @"g_1",
        YES, @"text", nil, @"明天评审前发原型", 0, @"李四");
    XCTAssertEqualObjects(c.title, @"产品讨论组");
    XCTAssertEqualObjects(c.body, @"李四: 明天评审前发原型");
}

- (void)testGroupChatMediaPreviewAlsoGetsSenderPrefix {
    IMInAppBannerContent *c = IMInAppBannerContentBuild(@"产品讨论组", YES, nil, @"g_1",
        YES, @"image", nil, nil, 0, @"李四");
    NSString *expected = [@"李四: " stringByAppendingString:IMLocalized(@"preview.image")];
    XCTAssertEqualObjects(c.body, expected);
}

- (void)testPreviewDisabledAlwaysShowsHiddenPlaceholderRegardlessOfContent {
    IMInAppBannerContent *privateC = IMInAppBannerContentBuild(@"王五", NO, nil, @"u_wang",
        NO /* previewEnabled */, @"text", nil, @"机密内容", 0, nil);
    XCTAssertEqualObjects(privateC.body, IMLocalized(@"notif.preview.hidden"));

    IMInAppBannerContent *groupC = IMInAppBannerContentBuild(@"周末羽毛球", YES, nil, @"g_2",
        NO, @"text", nil, @"机密内容", 0, @"周三");
    XCTAssertEqualObjects(groupC.body, IMLocalized(@"notif.preview.hidden")); // 群聊同样不带发送者前缀
}

- (void)testEmptyContentFallsBackToNoMessagePlaceholder {
    IMInAppBannerContent *c = IMInAppBannerContentBuild(@"张三", NO, nil, @"u_zhang",
        YES, @"text", nil, @"", 0, nil);
    XCTAssertEqualObjects(c.body, IMLocalized(@"conv.list.no_message"));
}

- (void)testSystemNoticeConversationPassesSystemSeedThroughForAvatarComponentToRenderAppIcon {
    // 头像仍走会话列表同款组件渲染（UILabel+IMAvatar 内部按 IMIsSystemUserID(seed) 出应用图标）；
    // 本函数只负责把 seed 原样透传，不在这里重新判定一次。
    IMInAppBannerContent *c = IMInAppBannerContentBuild(@"系统通知", NO, nil, IMSystemUserID,
        YES, @"text", nil, @"你的账号在新设备登录", 0, nil);
    XCTAssertEqualObjects(c.avatarSeed, IMSystemUserID);
    XCTAssertTrue(IMIsSystemUserID(c.avatarSeed));
    XCTAssertEqualObjects(c.body, @"你的账号在新设备登录");
}

@end
