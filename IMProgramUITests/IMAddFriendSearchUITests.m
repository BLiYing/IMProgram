//  IMAddFriendSearchUITests.m
//  BACKLOG B1 的**模拟器实测脚本**——不是常规回归，默认跳过。
//  「添加朋友」搜索到已是好友的人 → 发消息 → 聊天页标题是对方昵称，不是 10 位内部 ID。
//
//  前置：本机开发后端在跑（-dev-login），开发库里 uqcsiuos3u（AliceRed）与 u815q3obj1（BobBlue）是好友、
//  且 AliceRed 没给 BobBlue 设备注。跑法：
//    TEST_RUNNER_IM_B1_UITEST=1 xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build/DerivedData \
//      -parallel-testing-enabled NO -only-testing:IMProgramUITests/IMAddFriendSearchUITests -resultBundlePath build/B1UI.xcresult

#import <XCTest/XCTest.h>
#import "IMUITestLogin.h"

@interface IMAddFriendSearchUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation IMAddFriendSearchUITests

- (void)setUp {
    self.continueAfterFailure = NO;
    if (![NSProcessInfo.processInfo.environment[@"IM_B1_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"需要本机开发后端与好友测试数据，设 TEST_RUNNER_IM_B1_UITEST=1 才跑");
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

- (void)loginAs:(NSString *)username {
    XCUIElement *meTab = self.app.tabBars.buttons[@"设置"];
    if ([meTab waitForExistenceWithTimeout:6]) {
        XCUIElement *ok = self.app.alerts.buttons[@"我知道了"].firstMatch;
        if ([ok waitForExistenceWithTimeout:2]) { [ok tap]; }
        [meTab tap];
        XCUIElement *logout = self.app.buttons[@"退出登录"].firstMatch;
        if (!logout.exists) { logout = self.app.staticTexts[@"退出登录"].firstMatch; }
        for (NSInteger i = 0; i < 6 && !(logout.exists && logout.isHittable); i++) { [self.app swipeUp]; }
        [[self waitFor:logout named:@"退出登录"] tap];
        XCUIElement *confirm = self.app.alerts.buttons[@"退出登录"].firstMatch;
        if (![confirm waitForExistenceWithTimeout:3]) { confirm = [self.app.sheets.buttons matchingIdentifier:@"退出登录"].firstMatch; }
        if (confirm.exists) { [confirm tap]; }
        [self waitFor:IMUITestLoginLogo(self.app) named:@"登录页"];
    }
    XCTAssertTrue(IMUITestShowPasswordLogin(self.app, 15), @"没回到登录页");
    XCUIElement *user = [self waitFor:self.app.textFields.firstMatch named:@"用户名"];
    [user tap];
    NSString *cur = [user.value isKindOfClass:NSString.class] ? user.value : @"";
    if (cur.length > 0 && ![cur isEqualToString:user.placeholderValue]) {
        [user typeText:[@"" stringByPaddingToLength:cur.length + 4 withString:XCUIKeyboardKeyDelete startingAtIndex:0]];
    }
    [user typeText:username];
    [self.app.buttons[@"免密登录（开发）"] tap];
    [self waitFor:self.app.tabBars.buttons[@"设置"] named:@"主界面"];
    XCUIElement *ok = self.app.alerts.buttons[@"我知道了"].firstMatch;
    if ([ok waitForExistenceWithTimeout:2]) { [ok tap]; }
}

- (void)testSearchFriendThenSendMessageShowsNickname {
    [self loginAs:@"uqcsiuos3u"];
    [self.app.tabBars.buttons[@"通讯录"] tap];
    // 通讯录右上角「添加朋友」：只有图标，无障碍名是 SF Symbol 名
    XCUIElement *add = self.app.buttons[@"person.badge.plus"].firstMatch;
    [[self waitFor:add named:@"添加朋友"] tap];
    XCUIElement *field = [self waitFor:self.app.searchFields.firstMatch named:@"搜索框"];
    [field tap];
    [field typeText:@"u815q3obj1\n"];
    [[self waitFor:self.app.buttons[@"发消息"].firstMatch named:@"发消息"] tap];
    // 聊天页标题是自定义胶囊视图（不是系统导航栏标题），按「屏幕顶部的那行字」找
    [self waitFor:self.app.textViews.firstMatch named:@"聊天输入框"];
    XCUIElement *title = self.app.staticTexts[@"BobBlue"].firstMatch;
    BOOL ok = [title waitForExistenceWithTimeout:10] && CGRectGetMinY(title.frame) < 150;
    [self shot:@"B1-聊天页标题"];
    XCTAssertTrue(ok, @"聊天页标题应为对方昵称 BobBlue（不能是内部 ID）");
    XCTAssertFalse(self.app.staticTexts[@"9924909322"].exists, @"界面上不该出现内部 ID");
}

@end
