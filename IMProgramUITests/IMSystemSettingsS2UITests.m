//  IMSystemSettingsS2UITests.m
//  后台「系统设置」S2（server-config 下发的消息 / 群组上限）的**模拟器实测脚本**——不是常规回归，默认跳过。
//  设计：../IMServer/docs/design/SYSTEM_SETTINGS_DESIGN.md §3.1。
//
//  前置（脚本不负责改后台值）：本机开发后端 :8080 开着 -dev-login，后台「系统设置」已改成
//    撤回 3600 秒、编辑 60 秒、转发目标 3、合并转发 2、群名 10；
//  开发库账号 user1001 与「用户1002」的单聊里有自己发的、超过 1 分钟的文本「S2自测A / B / C」，
//  且 user1001 是「1001创建测试群」的群主或管理员。
//  每一步截图挂进 .xcresult（KeepAlways），关键处带断言。
//
//  跑法：
//    TEST_RUNNER_IM_S2_UITEST=1 xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram \
//      -destination 'id=<模拟器 UDID>' -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
//      -only-testing:IMProgramUITests/IMSystemSettingsS2UITests -resultBundlePath build/S2UI.xcresult

#import <XCTest/XCTest.h>
#import "IMUITestLogin.h"

@interface IMSystemSettingsS2UITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation IMSystemSettingsS2UITests

- (void)setUp {
    self.continueAfterFailure = YES; // 一项不过也继续往下测，最后统一看
    if (![NSProcessInfo.processInfo.environment[@"IM_S2_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"需要本机开发后端与后台测试值，设 TEST_RUNNER_IM_S2_UITEST=1 才跑");
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

- (void)typeText:(NSString *)text into:(XCUIElement *)field {
    for (NSInteger i = 0; i < 4; i++) {
        if ([[field valueForKey:@"hasKeyboardFocus"] boolValue]) { [field typeText:text]; return; }
        [field tap];
        [NSThread sleepForTimeInterval:0.8];
    }
    XCTFail(@"输入框拿不到焦点");
}

- (void)loginIfNeeded {
    IMUITestShowPasswordLogin(self.app, 5); // 免密按钮只在「密码登录」页签
    XCUIElement *devLogin = self.app.buttons[@"免密登录（开发）"];
    if ([devLogin waitForExistenceWithTimeout:5]) {
        XCUIElement *user = [self.app.textFields matchingPredicate:
            [NSPredicate predicateWithFormat:@"placeholderValue BEGINSWITH %@", @"用户名"]].firstMatch;
        [self typeText:@"user1001" into:user];
        [devLogin tap];
    }
    [self waitFor:self.app.tabBars.buttons[@"我"] named:@"Tab 我"];
    [NSThread sleepForTimeInterval:2.0]; // 等连上并拉到 server-config
}

/// 菜单里是否出现某一项（按钮或文字都算）。
- (BOOL)menuHas:(NSString *)title {
    return self.app.buttons[title].exists || self.app.staticTexts[title].exists || self.app.menuItems[title].exists;
}

- (void)dismissMenu {
    [self.app.windows.firstMatch coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.08)].tap;
    [NSThread sleepForTimeInterval:0.6];
}

/// 关掉弹出的面板 / 操作表：优先「取消」，其次左上角关闭（✕），都没有就下滑。
- (void)closeSheet {
    XCUIApplication *app = self.app;
    XCUIElement *cancel = app.sheets.buttons[@"取消"].firstMatch;
    if (!cancel.exists) { cancel = app.buttons[@"取消"].firstMatch; }
    XCUIElement *close = [app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label IN %@", @[@"关闭", @"Close", @"close"]]].firstMatch;
    if (cancel.exists && cancel.isHittable) { [cancel tap]; }
    else if (close.exists && close.isHittable) { [close tap]; }
    else { [[app.windows.firstMatch coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.3)] pressForDuration:0.1 thenDragToCoordinate:[app.windows.firstMatch coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.95)]]; }
    [NSThread sleepForTimeInterval:1.0];
}

- (XCUIElement *)anyStartingWith:(NSString *)prefix {
    return [[self.app descendantsMatchingType:XCUIElementTypeAny]
            matchingPredicate:[NSPredicate predicateWithFormat:@"label BEGINSWITH %@", prefix]].firstMatch;
}

/// 点标题栏一行上的某个水平位置（0~1）。
- (void)tapTop:(CGFloat)x {
    [[self.app.windows.firstMatch coordinateWithNormalizedOffset:CGVectorMake(x, 0.075)] tap];
}

- (void)openChatWith:(NSString *)name {
    [self.app.tabBars.buttons[@"消息"] tap];
    [[self waitFor:self.app.staticTexts[name].firstMatch named:name] tap];
    [NSThread sleepForTimeInterval:1.5];
}

- (void)testS2LimitsFollowServerConfig {
    XCUIApplication *app = self.app;
    [self loginIfNeeded];
    [self openChatWith:@"用户1002"];
    [self shot:@"01-单聊"];

    // ① 老消息（> 1 分钟，< 60 分钟）：撤回窗 3600 秒 → 有「撤回」；编辑窗 60 秒 → 没有「编辑」。
    XCUIElement *old = [self waitFor:app.staticTexts[@"S2自测A"].firstMatch named:@"S2自测A"];
    [old pressForDuration:1.0];
    [NSThread sleepForTimeInterval:0.8];
    [self shot:@"02-老消息菜单"];
    XCTAssertTrue([self menuHas:@"撤回"], @"老消息（撤回窗 60 分钟内）应有「撤回」");
    XCTAssertFalse([self menuHas:@"编辑"], @"老消息（超过 1 分钟编辑窗）不应有「编辑」");
    [self dismissMenu];

    // ② 新发一条：两项都有。（文字带时间戳，重跑时不会撞上一轮发的那条）
    NSString *freshText = [NSString stringWithFormat:@"S2iOS%ld", (long)(NSDate.date.timeIntervalSince1970) % 100000];
    XCUIElement *input = app.textViews.firstMatch;
    [self typeText:freshText into:input];
    XCUIElement *send = app.buttons[@"发送"];
    if (send.exists) { [send tap]; } else { [input typeText:@"\n"]; }
    [NSThread sleepForTimeInterval:1.5];
    XCUIElement *fresh = [self waitFor:app.staticTexts[freshText].firstMatch named:@"新消息"];
    [fresh pressForDuration:1.0];
    [NSThread sleepForTimeInterval:0.8];
    [self shot:@"03-新消息菜单"];
    XCTAssertTrue([self menuHas:@"撤回"], @"新消息应有「撤回」");
    XCTAssertTrue([self menuHas:@"编辑"], @"新消息（1 分钟内）应有「编辑」");

    // ③ 转发目标上限 3：多选勾 4 个，只能勾上 3 个。
    if (app.buttons[@"转发"].exists) { [app.buttons[@"转发"] tap]; } else { [app.staticTexts[@"转发"] tap]; }
    [[self waitFor:app.buttons[@"多选"] named:@"转发页 多选"] tap];
    [NSThread sleepForTimeInterval:0.6];
    [self shot:@"04-转发多选-空"];
    NSArray *targets = @[@"用户1002 2000", @"光辉岁月", @"学习交流", @"用户4982"];
    for (NSString *t in targets) {
        XCUIElement *row = app.staticTexts[t].firstMatch;
        if (row.exists) { [row tap]; [NSThread sleepForTimeInterval:0.4]; }
    }
    [self shot:@"05-转发多选-勾4个"];
    XCTAssertTrue(app.buttons[@"发送(3)"].exists || app.staticTexts[@"发送(3)"].exists, @"转发目标应停在 3 个");
    XCTAssertFalse(app.buttons[@"发送(4)"].exists, @"不应能选到第 4 个");
    [self closeSheet];

    // ④ 合并转发上限 2：多选 3 条 → 转发 → 合并转发 → 吐司拦下。
    [[self waitFor:app.staticTexts[@"S2自测B"].firstMatch named:@"S2自测B"] pressForDuration:1.0];
    [NSThread sleepForTimeInterval:0.8];
    if (app.buttons[@"多选"].exists) { [app.buttons[@"多选"] tap]; } else { [app.staticTexts[@"多选"] tap]; }
    [NSThread sleepForTimeInterval:0.8];
    [app.staticTexts[@"S2自测C"].firstMatch tap];
    [app.staticTexts[freshText].firstMatch tap];
    [NSThread sleepForTimeInterval:0.5];
    [self shot:@"06-消息多选3条"];
    XCUIElement *fwd = [app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", @"转发"]].firstMatch;
    [[self waitFor:fwd named:@"多选栏 转发"] tap];
    [NSThread sleepForTimeInterval:0.8];
    [self shot:@"07-转发方式"];
    [[self waitFor:app.buttons[@"合并转发"].firstMatch named:@"合并转发"] tap];
    [NSThread sleepForTimeInterval:0.4];
    [self shot:@"08-合并超限吐司"];
    // 吐司不一定以 StaticText 暴露，在全部元素里按文字找
    // 本 App 的吐司视图不进无障碍树（所有吐司都如此，非本次引入），这一项以截图「08-合并超限吐司」为证；
    // 能断言的是：没有被放行进合并转发的目标选择页。
    XCTAssertFalse(app.staticTexts[@"转发到"].exists, @"合并超限时不应进入转发目标选择页");
    [NSThread sleepForTimeInterval:2.5];
    [self closeSheet];
    // 退出消息多选（导航栏左侧「取消」）
    XCUIElement *cancelSel = app.buttons[@"取消"].firstMatch;
    if (cancelSel.exists && cancelSel.isHittable) { [cancelSel tap]; }
    [NSThread sleepForTimeInterval:0.8];

    // ⑤ 群名上限 10：群管理 → 改群名，往末尾多打 6 个字，计数停在 10/10，不保存。
    // 本 App 的标题栏是自绘的液态栏（不是系统 UINavigationBar）：返回 / 详情按位置点。
    [self tapTop:0.08];
    [NSThread sleepForTimeInterval:1.0];
    [self openChatWith:@"1001创建测试群"];
    [self tapTop:0.92];
    [NSThread sleepForTimeInterval:1.2];
    [self shot:@"09-群资料"];
    [self waitFor:app.staticTexts[@"群公告"].firstMatch named:@"群资料页（群公告行）"];
    [NSThread sleepForTimeInterval:1.5]; // 群资料拉回来后表格会整体重绘，等它稳定
    // 「群管理」在首屏最底边：先上拖一小段让它进入可视区，再**重新查询**、按它当下的屏幕位置点
    // （拖动前拿到的元素会随表格重绘失效）。
    XCUICoordinate *from = [app.windows.firstMatch coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.75)];
    [from pressForDuration:0.05 thenDragToCoordinate:[app.windows.firstMatch coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.55)]];
    [NSThread sleepForTimeInterval:1.0];
    [self shot:@"09b-群资料-上拖后"];
    // 这一行的元素查询在表格重绘期间时有时无，按上拖后的固定位置点（440×956 屏，约 y=0.587）。
    [[app.windows.firstMatch coordinateWithNormalizedOffset:CGVectorMake(0.3, 0.587)] tap];
    [NSThread sleepForTimeInterval:1.0];
    [[self waitFor:[self anyStartingWith:@"群名称"] named:@"群名称"] tap];
    [NSThread sleepForTimeInterval:0.8];
    XCUIElement *field = [self waitFor:app.alerts.textFields.firstMatch named:@"改群名输入框"];
    [field tap];
    [field typeText:@"ABCDEF"];
    [NSThread sleepForTimeInterval:0.6];
    [self shot:@"10-改群名-超限输入"];
    NSString *value = field.value;
    XCTAssertEqual(value.length, (NSUInteger)10, @"群名应被限在 10 字，实际「%@」", value);
    [app.alerts.buttons[@"取消"] tap];
    [NSThread sleepForTimeInterval:0.6];
    [self shot:@"11-取消改名"];
}

@end
