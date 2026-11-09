//  IMSmokeUITests.m
//  移动端冒烟（T3，../IMServer/docs/design/E2E_REGRESSION_DESIGN.md §6）：装上新包后，核心链路在真 App 里走一遍。
//  不是常规回归，默认跳过；一键跑法：./scripts/ui-smoke.sh（它先用 ../IMServer/scripts/smoke/mobile-smoke.mjs 造数据，
//  再跑本用例，最后到服务端核对对端真的收到了）。
//
//  脚本传入（TEST_RUNNER_ 前缀由 xcodebuild 剥掉）：IM_SMOKE=1、IM_SMOKE_USER（设备账号）、IM_SMOKE_PEER、IM_SMOKE_PING、IM_SMOKE_PONG。
//  步骤：（必要时免密登录）→ 会话列表里出现对端刚发的 ping → 点进去看到 ping 气泡 → 输入 pong 发送 → pong 气泡出现。

#import <XCTest/XCTest.h>

@interface IMSmokeUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *env;
@end

@implementation IMSmokeUITests

- (void)setUp {
    self.continueAfterFailure = NO;
    self.env = NSProcessInfo.processInfo.environment;
    if (![self.env[@"IM_SMOKE"] isEqualToString:@"1"]) {
        XCTSkip(@"移动端冒烟由 ./scripts/ui-smoke.sh 驱动（需要开发后端与造数据），单独跑会跳过");
    }
    self.app = [XCUIApplication new];
    [self.app launch];
}

- (void)shot:(NSString *)name {
    XCTAttachment *a = [XCTAttachment attachmentWithScreenshot:self.app.screenshot];
    a.name = name;
    a.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:a];
}

- (XCUIElement *)waitFor:(XCUIElement *)e named:(NSString *)name timeout:(NSTimeInterval)timeout {
    if (![e waitForExistenceWithTimeout:timeout]) {
        [self shot:[NSString stringWithFormat:@"找不到-%@", name]];
        XCTAttachment *t = [XCTAttachment attachmentWithString:self.app.debugDescription];
        t.name = [NSString stringWithFormat:@"树-找不到-%@", name];
        t.lifetime = XCTAttachmentLifetimeKeepAlways;
        [self addAttachment:t];
        XCTFail(@"找不到 %@", name);
    }
    return e;
}

- (XCUIElement *)textContaining:(NSString *)text {
    return [[self.app descendantsMatchingType:XCUIElementTypeAny]
            matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@ OR value CONTAINS %@", text, text]].firstMatch;
}

- (void)loginIfNeeded {
    XCUIElement *devLogin = self.app.buttons[@"免密登录（开发）"];
    if (![devLogin waitForExistenceWithTimeout:5]) { return; }
    XCUIElement *user = self.app.textFields.firstMatch;
    [user tap];
    [user typeText:self.env[@"IM_SMOKE_USER"] ?: @"user1001"];
    [devLogin tap];
}

- (void)testSmokeReceiveAndSend {
    NSString *peer = self.env[@"IM_SMOKE_PEER"], *ping = self.env[@"IM_SMOKE_PING"], *pong = self.env[@"IM_SMOKE_PONG"];
    XCTAssertTrue(peer.length && ping.length && pong.length, @"缺 IM_SMOKE_PEER / PING / PONG");

    [self loginIfNeeded];
    [self waitFor:self.app.tabBars.buttons[@"消息"] named:@"主界面" timeout:20];
    [self.app.tabBars.buttons[@"消息"] tap];

    // ① 收：对端刚发的 ping 出现在会话列表（实时推送或进前台同步）。
    [self waitFor:[self textContaining:ping] named:@"列表里的 ping" timeout:20];
    [self shot:@"S01-会话列表收到ping"];
    [[self waitFor:self.app.staticTexts[peer].firstMatch named:@"对端会话" timeout:5] tap];
    [self waitFor:[self textContaining:ping] named:@"聊天页 ping 气泡" timeout:10];

    // ② 发：输入 pong 发送。
    XCUIElement *input = self.app.textViews.firstMatch;
    [[self waitFor:input named:@"输入框" timeout:5] tap];
    [input typeText:pong];
    XCUIElement *send = [self.app.buttons matchingPredicate:[NSPredicate predicateWithFormat:
                         @"label IN %@ OR identifier IN %@", @[@"发送", @"Send", @"arrow.up.circle.fill", @"arrow.up"],
                         @[@"发送", @"Send", @"arrow.up.circle.fill", @"arrow.up"]]].firstMatch;
    if ([send waitForExistenceWithTimeout:2]) { [send tap]; } else { [input typeText:@"\n"]; }
    [self shot:@"S02-发送pong后"];

    // ③ 自己这边出现 pong 气泡（服务端是否真收到，由脚本事后到服务端核对）。
    XCUIElement *pongBubble = [self.app.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", pong]].firstMatch;
    if (![pongBubble waitForExistenceWithTimeout:10]) { pongBubble = [self textContaining:pong]; }
    [self waitFor:pongBubble named:@"pong 气泡" timeout:5];
    [NSThread sleepForTimeInterval:2.0]; // 留时间给 ack 往返，脚本随后核对服务端
    [self shot:@"S03-pong已发出"];
}

@end
