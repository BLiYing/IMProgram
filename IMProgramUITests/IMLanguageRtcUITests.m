//  IMLanguageRtcUITests.m
//  应用内语言切换 + im-rtc 通话 Kit locale 联动的**模拟器实测脚本**——不是常规回归，默认跳过。
//
//  用户报告：iOS 端把界面语言切成 English 后，发起通话时 Kit 界面文案好像没跟着变成英文。
//  本脚本走一遍真实路径：简体中文下发起 1v1 语音通话确认状态行是"正在呼叫…" → 切到 English →
//  再发起一次确认状态行变成 "Calling…"（`IMRtcCall.m` 的 `IMLocaleFromLanguage` 接线是否真的生效）→
//  切回简体中文确认能复原。判据只看用户看得见的文字，与 IMChatCalendarUITests 同一套写法。
//
//  依赖：本机 :8080 开发后端（`-dev-login`）+ 本机 im-rtc-server（`IMRtcConfig.local.plist` 里配的
//  wsUrl），账号 user1001 的会话列表里已有一个可点开的 1v1 会话（默认「光辉岁月」，随便一个 1v1
//  会话都行，呼叫对方在不在线不影响——outgoing 状态行发起瞬间就画出来，不等接通）。
//
//  跑法（在 IMProgram 仓里；环境变量经 TEST_RUNNER_ 前缀传给测试进程）：
//    TEST_RUNNER_IM_LANG_RTC_UITEST=1 xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram \
//      -destination 'id=<模拟器 UDID>' -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
//      -only-testing:IMProgramUITests/IMLanguageRtcUITests
//  可选：IM_LANG_RTC_USER（默认 user1001）、IM_LANG_RTC_PEER（默认「光辉岁月」，会话列表里的显示名）。
//  跑之前建议先 `xcrun simctl privacy <udid> grant microphone com.libeyond.IMProgram`，
//  否则首次通话会弹系统麦克风权限对话框，XCUITest 不处理系统弹窗会卡死。

#import <XCTest/XCTest.h>

@interface IMLanguageRtcUITests : XCTestCase
@end

@implementation IMLanguageRtcUITests

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (void)attachScreenshotOf:(XCUIApplication *)app named:(NSString *)name {
    XCTAttachment *shot = [XCTAttachment attachmentWithScreenshot:app.screenshot];
    shot.name = name;
    shot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:shot];
}

- (void)typeText:(NSString *)text into:(XCUIElement *)field app:(XCUIApplication *)app {
    for (NSInteger attempt = 0; attempt < 4; attempt++) {
        if ([[field valueForKey:@"hasKeyboardFocus"] boolValue]) {
            [field typeText:text];
            return;
        }
        [field tap];
        [NSThread sleepForTimeInterval:0.8];
    }
    [self attachScreenshotOf:app named:@"输入框拿不到焦点"];
    XCTFail(@"输入框点了 4 次仍没有键盘焦点");
}

/// 液态返回按钮固定标签"返回"（`IMLiquidNavigationBar.swift` 硬编码，不随界面语言翻译）——
/// 页面一旦 push 深了底部 Tab 栏会隐藏，找 Tab 前先弹回根页面。**每点一次就先看 Tab 栏是否已经
/// 露出来再决定要不要继续点**：自定义液态导航栏的转场动画不一定会让 XCUITest 的 idle 检测感知到，
/// 连续快点会在动画途中命中"下一屏此刻恰好在同一坐标"的别的控件（实测撞进过「我的二维码」页）。
- (BOOL)tabBarVisible:(XCUIApplication *)app {
    return app.tabBars.buttons[@"消息"].exists || app.tabBars.buttons[@"Messages"].exists
        || [app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label IN %@", @[@"消息", @"Messages"]]].firstMatch.exists;
}

- (void)popToTabRoot:(XCUIApplication *)app {
    if ([self tabBarVisible:app]) { return; }
    for (NSInteger i = 0; i < 4; i++) {
        XCUIElement *back = app.buttons[@"返回"];
        if (![back waitForExistenceWithTimeout:1.5]) { break; }
        [back tap];
        [NSThread sleepForTimeInterval:1.2];
        if ([self tabBarVisible:app]) { return; }
    }
}

/// 底部 Tab 按中英两个候选名找（切语言后标题会变），iOS 26 液态 Tab 栏不一定以 tabBars 暴露，退到按钮查找。
- (XCUIElement *)tabWithLabels:(NSArray<NSString *> *)labels app:(XCUIApplication *)app {
    [self popToTabRoot:app];
    for (NSString *l in labels) {
        XCUIElement *btn = app.tabBars.buttons[l];
        if (btn.exists) { return btn; }
    }
    NSPredicate *p = [NSPredicate predicateWithFormat:@"label IN %@", labels];
    return [app.buttons matchingPredicate:p].firstMatch;
}

- (XCUIElement *)meTab:(XCUIApplication *)app { return [self tabWithLabels:@[@"我", @"Me"] app:app]; }
- (XCUIElement *)messagesTab:(XCUIApplication *)app { return [self tabWithLabels:@[@"消息", @"Messages"] app:app]; }

/// 语言设置页 → 点指定选项（"简体中文"/"English" 两个选项本身固定用自己的语言书写，不随界面语言翻译，
/// 见 `IMServer/docs/i18n/strings.json` 的 settings.language.option_zh_hans/option_en 注释）。
- (void)switchLanguageTo:(NSString *)optionLabel app:(XCUIApplication *)app {
    XCUIElement *me = [self meTab:app];
    XCTAssertTrue([me waitForExistenceWithTimeout:8], @"没找到「我/Me」Tab");
    [me tap];
    [NSThread sleepForTimeInterval:0.4];

    NSPredicate *langRowPred = [NSPredicate predicateWithFormat:@"label IN %@", @[@"语言", @"Language"]];
    XCUIElement *langRow = [app.staticTexts matchingPredicate:langRowPred].firstMatch;
    if (!langRow.exists) { langRow = [app.cells matchingPredicate:langRowPred].firstMatch; }
    XCTAssertTrue([langRow waitForExistenceWithTimeout:8], @"设置页没找到「语言/Language」行");
    [langRow tap];
    [NSThread sleepForTimeInterval:0.4];

    // 模拟器系统语言是英文时，「跟随系统」行的副标题也会显示 "English"，与真正的 English 选项行撞标签——
    // 取**最后一个**匹配（options 数组顺序固定 system/zh-Hans/en，真正的选项行恒排在副标题重名行之后）。
    NSPredicate *optPred = [NSPredicate predicateWithFormat:@"label == %@", optionLabel];
    XCUIElementQuery *optQuery = [app.staticTexts matchingPredicate:optPred];
    XCTAssertTrue([optQuery.firstMatch waitForExistenceWithTimeout:8], @"语言页没找到选项「%@」", optionLabel);
    XCUIElement *option = optQuery.count > 1 ? [optQuery elementBoundByIndex:optQuery.count - 1] : optQuery.firstMatch;
    [option tap];
    // SceneDelegate 切语言会做 0.25s 交叉淡化 + 重建根控制器，多等一点再继续操作。
    [NSThread sleepForTimeInterval:1.5];
}

/// 从消息列表点开指定 1v1 会话 → 头像进详情页 → 点「呼叫/Call」发起语音通话。
- (void)placeVoiceCallToConversation:(NSString *)peerTitle app:(XCUIApplication *)app {
    XCUIElement *msgTab = [self messagesTab:app];
    XCTAssertTrue([msgTab waitForExistenceWithTimeout:8], @"没找到「消息/Messages」Tab");
    [msgTab tap];
    [NSThread sleepForTimeInterval:0.4];

    XCUIElement *row = app.staticTexts[peerTitle];
    XCTAssertTrue([row waitForExistenceWithTimeout:8], @"消息列表没找到会话「%@」", peerTitle);
    [row tap];
    [NSThread sleepForTimeInterval:0.6];

    NSPredicate *detailPred = [NSPredicate predicateWithFormat:@"label ENDSWITH %@ OR label ENDSWITH %@",
                               @"的聊天详情", @"chat details"];
    XCUIElement *detailBtn = [app.buttons matchingPredicate:detailPred].firstMatch;
    XCTAssertTrue([detailBtn waitForExistenceWithTimeout:8], @"聊天页没找到「…的聊天详情」按钮");
    [detailBtn tap];
    [NSThread sleepForTimeInterval:0.6];

    NSPredicate *callPred = [NSPredicate predicateWithFormat:@"label IN %@", @[@"呼叫", @"Call"]];
    XCUIElement *callPill = [app.buttons matchingPredicate:callPred].firstMatch;
    if (!callPill.exists) { callPill = [app.staticTexts matchingPredicate:callPred].firstMatch; }
    XCTAssertTrue([callPill waitForExistenceWithTimeout:8], @"详情页没找到「呼叫/Call」按钮");
    [callPill tap];
}

/// 点 Kit 的「取消/Cancel」结束刚发起的通话（outgoing 阶段的挂断按钮文案是 ctl.cancel，见 IMCallControls.swift）。
- (void)cancelOutgoingCall:(XCUIApplication *)app {
    NSPredicate *cancelPred = [NSPredicate predicateWithFormat:@"label IN %@", @[@"取消", @"Cancel"]];
    XCUIElement *cancelBtn = [app.buttons matchingPredicate:cancelPred].firstMatch;
    if ([cancelBtn waitForExistenceWithTimeout:5]) {
        [cancelBtn tap];
        [NSThread sleepForTimeInterval:0.6];
    } else {
        NSLog(@"[im-uitest] 没找到取消/Cancel 按钮，可能通话已经自己结束了");
    }
}

- (void)test_语言切换后通话Kit文案跟随 {
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    if (![env[@"IM_LANG_RTC_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"手动核对脚本，设 TEST_RUNNER_IM_LANG_RTC_UITEST=1 才跑");
    }
    NSString *user = env[@"IM_LANG_RTC_USER"] ?: @"user1001";
    NSString *peer = env[@"IM_LANG_RTC_PEER"] ?: @"光辉岁月";

    XCUIApplication *app = [XCUIApplication new];
    [app launch];

    XCUIElement *devLogin = app.buttons[@"免密登录（开发）"];
    if ([devLogin waitForExistenceWithTimeout:5]) {
        XCUIElement *userField = [app.textFields matchingPredicate:
            [NSPredicate predicateWithFormat:@"placeholderValue BEGINSWITH %@", @"用户名"]].firstMatch;
        XCTAssertTrue([userField waitForExistenceWithTimeout:5]);
        [self typeText:user into:userField app:app];
        [devLogin tap];
        [NSThread sleepForTimeInterval:1.5];
    }

    // ① 基线：确保是简体中文（可能上一轮跑到一半留在 English）。
    [self switchLanguageTo:@"简体中文" app:app];
    [self attachScreenshotOf:app named:@"0-基线中文-语言页"];

    // ② 中文下发起语音通话，确认状态行是「正在呼叫…」
    [self placeVoiceCallToConversation:peer app:app];
    XCUIElement *zhCalling = app.staticTexts[@"正在呼叫…"];
    BOOL zhOK = [zhCalling waitForExistenceWithTimeout:8];
    [self attachScreenshotOf:app named:@"1-中文呼叫中"];
    XCTAssertTrue(zhOK, @"中文下发起通话，状态行应显示「正在呼叫…」");
    [self cancelOutgoingCall:app];

    // ③ 切到 English
    [self switchLanguageTo:@"English" app:app];
    [self attachScreenshotOf:app named:@"2-已切英文-语言页"];
    XCUIElement *messagesTabEN = [self messagesTab:app];
    XCTAssertTrue([messagesTabEN waitForExistenceWithTimeout:5], @"切到 English 后底栏应出现「Messages」Tab（应用内文案没跟着切语言）");

    // ④ English 下再发起一次语音通话——这是用户报告的疑点：Kit 状态行应变成「Calling…」
    [self placeVoiceCallToConversation:peer app:app];
    XCUIElement *enCalling = app.staticTexts[@"Calling…"];
    BOOL enOK = [enCalling waitForExistenceWithTimeout:8];
    [self attachScreenshotOf:app named:@"3-英文呼叫中"];
    XCTAssertTrue(enOK, @"切到 English 后发起通话，状态行应显示「Calling…」——若失败即复现用户报告的「RTC 没有跟着切语言」");
    [self cancelOutgoingCall:app];

    // ⑤ 切回简体中文，确认能复原
    [self switchLanguageTo:@"简体中文" app:app];
    XCUIElement *messagesTabZH = [self messagesTab:app];
    XCTAssertTrue([messagesTabZH waitForExistenceWithTimeout:5], @"切回简体中文后底栏应恢复「消息」Tab");
    [self attachScreenshotOf:app named:@"4-切回中文-消息列表"];
}

@end
