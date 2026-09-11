//  IMChatSearchPagingUITests.m
//  会话内搜索「服务端命中翻页」的**模拟器实测脚本**——不是常规回归，默认跳过。
//
//  它依赖一个带离线积压数据的隔离后端（IMServer `docs/ops/LOAD_TESTING.md` §10.5 的副本库 + `:8099`，
//  登录页预填 `127.0.0.1:8099`、`-dev-login`），在那个群里搜一个命中远超 50 条的词，
//  走一遍「第一页 → ▲ 翻到最旧命中 → 再 ▲ 取第二页 → ▼ 跨回」。判据只看计数胶囊的文字，
//  所以它验的是用户看得见的东西，不是内部状态。与 im-web 那边的浏览器实测走的是同一条路径。
//
//  跑法（在 IMProgram 仓里；环境变量经 TEST_RUNNER_ 前缀传给测试进程）：
//    TEST_RUNNER_IM_SEARCH_UITEST=1 xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram \
//      -destination 'id=<模拟器 UDID>' -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
//      -only-testing:IMProgramUITests/IMChatSearchPagingUITests
//  可选：IM_SEARCH_GROUP（默认「20000人大群」）、IM_SEARCH_KEYWORD（默认「14:20」，积压灌库的标签里都带它）。

#import <XCTest/XCTest.h>

@interface IMChatSearchPagingUITests : XCTestCase
@end

@implementation IMChatSearchPagingUITests

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (void)attachScreenshotOf:(XCUIApplication *)app named:(NSString *)name {
    XCTAttachment *shot = [XCTAttachment attachmentWithScreenshot:app.screenshot];
    shot.name = name;
    shot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:shot];
}

/// 等计数胶囊的文字变成 text；超时就附一张截图再判负，失败时一眼能看出停在了哪。
- (void)waitForCount:(XCUIElement *)count toBe:(NSString *)text app:(XCUIApplication *)app {
    NSPredicate *p = [NSPredicate predicateWithFormat:@"label == %@", text];
    XCTNSPredicateExpectation *exp = [[XCTNSPredicateExpectation alloc] initWithPredicate:p object:count];
    XCTWaiterResult r = [XCTWaiter waitForExpectations:@[exp] timeout:25];
    if (r != XCTWaiterResultCompleted) {
        [self attachScreenshotOf:app named:[NSString stringWithFormat:@"等「%@」超时", text]];
        XCTFail(@"计数胶囊期望「%@」，实际「%@」", text, count.exists ? count.label : @"(不存在)");
    }
}

/// 往输入框里打字。**先确认真的拿到了键盘焦点**：页面转场刚落定时第一下 tap 常常没让它成为第一响应者，
/// 直接 typeText 会报「Neither element nor any descendant has keyboard focus」（2026-09-11 首跑即撞）。
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

- (void)test_大群搜索翻过第一页 {
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    if (![env[@"IM_SEARCH_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"需要带积压数据的 :8099 隔离后端，设 TEST_RUNNER_IM_SEARCH_UITEST=1 才跑");
    }
    NSString *group = env[@"IM_SEARCH_GROUP"] ?: @"20000人大群";
    NSString *keyword = env[@"IM_SEARCH_KEYWORD"] ?: @"14:20";

    XCUIApplication *app = [XCUIApplication new];
    [app launch];

    // ① 登录页（地址已预填隔离后端）→ 免密登录。已登录则跳过。
    XCUIElement *devLogin = app.buttons[@"免密登录（开发）"];
    if ([devLogin waitForExistenceWithTimeout:5]) {
        XCUIElement *user = [app.textFields matchingPredicate:
            [NSPredicate predicateWithFormat:@"placeholderValue BEGINSWITH %@", @"用户名"]].firstMatch;
        XCTAssertTrue([user waitForExistenceWithTimeout:5]);
        [self typeText:@"user1001" into:user app:app];
        [devLogin tap];
    }

    // ② 会话列表 → 目标群
    XCUIElement *row = app.staticTexts[group];
    XCTAssertTrue([row waitForExistenceWithTimeout:40], @"会话列表里没出现「%@」", group);
    [row tap];

    // ③ 聊天页右上角头像 → 聊天详情 → 「搜索」
    XCUIElement *detail = app.buttons[[NSString stringWithFormat:@"%@的聊天详情", group]];
    if (![detail waitForExistenceWithTimeout:5]) {
        // ⚠️ 注入的液态标题栏没把 rightBarButtonItem 的 accessibilityLabel 透出来（2026-09-11 首跑实测：
        // 右上角那颗 44×44 圆钮 label 为空）——VoiceOver 同样念不出「聊天详情」，是既有的无障碍缺口。
        // 这里退回按位置找：标题栏那一行最右边的 44×44 按钮。
        CGFloat width = app.windows.firstMatch.frame.size.width;
        for (XCUIElement *b in app.buttons.allElementsBoundByIndex) {
            CGRect f = b.frame;
            if (f.origin.y < 130 && CGRectGetMaxX(f) > width - 40 && f.size.width <= 48 && f.size.height <= 48) {
                detail = b;
                break;
            }
        }
    }
    if (!detail.exists) {
        [self attachScreenshotOf:app named:@"找不到详情入口"];
        for (XCUIElement *b in app.buttons.allElementsBoundByIndex) {
            NSLog(@"[im-uitest] button label=%@ id=%@ frame=%@", b.label, b.identifier, NSStringFromCGRect(b.frame));
        }
        XCTFail(@"聊天页右上角的详情入口没找到");
        return;
    }
    [detail tap];
    // ⚠️ 详情页操作排的按钮 accessibilityLabel 是**动作键**（"search"/"more"），不是标题「搜索」——
    // 见 IMChatDetailViewController+Header.m 的 actionPillButtonForSpec:。VoiceOver 因此念英文键名，是既有的无障碍缺口。
    XCUIElement *searchPill = app.buttons[@"search"];
    if (![searchPill waitForExistenceWithTimeout:10]) {
        // 按 label 找不到时把详情页上所有叫「搜索」的元素列出来，再挑标题栏以下那一个点。
        [self attachScreenshotOf:app named:@"详情页找不到搜索"];
        NSPredicate *named = [NSPredicate predicateWithFormat:@"label CONTAINS %@ OR identifier CONTAINS %@", @"搜索", @"search"];
        XCUIElementQuery *all = [[app descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:named];
        XCUIElement *pick = nil;
        for (XCUIElement *e in all.allElementsBoundByIndex) {
            NSLog(@"[im-uitest] 搜索候选 type=%lu label=%@ id=%@ frame=%@ hittable=%d",
                  (unsigned long)e.elementType, e.label, e.identifier, NSStringFromCGRect(e.frame), e.isHittable);
            if (!pick && e.isHittable && e.frame.origin.y > 120) { pick = e; }
        }
        for (XCUIElement *b in app.buttons.allElementsBoundByIndex) {
            NSLog(@"[im-uitest] 详情页 button label=%@ id=%@ frame=%@", b.label, b.identifier, NSStringFromCGRect(b.frame));
        }
        XCTAssertNotNil(pick, @"详情页没有「搜索」");
        searchPill = pick;
    }
    [searchPill tap];

    // ④ 输入关键词 → 第一页
    // 搜索框是 Swift 的 IMLiquidNavigationBar 里自持的 UISearchTextField，进搜索态时会自己 becomeFirstResponder。
    // 它不一定以 searchField 类型暴露（2026-09-11 实测 app.searchFields 为空），故依次退到：
    // 占位符含「搜索」的 textField → 当前持有键盘焦点的任意元素。
    XCUIElement *field = app.searchFields.firstMatch;
    if (![field waitForExistenceWithTimeout:6]) {
        field = [app.textFields matchingPredicate:
                 [NSPredicate predicateWithFormat:@"placeholderValue CONTAINS %@", @"搜索"]].firstMatch;
    }
    if (!field.exists) {
        field = [[app descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:
                 [NSPredicate predicateWithFormat:@"hasKeyboardFocus == YES"]].firstMatch;
    }
    if (![field waitForExistenceWithTimeout:6]) {
        [self attachScreenshotOf:app named:@"聊天页找不到搜索框"];
        for (XCUIElement *e in app.textFields.allElementsBoundByIndex) {
            NSLog(@"[im-uitest] textField label=%@ placeholder=%@ frame=%@", e.label, e.placeholderValue, NSStringFromCGRect(e.frame));
        }
        NSLog(@"[im-uitest] keyboards=%lu searchFields=%lu", (unsigned long)app.keyboards.count, (unsigned long)app.searchFields.count);
    }
    XCTAssertTrue(field.exists, @"聊天页搜索框没出现");
    [self typeText:keyword into:field app:app];
    XCUIElement *count = app.staticTexts[@"chat.search.count"];
    XCTAssertTrue([count waitForExistenceWithTimeout:15]);
    [self waitForCount:count toBe:@"第 50 / 50+ 条" app:app];
    [self attachScreenshotOf:app named:@"1-第一页"];

    // ⑤ ▲ 翻到第一页最旧的命中：计数带 + 时 ▲ 必须仍可点
    XCUIElement *prev = app.buttons[@"chat.search.prev"];
    XCUIElement *next = app.buttons[@"chat.search.next"];
    for (NSInteger i = 0; i < 49; i++) { [prev tap]; }
    [self waitForCount:count toBe:@"第 1 / 50+ 条" app:app];
    XCTAssertTrue(prev.isEnabled, @"在最旧命中上、服务端还有更早的页，▲ 却灰了");
    [self attachScreenshotOf:app named:@"2-第一页最旧命中"];

    // ⑥ 再 ▲：取第二页，拼到前面，落到紧挨着原最旧命中的那一条
    [prev tap];
    [self waitForCount:count toBe:@"第 50 / 100+ 条" app:app];
    [self attachScreenshotOf:app named:@"3-取回第二页"];

    // ⑦ ▼ 跨回第一页那段
    [next tap];
    [self waitForCount:count toBe:@"第 51 / 100+ 条" app:app];
    [self attachScreenshotOf:app named:@"4-跨回第一页"];
}

@end
