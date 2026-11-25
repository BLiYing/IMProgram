//  IMWorkbenchUITests.m
//  工作台（WORKBENCH_DESIGN W4）的**模拟器实测脚本**——不是常规回归，默认跳过。
//  底部 Tab「工作台」→ 分组宫格 + 轮播 → 点应用在内置浏览器打开（演示应用显示兑换到的身份）
//  → 应用商店添加可选应用 → 回工作台出现 → 长按移除。
//
//  前置：本机开发后端（-dev-login）在跑；被测账号（默认 AliceRed = uqcsiuos3u）所在公司开了工作台，
//  上架了「演示应用」（强制不可移除，首页 http://127.0.0.1:8790/，带身份）、「官网」、「帮助中心」（可选），并有一张轮播图；
//  演示应用 cmd/wbdemo 在 :8790 跑着。跑法：
//    TEST_RUNNER_IM_WB_UITEST=1 xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build/DerivedData \
//      -parallel-testing-enabled NO -only-testing:IMProgramUITests/IMWorkbenchUITests -resultBundlePath build/WBUI.xcresult

#import <XCTest/XCTest.h>
#import "IMUITestLogin.h"

@interface IMWorkbenchUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation IMWorkbenchUITests

- (void)setUp {
    self.continueAfterFailure = NO;
    if (![NSProcessInfo.processInfo.environment[@"IM_WB_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"需要本机开发后端、工作台测试数据与 cmd/wbdemo，设 TEST_RUNNER_IM_WB_UITEST=1 才跑");
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

/// 等元素可点再点（弹层收起 / 转场动画期间点不到）。
- (void)tapWhenHittable:(XCUIElement *)el {
    NSPredicate *hittable = [NSPredicate predicateWithFormat:@"hittable == YES"];
    XCTWaiter *w = [XCTWaiter new];
    [w waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:hittable object:el]] timeout:8];
    [el tap];
}

/// 返回：自绘标题栏左键（默认标签「返回」）；栈里隐藏页的也在树上，取可点的那个（查询谓词不支持 hittable，只能逐个看）。
- (void)tapBack {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
    while (deadline.timeIntervalSinceNow > 0) {
        for (XCUIElement *b in [self.app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", @"返回"]].allElementsBoundByIndex) {
            if (b.isHittable) { [b tap]; return; }
        }
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    }
    XCTFail(@"找不到可点的返回键");
}

- (void)ensureLoggedIn {
    if ([self.app.tabBars.buttons[@"设置"] waitForExistenceWithTimeout:8]) { return; }
    NSString *uid = NSProcessInfo.processInfo.environment[@"IM_WB_USER"] ?: @"uqcsiuos3u";
    XCTAssertTrue(IMUITestShowPasswordLogin(self.app, 15), @"既没登录也不在登录页");
    XCUIElement *user = self.app.textFields.firstMatch;
    [user tap];
    [user typeText:uid];
    [self.app.buttons[@"免密登录（开发）"] tap];
    XCTAssertTrue([self.app.tabBars.buttons[@"设置"] waitForExistenceWithTimeout:20], @"没进主界面");
}

- (void)testWorkbenchFlow {
    [self ensureLoggedIn];
    XCUIElement *ok = self.app.alerts.buttons[@"我知道了"].firstMatch;
    if ([ok waitForExistenceWithTimeout:2]) { [ok tap]; }

    // 1 底栏有「工作台」，排在通讯录与设置之间
    XCUIElement *tab = self.app.tabBars.buttons[@"工作台"];
    XCTAssertTrue([tab waitForExistenceWithTimeout:15], @"server-config 有可看的公司时应出现「工作台」Tab");
    NSArray<NSString *> *labels = [self.app.tabBars.buttons.allElementsBoundByIndex valueForKey:@"label"];
    XCTAssertEqualObjects(labels, (@[@"消息", @"通讯录", @"工作台", @"设置"]), @"Tab 顺序");
    [tab tap];

    // 2 分组宫格：办公 / 服务；演示应用在
    XCUIElement *demo = self.app.collectionViews[@"workbench.grid"].cells[@"演示应用"];
    XCTAssertTrue([demo waitForExistenceWithTimeout:10], @"宫格里应有「演示应用」");
    XCTAssertTrue(self.app.staticTexts[@"办公"].exists && self.app.staticTexts[@"服务"].exists, @"按分组分段");
    [self shot:@"WB-1 工作台"];

    // 3 点应用 → 内置浏览器 → 演示应用显示兑换到的身份
    [demo tap];
    // 注：本机模拟器的 WebKit 缺中文字形（Safari 打开后台页同样是方框），只断言 ASCII 文字
    XCUIElement *who = self.app.webViews.staticTexts[@"AliceRed"];
    XCTAssertTrue([who waitForExistenceWithTimeout:15], @"演示应用应显示兑换到的昵称");
    XCTAssertTrue(self.app.webViews.staticTexts[@"staff"].exists, @"身份 = staff");
    [self shot:@"WB-2 演示应用"];
    [self.app.buttons[@"workbench.web.more"] tap];
    XCTAssertTrue([self.app.buttons[@"用浏览器打开"] waitForExistenceWithTimeout:3] || [self.app.staticTexts[@"用浏览器打开"] waitForExistenceWithTimeout:1], @"⋯ 菜单有「用浏览器打开」");
    [self shot:@"WB-3 网页菜单"];
    XCUIElement *cancel = self.app.buttons[@"取消"].firstMatch;
    if (cancel.exists) { [cancel tap]; } else { [self.app.staticTexts[@"取消"].firstMatch tap]; }
    [self tapWhenHittable:self.app.buttons[@"customerService.close"]]; // 左侧 ✕（弹层收起动画期间不可点）

    // 4 应用商店：添加可选的「帮助中心」→ 回工作台出现
    XCUIElement *storeBtn = self.app.buttons[@"workbench.store"];
    XCTAssertTrue([storeBtn waitForExistenceWithTimeout:5]);
    [storeBtn tap];
    XCUIElement *add = self.app.buttons[@"workbench.store.add.帮助中心"];
    if ([add waitForExistenceWithTimeout:10]) {
        [self shot:@"WB-4 应用商店"];
        [add tap];
        XCTAssertTrue([self.app.staticTexts[@"已添加"].firstMatch waitForExistenceWithTimeout:5]);
    }
    [self tapBack];
    XCUIElement *help = self.app.collectionViews[@"workbench.grid"].cells[@"帮助中心"];
    XCTAssertTrue([help waitForExistenceWithTimeout:10], @"添加后工作台出现「帮助中心」");
    [self shot:@"WB-5 添加后"];

    // 5 长按移除
    [help pressForDuration:1.0];
    XCUIElement *remove = self.app.buttons[@"移除"];
    XCTAssertTrue([remove waitForExistenceWithTimeout:5], @"长按应出「移除」");
    [self shot:@"WB-6 长按移除"];
    [remove tap];
    XCTAssertTrue([help waitForNonExistenceWithTimeout:5], @"移除后不在宫格里");
    // 强制不可移除的没有菜单
    [demo pressForDuration:1.0];
    XCTAssertFalse([self.app.buttons[@"移除"] waitForExistenceWithTimeout:2], @"强制不可移除的应用长按没有「移除」");
}

@end
