//  IMSecurityS4UITests.m
//  后台「系统设置 ▸ 安全风控」S4（开放注册开关 + 登录失败锁定）的**模拟器实测脚本**——不是常规回归，默认跳过。
//  设计：../IMServer/docs/design/SYSTEM_SETTINGS_DESIGN.md §9.2。
//
//  前置（脚本不改后台值，跑之前用管理端调好）：
//    testA_RegisterClosed  ← sys.auth.register_enabled=0
//    testB_LoginLocked     ← sys.auth.login_fail_limit=3，并已注册密码账号 s4lockios / secret1（未被锁）
//  两条用例都会先在 App 里退出当前账号；testB 结束时用免密登录登回 user1001。
//  跑法同 IMUploadPolicyS3aUITests（TEST_RUNNER_IM_S4_UITEST=1）。

#import <XCTest/XCTest.h>

@interface IMSecurityS4UITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation IMSecurityS4UITests

- (void)setUp {
    self.continueAfterFailure = NO;
    if (![NSProcessInfo.processInfo.environment[@"IM_S4_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"需要本机开发后端与后台安全风控测试值，设 TEST_RUNNER_IM_S4_UITEST=1 才跑");
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
        XCTAttachment *t = [XCTAttachment attachmentWithString:self.app.debugDescription];
        t.name = [NSString stringWithFormat:@"树-找不到-%@", name];
        t.lifetime = XCTAttachmentLifetimeKeepAlways;
        [self addAttachment:t];
        XCTFail(@"找不到 %@", name);
    }
    return e;
}

/// 已登录则从「我」页退出，回到登录页。
- (void)logoutIfNeeded {
    XCUIElement *meTab = self.app.tabBars.buttons[@"我"];
    if (![meTab waitForExistenceWithTimeout:6]) { return; } // 已在登录页
    [meTab tap];
    XCUIElement *logout = self.app.buttons[@"退出登录"].firstMatch;
    if (!logout.exists) { logout = self.app.staticTexts[@"退出登录"].firstMatch; }
    for (NSInteger i = 0; i < 6 && !(logout.exists && logout.isHittable); i++) { [self.app swipeUp]; }
    [[self waitFor:logout named:@"退出登录"] tap];
    XCUIElement *confirm = self.app.alerts.buttons[@"退出登录"].firstMatch;
    if (![confirm waitForExistenceWithTimeout:3]) {
        confirm = [self.app.sheets.buttons matchingIdentifier:@"退出登录"].firstMatch;
    }
    [[self waitFor:confirm named:@"确认退出"] tap];
    [self waitFor:self.app.buttons[@"免密登录（开发）"] named:@"登录页"];
}

/// 两个「登录」按钮（Tab 与提交）里取靠下的那个 = 提交。
- (XCUIElement *)loginSubmit {
    XCUIElementQuery *q = [self.app.buttons matchingIdentifier:@"登录"];
    XCUIElement *best = nil;
    for (NSUInteger i = 0; i < q.count; i++) {
        XCUIElement *e = [q elementBoundByIndex:i];
        if (!best || e.frame.origin.y > best.frame.origin.y) { best = e; }
    }
    return best;
}

- (XCUIElement *)loginTab {
    XCUIElementQuery *q = [self.app.buttons matchingIdentifier:@"登录"];
    XCUIElement *best = nil;
    for (NSUInteger i = 0; i < q.count; i++) {
        XCUIElement *e = [q elementBoundByIndex:i];
        if (!best || e.frame.origin.y < best.frame.origin.y) { best = e; }
    }
    return best;
}

- (void)replaceText:(NSString *)text in:(XCUIElement *)field {
    [field tap];
    NSString *cur = [field.value isKindOfClass:NSString.class] ? field.value : @"";
    if (cur.length > 0 && ![cur isEqualToString:field.placeholderValue]) {
        NSString *del = [@"" stringByPaddingToLength:cur.length + 4 withString:XCUIKeyboardKeyDelete startingAtIndex:0];
        [field typeText:del];
    }
    [field typeText:text];
}

/// ① 关闭开放注册：切到「注册」Tab → 显示「管理员已暂停注册新账号」，「注册并登录」不可点。
- (void)testA_RegisterClosed {
    [self logoutIfNeeded];
    [[self waitFor:self.app.buttons[@"注册"].firstMatch named:@"注册 Tab"] tap];
    XCUIElement *notice = self.app.staticTexts[@"login.register_closed"];
    [self waitFor:notice named:@"暂停注册提示"];
    [NSThread sleepForTimeInterval:0.5];
    [self shot:@"A01-注册页-已暂停"];
    XCTAssertEqualObjects(notice.label, @"管理员已暂停注册新账号");
    XCTAssertFalse(self.app.buttons[@"注册并登录"].isEnabled, @"暂停注册时提交按钮应不可点");
}

/// ② 登录失败锁定（阈值 3）：连输 3 次错密码 → 第 4 次即使密码正确也提示「登录失败次数过多，请 N 分钟后再试」。
- (void)testB_LoginLocked {
    [self logoutIfNeeded];
    [[self waitFor:[self loginTab] named:@"登录 Tab"] tap];
    XCUIElement *user = self.app.textFields.firstMatch;
    XCUIElement *pass = self.app.secureTextFields.firstMatch;
    [self replaceText:@"s4lockios" in:[self waitFor:user named:@"用户名"]];
    NSArray *pwds = @[@"bad1xx", @"bad2xx", @"bad3xx", @"secret1"];
    for (NSUInteger i = 0; i < pwds.count; i++) {
        [self replaceText:pwds[i] in:pass];
        [[self loginSubmit] tap];
        [NSThread sleepForTimeInterval:2.0];
        [self shot:[NSString stringWithFormat:@"B0%lu-第%lu次", (unsigned long)i + 1, (unsigned long)i + 1]];
    }
    XCUIElement *locked = [self.app.staticTexts matchingPredicate:
                           [NSPredicate predicateWithFormat:@"label BEGINSWITH %@", @"登录失败次数过多"]].firstMatch;
    XCTAssertTrue([locked waitForExistenceWithTimeout:3], @"第 4 次应提示登录失败次数过多");

    // 收尾：免密登录回 user1001。
    [self replaceText:@"user1001" in:user];
    [self.app.buttons[@"免密登录（开发）"] tap];
    [self waitFor:self.app.tabBars.buttons[@"我"] named:@"登回主界面"];
}

@end
