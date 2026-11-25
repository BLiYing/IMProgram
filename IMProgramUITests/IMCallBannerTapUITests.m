//  IMCallBannerTapUITests.m
//  BACKLOG B3 的**模拟器实测脚本**——不是常规回归，默认跳过。
//  App 在后台 / 被杀时收到来电横幅，点横幅**正文**（不是按钮）→ 应出全屏接听页，而不是只进聊天页 + 顶部小横幅。
//
//  前置：本机开发后端 + im-rtc-server 在跑，模拟器已登录被叫账号、音视频地址指本机（ws://127.0.0.1:8787/v1/ws）。
//  测试起来后在日志里打 `B3_READY`，**由外部脚本**接着让主叫发起呼叫、并用 `xcrun simctl push` 注入来电横幅
//  （模拟器收不到真 APNs）。TEST_RUNNER_IM_B3_MODE=bg（App 在后台、通话连接还在）| killed（先杀掉 App）。
//  横幅按「邀请你语音通话」找：外部脚本须发起**语音**通话、系统语言为中文。
//    TEST_RUNNER_IM_B3_UITEST=1 TEST_RUNNER_IM_B3_MODE=bg xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build/DerivedData \
//      -parallel-testing-enabled NO -only-testing:IMProgramUITests/IMCallBannerTapUITests -resultBundlePath build/B3UI.xcresult

#import <XCTest/XCTest.h>
#import "IMUITestLogin.h"

@interface IMCallBannerTapUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation IMCallBannerTapUITests

- (void)setUp {
    self.continueAfterFailure = NO;
    if (![NSProcessInfo.processInfo.environment[@"IM_B3_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"需要本机开发后端、im-rtc-server 与外部呼叫脚本，设 TEST_RUNNER_IM_B3_UITEST=1 才跑");
    }
    self.app = [XCUIApplication new];
}

- (void)shot:(XCUIApplication *)app name:(NSString *)name {
    XCTAttachment *a = [XCTAttachment attachmentWithScreenshot:app.screenshot];
    a.name = name;
    a.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:a];
}

- (void)testTapIncomingBannerShowsFullScreenAnswer {
    BOOL killed = [NSProcessInfo.processInfo.environment[@"IM_B3_MODE"] isEqualToString:@"killed"];
    [self.app launch]; // 重启到首页（登录态在磁盘上，保留）；停在聊天页之类时 tab 栏是隐藏的
    if (![self.app.tabBars.buttons[@"设置"] waitForExistenceWithTimeout:8]) {
        // 没登录（单测跑在 App 宿主里会清登录态）：免密登录被叫（默认 AliceRed = uqcsiuos3u）
        NSString *callee = NSProcessInfo.processInfo.environment[@"IM_B3_CALLEE"] ?: @"uqcsiuos3u";
        XCTAssertTrue(IMUITestShowPasswordLogin(self.app, 15), @"既没登录也不在登录页");
        XCUIElement *user = self.app.textFields.firstMatch;
        [user tap];
        [user typeText:callee];
        [self.app.buttons[@"免密登录（开发）"] tap];
    }
    XCTAssertTrue([self.app.tabBars.buttons[@"设置"] waitForExistenceWithTimeout:20], @"没进主界面");
    XCUIElement *ok = self.app.alerts.buttons[@"我知道了"].firstMatch;
    if ([ok waitForExistenceWithTimeout:2]) { [ok tap]; }
    [NSThread sleepForTimeInterval:5]; // 等通话服务连上（Kit 登录），否则后台时 SDK 收不到来电
    if (killed) { [self.app terminate]; } else { [XCUIDevice.sharedDevice pressButton:XCUIDeviceButtonHome]; }
    NSLog(@"B3_READY mode=%@", killed ? @"killed" : @"bg");

    XCUIApplication *springboard = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.springboard"];
    NSPredicate *invite = [NSPredicate predicateWithFormat:@"label CONTAINS %@", @"邀请你语音通话"];
    XCUIElement *banner = [[springboard descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:invite].firstMatch;
    XCTAssertTrue([banner waitForExistenceWithTimeout:90], @"90 秒内没等到来电横幅（外部脚本发起呼叫 + 注入推送了吗）");
    [self shot:springboard name:@"B3-来电横幅"];
    [banner tap];

    // 全屏接听页的「接听」在屏幕下半部；顶部小横幅上的接听按钮在最上面——按位置区分两种形态。
    XCUIElement *accept = self.app.buttons[@"接听"].firstMatch;
    BOOL fullScreen = NO;
    for (NSInteger i = 0; i < 30 && !fullScreen; i++) {
        fullScreen = accept.exists && CGRectGetMinY(accept.frame) > CGRectGetHeight(self.app.frame) / 2;
        if (!fullScreen) { [NSThread sleepForTimeInterval:0.5]; }
    }
    [self shot:self.app name:@"B3-点横幅后"];
    XCTAssertTrue(fullScreen, @"点来电横幅正文后应出全屏接听页（不是聊天页 + 顶部小横幅）");
}

@end
