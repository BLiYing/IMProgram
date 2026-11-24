//  IMUserSearchViewControllerTests.m
//  「添加朋友」搜索结果里已是好友的人点「发消息」（BACKLOG B1）：聊天页要拿到对方昵称与头像，
//  标题不能退化成 10 位内部 ID。app-hosted 测试，头文件按相对路径引入。

#import <XCTest/XCTest.h>

#import "../IMProgram/Modules/Contacts/IMUserSearchViewController.h"
#import "../IMProgram/Modules/Chat/IMChatViewController.h"
#import "../IMProgram/Modules/Chat/IMChatViewController+Private.h"
#import "../IMProgram/Models/IMUserCard.h"

/// 被测私有成员（类扩展里合成的属性 + .m 内私有方法），测试内声明即可调用。
@interface IMUserSearchViewController (Testing)
- (void)openChatWithCard:(IMUserCard *)card;
@end

@interface IMUserSearchViewControllerTests : XCTestCase
@end

@implementation IMUserSearchViewControllerTests

- (IMUserCard *)friendCard {
    return [IMUserCard cardsFromArray:@[ @{ @"user_id": @"8800000001", @"username": @"bobblue", @"nickname": @"BobBlue",
                                            @"avatar_url": @"/avatars/abc.jpg" } ]].firstObject;
}

- (void)testSendMessageCarriesNicknameAndAvatarIntoChat {
    IMUserSearchViewController *search = [[IMUserSearchViewController alloc] initWithHost:@"http://127.0.0.1:8080"
                                                                                  userID:@"8800000000"];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:search];

    [search openChatWithCard:[self friendCard]];

    IMChatViewController *chat = (IMChatViewController *)nav.viewControllers.lastObject;
    XCTAssertTrue([chat isKindOfClass:IMChatViewController.class], @"点「发消息」应进入聊天页");
    XCTAssertEqualObjects(chat.peerNickname, @"BobBlue", @"没带昵称时聊天页标题退化成内部 ID");
    XCTAssertEqualObjects(chat.peerAvatarURL, @"/avatars/abc.jpg");
    XCTAssertEqualObjects([chat peerDisplayName], @"BobBlue");
}

- (void)testSendMessageToSelfIsIgnored {
    IMUserSearchViewController *search = [[IMUserSearchViewController alloc] initWithHost:@"http://127.0.0.1:8080"
                                                                                  userID:@"8800000001"];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:search];

    [search openChatWithCard:[self friendCard]];

    XCTAssertEqual(nav.viewControllers.count, 1u, @"自己不能和自己开会话");
}

@end
