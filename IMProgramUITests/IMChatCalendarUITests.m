//  IMChatCalendarUITests.m
//  会话内搜索「日历跳转」的**模拟器实测脚本**——不是常规回归，默认跳过。
//
//  2026-09-25：Android 端对比发现日历圆点数量不一致，查出根因是 iOS `searchCalTapped` 请求跨度
//  730 天超服务端 400 天上限、请求恒被拒（见 `IMChatViewController+Search.m` 的
//  `kIMChatCalendarQuerySpanMs` 注释），改成 390 天后本脚本用于真机/模拟器肉眼核对：圆点位置、
//  「最早」「今天」跳转是否生效。跑在本机默认开发后端（`127.0.0.1:8080`，已含常规测试数据），
//  不需要 IMChatSearchPagingUITests 那种隔离积压副本库。
//
//  跑法（在 IMProgram 仓里；环境变量经 TEST_RUNNER_ 前缀传给测试进程）：
//    TEST_RUNNER_IM_CALENDAR_UITEST=1 xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram \
//      -destination 'id=<模拟器 UDID>' -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
//      -only-testing:IMProgramUITests/IMChatCalendarUITests
//  可选：IM_CALENDAR_GROUP（默认「20000人大群」）、IM_CALENDAR_KEYWORD（默认「CCC」）、
//  IM_CALENDAR_USER（默认「user1001」，免密登录用）。

#import <XCTest/XCTest.h>

@interface IMChatCalendarUITests : XCTestCase
@end

@implementation IMChatCalendarUITests

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

- (void)test_日历圆点与最早今天跳转 {
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    if (![env[@"IM_CALENDAR_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"手动核对脚本，设 TEST_RUNNER_IM_CALENDAR_UITEST=1 才跑");
    }
    NSString *group = env[@"IM_CALENDAR_GROUP"] ?: @"20000人大群";
    NSString *keyword = env[@"IM_CALENDAR_KEYWORD"] ?: @"CCC";
    NSString *user = env[@"IM_CALENDAR_USER"] ?: @"user1001";

    XCUIApplication *app = [XCUIApplication new];
    [app launch];

    // ① 登录页 → 免密登录（已登录则跳过）。
    XCUIElement *devLogin = app.buttons[@"免密登录（开发）"];
    if ([devLogin waitForExistenceWithTimeout:5]) {
        XCUIElement *userField = [app.textFields matchingPredicate:
            [NSPredicate predicateWithFormat:@"placeholderValue BEGINSWITH %@", @"用户名"]].firstMatch;
        XCTAssertTrue([userField waitForExistenceWithTimeout:5]);
        [self typeText:user into:userField app:app];
        [devLogin tap];
    }

    // ② 会话列表 → 目标群
    XCUIElement *row = app.staticTexts[group];
    XCTAssertTrue([row waitForExistenceWithTimeout:40], @"会话列表里没出现「%@」", group);
    [row tap];

    // ③ 聊天页头像 → 聊天详情 → 「搜索」（同 IMChatSearchPagingUITests 的路径）
    XCUIElement *detail = [app.buttons matchingPredicate:
        [NSPredicate predicateWithFormat:@"label ENDSWITH %@", @"的聊天详情"]].firstMatch;
    XCTAssertTrue([detail waitForExistenceWithTimeout:10], @"聊天页右上角没找到「…的聊天详情」按钮");
    [detail tap];
    XCUIElement *searchPill = app.buttons[@"detail.pill.search"];
    XCTAssertTrue([searchPill waitForExistenceWithTimeout:10], @"详情页没有 detail.pill.search 按钮");
    [searchPill tap];

    // ④ 输入关键词——**不强求命中**：这条脚本要测的是日历，不是搜索命中（那条路 Android 已验证过，
    // 这个账号能不能看到「CCC」这几条测试消息取决于入群时间/可见下界，命中与否不影响日历钮的出现）。
    XCUIElement *field = app.searchFields.firstMatch;
    if (![field waitForExistenceWithTimeout:6]) {
        field = [app.textFields matchingPredicate:
                 [NSPredicate predicateWithFormat:@"placeholderValue CONTAINS %@", @"搜索"]].firstMatch;
    }
    XCTAssertTrue([field waitForExistenceWithTimeout:6], @"聊天页搜索框没出现");
    [self typeText:keyword into:field app:app];
    XCUIElement *count = app.staticTexts[@"chat.search.count"];
    if ([count waitForExistenceWithTimeout:8]) {
        NSLog(@"[im-uitest] 搜「%@」命中计数：%@", keyword, count.label);
    } else {
        NSLog(@"[im-uitest] 搜「%@」没有命中（这个账号可能看不到这几条测试消息，不影响本脚本要测的日历功能）", keyword);
    }
    [self attachScreenshotOf:app named:@"1-搜索态"];

    // ⑤ 点日历钮 → 弹层出现（UICalendarView + 最早/今天）
    XCUIElement *calBtn = app.buttons[@"chat.search.calendar"];
    XCTAssertTrue([calBtn waitForExistenceWithTimeout:10], @"没有 identifier 为 chat.search.calendar 的按钮");
    [calBtn tap];
    XCUIElement *earliestBtn = app.buttons[@"最早"];
    XCTAssertTrue([earliestBtn waitForExistenceWithTimeout:10], @"日历弹层没出现「最早」按钮");
    [self attachScreenshotOf:app named:@"2-日历弹层圆点"];   // 肉眼核对：有消息的日期下方应有圆点

    // ⑥ 点「最早」：弹层应关闭并跳转（先等 sheet 收起动画走完，再判「已不存在」，
    // 不用 waitForExistenceWithTimeout 的否定式——它一进来就命中已存在的元素，测不出「随后消失」）。
    [earliestBtn tap];
    [NSThread sleepForTimeInterval:1.5];
    XCTAssertFalse(earliestBtn.exists, @"点「最早」后日历弹层没有关闭");
    [self attachScreenshotOf:app named:@"3-点最早后落点"];

    // ⑦ 再开一次日历，点「今天」，同样应关闭
    XCTAssertTrue([calBtn waitForExistenceWithTimeout:10], @"「最早」跳转后日历钮消失了（是不是意外退出了搜索态？）");
    [calBtn tap];
    XCUIElement *todayBtn = app.buttons[@"今天"];
    XCTAssertTrue([todayBtn waitForExistenceWithTimeout:10], @"日历弹层没出现「今天」按钮");
    [todayBtn tap];
    [NSThread sleepForTimeInterval:1.5];
    XCTAssertFalse(todayBtn.exists, @"点「今天」后日历弹层没有关闭");
    [self attachScreenshotOf:app named:@"4-点今天后落点"];
}

@end
