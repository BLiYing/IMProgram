//  IMPushSenderTests.m
//  通知扩展用的纯函数（PUSH_M5_DESIGN §3.6）：载荷里的发送人资料怎么解、头像地址怎么补全。

#import <XCTest/XCTest.h>
#import "IMPushSender.h"

@interface IMPushSenderTests : XCTestCase
@end

@implementation IMPushSenderTests

- (void)testAvatarURLJoinsServerAndRelativePath {
    NSURL *url = IMPushAvatarURL(@"/avatars/abc.jpg", @"http", @"192.168.1.12:8080");
    XCTAssertEqualObjects(url.absoluteString, @"http://192.168.1.12:8080/avatars/abc.jpg");
    XCTAssertEqualObjects(IMPushAvatarURL(@"/avatars/abc.jpg", @"https", @"im.example.com").absoluteString,
                          @"https://im.example.com/avatars/abc.jpg");
}

/// 只从自家服务器的头像目录取：推送里塞一个外站地址 / 别的目录，扩展不该去拉。
- (void)testAvatarURLRejectsAnythingButOwnAvatarDirectory {
    XCTAssertNil(IMPushAvatarURL(@"https://evil.example/a.jpg", @"http", @"192.168.1.12:8080"));
    XCTAssertNil(IMPushAvatarURL(@"/uploads/a.jpg", @"http", @"192.168.1.12:8080"));
    XCTAssertNil(IMPushAvatarURL(@"/avatars/../uploads/a.jpg", @"http", @"192.168.1.12:8080"));
    XCTAssertNil(IMPushAvatarURL(@"/avatars/a.jpg", @"ftp", @"192.168.1.12:8080"));
    XCTAssertNil(IMPushAvatarURL(@"/avatars/a.jpg", @"http", @""));
    XCTAssertNil(IMPushAvatarURL(@"/avatars/a.jpg", @"http", @"evil.example@192.168.1.12"));
    XCTAssertNil(IMPushAvatarURL(nil, @"http", @"192.168.1.12:8080"));
}

- (void)testPrivateSenderFromPayload {
    IMPushSender *s = [IMPushSender senderFromUserInfo:@{
        @"conv_id": @"u_1001_u_1002", @"conv_seq": @3, @"sender_id": @"1002",
        @"sender_name": @"老王", @"sender_avatar": @"/avatars/abc.jpg", @"bare_body": @"不该用" }];
    XCTAssertNotNil(s);
    XCTAssertFalse(s.isGroup);
    XCTAssertEqualObjects(s.senderID, @"1002");
    XCTAssertEqualObjects(s.senderName, @"老王");
    XCTAssertEqualObjects(s.avatarPath, @"/avatars/abc.jpg");
    XCTAssertNil(s.bareBody, @"私聊正文本来就不带发送人前缀");
}

- (void)testGroupSenderFromPayload {
    IMPushSender *s = [IMPushSender senderFromUserInfo:@{
        @"conv_id": @"g_9", @"sender_id": @"1002", @"sender_name": @"小明",
        @"group_avatar": @"/avatars/grp.jpg", @"bare_body": @"开会了" }];
    XCTAssertTrue(s.isGroup);
    XCTAssertEqualObjects(s.groupAvatarPath, @"/avatars/grp.jpg");
    XCTAssertEqualObjects(s.bareBody, @"开会了");
    XCTAssertNil(s.avatarPath);
}

/// 已读清通知、老服务端的推送没有发送人：扩展原样展示。
- (void)testPayloadWithoutSenderIsNil {
    NSArray<NSDictionary *> *payloads = @[
        @{ @"conv_id": @"u_1_u_2", @"clear_up_to": @5 },
        @{ @"sender_id": @"1002" },
        @{ @"conv_id": @"u_1_u_2", @"sender_id": @1002 },
    ];
    for (NSDictionary *payload in payloads) {
        XCTAssertNil([IMPushSender senderFromUserInfo:payload], @"%@", payload);
    }
    XCTAssertNil([IMPushSender senderFromUserInfo:nil]);
}

- (void)testMissingNameFallsBackToID {
    IMPushSender *s = [IMPushSender senderFromUserInfo:@{ @"conv_id": @"u_1_u_2", @"sender_id": @"1002" }];
    XCTAssertEqualObjects(s.senderName, @"1002");
}

@end
