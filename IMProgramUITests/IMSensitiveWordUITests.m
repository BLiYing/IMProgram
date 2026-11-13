//  IMSensitiveWordUITests.m
//  敏感词过滤（../IMServer/docs/design/SENSITIVE_WORDS_DESIGN.md）的模拟器自测：发消息被拦 → 失败气泡下方显示说明、无重发；
//  编辑消息被拦 → 提示且编辑内容回到输入框。默认跳过，需先：
//    ① 开发后端在跑，后台词表里有 badword9、档位为「拦截」；② IM_SW_USER（专用测试号，**别用真机在用的账号**——多登一台可能把真机挤下线）
//       与 IM_SW_PEER 是好友且已有会话。App 未登录时用 IM_SW_USER 免密登录。
//  跑法（TEST_RUNNER_ 前缀由 xcodebuild 剥掉）：
//    TEST_RUNNER_IM_SW=1 TEST_RUNNER_IM_SW_USER=swios TEST_RUNNER_IM_SW_PEER=smokepeer xcodebuild test … -only-testing:IMProgramUITests/IMSensitiveWordUITests

#import <XCTest/XCTest.h>
#import "IMUITestLogin.h"

@interface IMSensitiveWordUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation IMSensitiveWordUITests

- (void)setUp {
    self.continueAfterFailure = NO;
    if (![NSProcessInfo.processInfo.environment[@"IM_SW"] isEqualToString:@"1"]) {
        XCTSkip(@"敏感词 UI 自测需要开发后端预置词表与档位，单独跑会跳过");
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

- (XCUIElement *)containing:(NSString *)text {
    return [[self.app descendantsMatchingType:XCUIElementTypeAny]
            matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@ OR value CONTAINS %@", text, text]].firstMatch;
}

- (void)must:(XCUIElement *)e name:(NSString *)name timeout:(NSTimeInterval)t {
    if (![e waitForExistenceWithTimeout:t]) {
        [self shot:[@"找不到-" stringByAppendingString:name]];
        XCTFail(@"找不到 %@", name);
    }
}

- (void)loginIfNeeded {
    IMUITestShowPasswordLogin(self.app, 5); // 免密按钮只在「密码登录」页签
    XCUIElement *devLogin = self.app.buttons[@"免密登录（开发）"];
    if (![devLogin waitForExistenceWithTimeout:5]) { return; }
    NSString *user = NSProcessInfo.processInfo.environment[@"IM_SW_USER"];
    XCTAssertTrue(user.length, @"App 未登录：请传 IM_SW_USER（专用测试号）");
    XCUIElement *field = self.app.textFields.firstMatch;
    [field tap];
    [field typeText:user];
    [devLogin tap];
}

- (void)sendText:(NSString *)text input:(XCUIElement *)input {
    [input tap];
    [input typeText:text];
    XCUIElement *send = [self.app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label IN %@ OR identifier IN %@",
                         @[@"发送", @"Send", @"arrow.up.circle.fill", @"arrow.up"], @[@"发送", @"Send", @"arrow.up.circle.fill", @"arrow.up"]]].firstMatch;
    if ([send waitForExistenceWithTimeout:2]) { [send tap]; } else { [input typeText:@"\n"]; }
}

- (void)testBlockedSendShowsNoteAndEditKeepsText {
    NSString *peer = NSProcessInfo.processInfo.environment[@"IM_SW_PEER"] ?: @"smokepeer";
    [self loginIfNeeded];
    [self must:self.app.tabBars.buttons[@"消息"] name:@"主界面" timeout:20];
    [self.app.tabBars.buttons[@"消息"] tap];
    XCUIElement *row = self.app.staticTexts[peer].firstMatch;
    [self must:row name:@"会话" timeout:10];
    [row tap];

    // ⓪ 先发一条干净的，供 ② 编辑。① 发消息被拦：失败气泡下方显示「内容包含不允许发送的词语」。
    XCUIElement *input = self.app.textViews.firstMatch;
    [self must:input name:@"输入框" timeout:5];
    NSString *clean = [NSString stringWithFormat:@"clean %u", arc4random_uniform(100000)];
    [self sendText:clean input:input];
    // 只认气泡（cell），不认输入框里还没发出去的那份。
    [self must:[self.app.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", clean]].firstMatch name:@"干净消息气泡" timeout:10];
    [self sendText:@"ios badword9" input:input];
    [self must:[self containing:@"不允许发送的词语"] name:@"被拦说明" timeout:10];
    [self shot:@"S1-发消息被拦"];

    // ② 编辑被拦：长按自己发过的一条 → 编辑 → 改成命中词 → 发送；提示出现，编辑内容仍在输入框。
    XCUIElement *mine = [self.app.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", clean]].firstMatch;
    [self must:mine name:@"自己的消息" timeout:5];
    [mine pressForDuration:1.0];
    XCUIElement *edit = self.app.buttons[@"编辑"].firstMatch;
    if (![edit waitForExistenceWithTimeout:3]) { edit = self.app.staticTexts[@"编辑"].firstMatch; }
    [self must:edit name:@"编辑菜单" timeout:3];
    [edit tap];
    [input tap];
    NSString *old = [input.value isKindOfClass:NSString.class] ? input.value : @"";
    for (NSUInteger i = 0; i < old.length + 2; i++) { [input typeText:XCUIKeyboardKeyDelete]; }
    [self sendText:@"edit badword9" input:input];
    // 提示只停留约 1.9 秒，查无障碍树太慢会错过：发送后连拍，靠截图人工确认提示可见（不被键盘挡住）。
    for (int k = 0; k < 6; k++) {
        [NSThread sleepForTimeInterval:0.3];
        [self shot:[NSString stringWithFormat:@"S2-编辑被拦-%d", k]];
    }
    XCTAssertTrue([self.app.textViews.firstMatch waitForExistenceWithTimeout:3]);
    NSPredicate *kept = [NSPredicate predicateWithFormat:@"value CONTAINS %@", @"edit badword9"];
    [self expectationForPredicate:kept evaluatedWithObject:self.app.textViews.firstMatch handler:nil];
    [self waitForExpectationsWithTimeout:5 handler:nil];
    [self shot:@"S3-编辑内容回到输入框"];
}

@end
