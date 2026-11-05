//  IMSharePickerUITests.m
//  分享选择页（SHARE_PICKER_UX_SKETCH）的**模拟器实测脚本**——不是常规回归，默认跳过。
//  依赖本机开发后端（:8080、-dev-login）与开发库里的账号 user4982（3 个从没聊过的好友 + 9 个群）。
//  每一步截图挂进 .xcresult（XCTAttachmentLifetimeKeepAlways），用 xcresulttool 导出后肉眼核对。
//
//  跑法：
//    TEST_RUNNER_IM_SHARE_UITEST=1 xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram \
//      -destination 'id=<模拟器 UDID>' -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
//      -only-testing:IMProgramUITests/IMSharePickerUITests -resultBundlePath build/SharePickerUI.xcresult

#import <XCTest/XCTest.h>

@interface IMSharePickerUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation IMSharePickerUITests

- (void)setUp {
    self.continueAfterFailure = NO;
    if (![NSProcessInfo.processInfo.environment[@"IM_SHARE_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"需要本机开发后端与 user4982 账号，设 TEST_RUNNER_IM_SHARE_UITEST=1 才跑");
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

- (XCUIElement *)waitFor:(XCUIElement *)e named:(NSString *)name {
    if (![e waitForExistenceWithTimeout:15]) {
        [self shot:[NSString stringWithFormat:@"找不到-%@", name]];
        XCTFail(@"找不到 %@", name);
    }
    return e;
}

- (void)tapStatic:(NSString *)text {
    [[self waitFor:self.app.staticTexts[text].firstMatch named:text] tap];
}

- (void)typeText:(NSString *)text into:(XCUIElement *)field {
    for (NSInteger i = 0; i < 4; i++) {
        if ([[field valueForKey:@"hasKeyboardFocus"] boolValue]) { [field typeText:text]; return; }
        [field tap];
        [NSThread sleepForTimeInterval:0.8];
    }
    XCTFail(@"输入框拿不到焦点");
}

- (void)loginIfNeeded {
    XCUIElement *devLogin = self.app.buttons[@"免密登录（开发）"];
    if ([devLogin waitForExistenceWithTimeout:5]) {
        XCUIElement *user = [self.app.textFields matchingPredicate:
            [NSPredicate predicateWithFormat:@"placeholderValue BEGINSWITH %@", @"用户名"]].firstMatch;
        [self typeText:@"user4982" into:user];
        [devLogin tap];
    }
    [self waitFor:self.app.tabBars.buttons[@"我"] named:@"Tab 我"];
}

- (void)openShareMyCard {
    [self.app.tabBars.buttons[@"我"] tap];
    [self tapStatic:@"分享我的名片"];
    [self waitFor:self.app.staticTexts[@"我的好友"] named:@"入口 我的好友"];
    [NSThread sleepForTimeInterval:1.0];
}

- (void)testShareFlows {
    XCUIApplication *app = self.app;
    [self loginIfNeeded];

    // ① 单选：主页有两个入口 → 我的好友 → 点没聊过的「用户1002」→ 确认框 → 发送。
    [self openShareMyCard];
    [self shot:@"01-主页-单选"];
    [self tapStatic:@"我的好友"];
    [self waitFor:app.staticTexts[@"用户1002"] named:@"好友 用户1002"];
    [self shot:@"02-我的好友-单选"];
    [self tapStatic:@"用户1002"];
    XCUIElement *alertSend = [self waitFor:app.alerts.buttons[@"发送"] named:@"确认框 发送"];
    [self shot:@"03-单选确认框"];
    [alertSend tap];
    [NSThread sleepForTimeInterval:1.5];
    [self shot:@"04-单选发送后"];

    // ② 多选：空已选栏 → 好友子页勾「用户1001ces」→ 回主页 → 群聊子页勾「学习交流」→ 发送(2) → 确认面板。
    [self openShareMyCard];
    [[self waitFor:app.buttons[@"多选"] named:@"多选"] tap];
    [NSThread sleepForTimeInterval:0.5];
    [self shot:@"05-多选-空已选栏"];
    [self tapStatic:@"我的好友"];
    [self tapStatic:@"用户1001ces"];
    [NSThread sleepForTimeInterval:0.6];
    [self shot:@"06-好友子页-勾1个"];
    [app.navigationBars.buttons.firstMatch tap]; // 返回
    [NSThread sleepForTimeInterval:0.8];
    [self shot:@"07-返回主页-已选保留"];
    [self tapStatic:@"我的群聊"];
    [self tapStatic:@"学习交流"];
    [NSThread sleepForTimeInterval:0.6];
    [self shot:@"08-群聊子页-勾2个"];
    [[self waitFor:app.buttons[@"发送(2)"] named:@"发送(2)"] tap];
    [NSThread sleepForTimeInterval:1.0];
    [self shot:@"09-确认面板"];
    [NSThread sleepForTimeInterval:4.0];
    [self shot:@"09b-确认面板-停留4秒"];
    // 面板里删一个再发：删「学习交流」，剩 1 个
    [[self waitFor:app.buttons[@"移除 学习交流"].firstMatch named:@"面板 ✕"] tap];
    [NSThread sleepForTimeInterval:0.6];
    [self shot:@"10-确认面板-删一个"];
    [[self waitFor:app.buttons[@"发送"].firstMatch named:@"面板发送"] tap];
    [NSThread sleepForTimeInterval:1.5];
    [self shot:@"11-多选发送后"];

    // ③ 上限：群聊子页连勾 9 个群后再勾好友 → 吐司；已选栏 ✕ 删一个；取消放弃。
    [self openShareMyCard];
    [app.buttons[@"多选"] tap];
    [self tapStatic:@"我的群聊"];
    [NSThread sleepForTimeInterval:1.0];
    XCUIElementQuery *cells = app.tables.cells;
    NSUInteger n = MIN(cells.count, (NSUInteger)9);
    for (NSUInteger i = 0; i < n; i++) { [[cells elementBoundByIndex:i] tap]; [NSThread sleepForTimeInterval:0.3]; }
    [self shot:@"12-群聊子页-选满"];
    [app.navigationBars.buttons.firstMatch tap];
    [self tapStatic:@"我的好友"];
    [self tapStatic:@"光辉岁月"];
    [NSThread sleepForTimeInterval:0.3];
    [self shot:@"13-超限吐司"];
    [[self waitFor:app.buttons[@"移除 学习交流"].firstMatch named:@"已选栏 ✕"] tap];
    [NSThread sleepForTimeInterval:0.5];
    [self shot:@"14-已选栏删一个"];
    [app.navigationBars.buttons.firstMatch tap];
    [NSThread sleepForTimeInterval:0.6];

    // ④ 主页搜索：同时搜最近聊天 / 好友 / 群，按 conv_id 去重分组。
    XCUIElement *search = app.searchFields.firstMatch;
    [self typeText:@"1001" into:search];
    [NSThread sleepForTimeInterval:1.0];
    [self shot:@"15-搜索分组"];
    [app.navigationBars.buttons[@"Cancel"].exists ? app.navigationBars.buttons[@"Cancel"] : app.navigationBars.buttons[@"取消"] tap];
    [NSThread sleepForTimeInterval:1.0];

    // ⑤ 二维码页：分享 → 发送方式 → 发送给朋友 → 选择页（名片预览）。
    // 「我」页是自绘液态标题栏，二维码图标不一定暴露成带名字的 button：按坐标点左上角。
    [[app coordinateWithNormalizedOffset:CGVectorMake(0.087, 0.094)] tap];
    [[self waitFor:app.buttons[@"分享"] named:@"分享"] tap];
    [NSThread sleepForTimeInterval:0.8];
    [self shot:@"16-二维码-发送方式"];
    [self tapStatic:@"发送给朋友"];
    [self waitFor:app.staticTexts[@"我的好友"] named:@"二维码→选择页"];
    [self shot:@"17-二维码-选择页"];
    [app.buttons[@"多选"] tap];
    [self tapStatic:@"用户1002"];
    [app.buttons[@"发送(1)"] tap];
    [NSThread sleepForTimeInterval:1.0];
    [self shot:@"18-二维码-确认面板预览"];
    [app.buttons[@"取消"].firstMatch tap];
    [NSThread sleepForTimeInterval:0.6];
    [app.navigationBars.buttons[@"Cancel"].exists ? app.navigationBars.buttons[@"Cancel"] : app.navigationBars.buttons[@"取消"] tap];
    [NSThread sleepForTimeInterval:0.8];

    // ⑥ 会话列表：刚发过名片的「用户1002」「用户1001ces」应出现（原先没有会话）。
    // 二维码页是 push 页（Tab 栏隐藏）：先点左上返回。
    [[app coordinateWithNormalizedOffset:CGVectorMake(0.087, 0.094)] tap];
    [NSThread sleepForTimeInterval:1.0];
    [[self waitFor:app.tabBars.buttons[@"消息"] named:@"Tab 消息"] tap];
    [NSThread sleepForTimeInterval:2.0];
    [self shot:@"19-会话列表-新会话出现"];
    XCTAssertTrue([app.staticTexts[@"用户1002"].firstMatch waitForExistenceWithTimeout:5]);
    XCTAssertTrue([app.staticTexts[@"用户1001ces"].firstMatch waitForExistenceWithTimeout:5]);
}

@end
