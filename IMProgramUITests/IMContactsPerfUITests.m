//  IMContactsPerfUITests.m
//  通讯录 / 选好友页「大名单不卡」的**模拟器自测脚本**——不是常规回归，默认跳过。
//
//  它依赖本机 :8080 开发后端（`-dev-login`）和一个好友很多的账号（user1001 / user1002 各约 2000 人）；
//  App 已登录就直接用当前账号，停在登录页才免密登录 user1001。判据只看用户看得见的：
//  通讯录出好友行、来回切 Tab 后好友行仍在、选好友页出行且搜索能过滤。
//  切 Tab 每一下的耗时写进日志与附件——XCUITest 每次点击前后都会等 App 主线程空闲，主线程被占住会直接体现在这里。
//
//  ⚠️ 已知问题（2026-09-12 首跑）：对 2000 好友的账号会卡在 ① 的 `table.cells.count`——XCUITest 每查一次都给整棵无障碍树
//  拍快照，UITableView 把 2000 行全暴露出来，一次 30s+ 超时重试（App 本身不卡）。重跑前先把「数行数」换成
//  不查大表的判据（只点 Tab / 看标题），效果改看 contacts_index_applied / contacts_cache_persist 日志与截图。
//
//  跑法（在 IMProgram 仓里；环境变量经 TEST_RUNNER_ 前缀传给测试进程）：
//    TEST_RUNNER_IM_CONTACTS_UITEST=1 xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram \
//      -destination 'id=<模拟器 UDID>' -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
//      -only-testing:IMProgramUITests/IMContactsPerfUITests

#import <XCTest/XCTest.h>

@interface IMContactsPerfUITests : XCTestCase
@end

@implementation IMContactsPerfUITests

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (void)attachScreenshotOf:(XCUIApplication *)app named:(NSString *)name {
    XCTAttachment *shot = [XCTAttachment attachmentWithScreenshot:app.screenshot];
    shot.name = name;
    shot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:shot];
}

/// 底部 Tab：iOS 26 的液态 Tab 栏不一定以 tabBars 暴露，退到按 label 找按钮。
- (XCUIElement *)tabNamed:(NSString *)name app:(XCUIApplication *)app {
    XCUIElement *tab = app.tabBars.buttons[name];
    if (tab.exists) { return tab; }
    return [app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", name]].firstMatch;
}

/// 轮询表格可见行数，直到超过 minimum 或超时；返回最后一次看到的行数。
- (NSUInteger)waitForCellsIn:(XCUIElement *)table moreThan:(NSUInteger)minimum timeout:(NSTimeInterval)timeout {
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + timeout;
    NSUInteger count = table.cells.count;
    while (count <= minimum && CFAbsoluteTimeGetCurrent() < deadline) {
        [NSThread sleepForTimeInterval:0.3];
        count = table.cells.count;
    }
    return count;
}

/// 往输入框里打字，先确认真的拿到了键盘焦点（同 IMChatSearchPagingUITests 的教训）。
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

- (void)loginIfNeeded:(XCUIApplication *)app {
    XCUIElement *devLogin = app.buttons[@"免密登录（开发）"];
    if (![devLogin waitForExistenceWithTimeout:5]) { return; }
    XCUIElement *user = [app.textFields matchingPredicate:
        [NSPredicate predicateWithFormat:@"placeholderValue BEGINSWITH %@", @"用户名"]].firstMatch;
    XCTAssertTrue([user waitForExistenceWithTimeout:5]);
    [self typeText:@"user1001" into:user app:app];
    [devLogin tap];
}

- (void)test_通讯录大名单切Tab与选好友 {
    if (![NSProcessInfo.processInfo.environment[@"IM_CONTACTS_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"需要 :8080 开发后端与好友很多的账号，设 TEST_RUNNER_IM_CONTACTS_UITEST=1 才跑");
    }
    XCUIApplication *app = [XCUIApplication new];
    [app launch];
    [self loginIfNeeded:app];

    // ① 通讯录出好友行（入口区固定 4 行，多出来的才是好友）
    XCUIElement *contactsTab = [self tabNamed:@"通讯录" app:app];
    XCTAssertTrue([contactsTab waitForExistenceWithTimeout:30], @"找不到「通讯录」Tab");
    [contactsTab tap];
    XCUIElement *newFriends = app.staticTexts[@"新的朋友"];
    XCTAssertTrue([newFriends waitForExistenceWithTimeout:10]);
    XCUIElement *table = app.tables.firstMatch;
    NSUInteger cells = [self waitForCellsIn:table moreThan:4 timeout:15];
    [self attachScreenshotOf:app named:@"1-通讯录首屏"];
    XCTAssertGreaterThan(cells, 4, @"通讯录只有入口行、没有好友行");

    // ② 来回切 Tab，记录每一下的耗时
    NSMutableArray<NSString *> *timings = [NSMutableArray array];
    NSArray<NSString *> *order = @[ @"会话", @"通讯录", @"我", @"通讯录" ];
    for (NSInteger round = 0; round < 5; round++) {
        for (NSString *name in order) {
            XCUIElement *tab = [self tabNamed:name app:app];
            CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
            [tab tap];
            [timings addObject:[NSString stringWithFormat:@"r%ld %@ %.0fms", (long)round, name,
                                (CFAbsoluteTimeGetCurrent() - t0) * 1000]];
        }
    }
    NSLog(@"[im-uitest] tab_switch %@", [timings componentsJoinedByString:@" | "]);
    XCTAttachment *timingAttachment = [XCTAttachment attachmentWithString:[timings componentsJoinedByString:@"\n"]];
    timingAttachment.name = @"切 Tab 耗时";
    timingAttachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:timingAttachment];
    XCTAssertGreaterThan([self waitForCellsIn:app.tables.firstMatch moreThan:4 timeout:10], 4,
                         @"来回切 Tab 之后通讯录的好友行没了");
    [self attachScreenshotOf:app named:@"2-切完 Tab 回到通讯录"];

    // ③ 会话页右上 ＋ → 新建群聊 → 选好友页出行
    [[self tabNamed:@"会话" app:app] tap];
    XCUIElement *plus = nil;
    for (NSString *label in @[ @"Add", @"添加", @"plus", @"新建" ]) {
        XCUIElement *candidate = app.buttons[label];
        if ([candidate waitForExistenceWithTimeout:2]) { plus = candidate; break; }
    }
    if (!plus) {
        for (XCUIElement *b in app.buttons.allElementsBoundByIndex) {
            NSLog(@"[im-uitest] button label=%@ id=%@ frame=%@", b.label, b.identifier, NSStringFromCGRect(b.frame));
        }
        [self attachScreenshotOf:app named:@"找不到会话页右上加号"];
        XCTFail(@"会话页右上角的 ＋ 按钮找不到（候选 label 都没命中，见日志里的按钮清单）");
        return;
    }
    [plus tap];
    XCUIElement *newGroup = app.buttons[@"新建群聊"];
    if (![newGroup waitForExistenceWithTimeout:3]) { newGroup = app.staticTexts[@"新建群聊"]; }
    XCTAssertTrue([newGroup waitForExistenceWithTimeout:5], @"＋ 菜单里没有「新建群聊」");
    [newGroup tap];

    XCUIElement *pickerTable = app.tables.firstMatch;
    NSUInteger pickerCells = [self waitForCellsIn:pickerTable moreThan:0 timeout:15];
    [self attachScreenshotOf:app named:@"3-选好友页首屏"];
    XCTAssertGreaterThan(pickerCells, 0, @"选好友页没有出行");

    // ④ 取第一行的名字去搜：结果里必须还有这个人，且行数不多于搜索前
    NSString *keyword = [pickerTable.cells elementBoundByIndex:0].staticTexts.firstMatch.label;
    XCTAssertGreaterThan(keyword.length, 0);
    XCUIElement *field = app.searchFields.firstMatch;
    if (![field waitForExistenceWithTimeout:3]) {
        field = [app.textFields matchingPredicate:
                 [NSPredicate predicateWithFormat:@"placeholderValue CONTAINS %@", @"搜索"]].firstMatch;
    }
    XCTAssertTrue([field waitForExistenceWithTimeout:5], @"选好友页找不到搜索框");
    [self typeText:keyword into:field app:app];
    XCUIElement *hit = pickerTable.staticTexts[keyword];
    XCTAssertTrue([hit waitForExistenceWithTimeout:10], @"搜「%@」后结果里没有这个人", keyword);
    NSUInteger filtered = pickerTable.cells.count;
    NSLog(@"[im-uitest] picker keyword=%@ cells_before=%lu cells_after=%lu",
          keyword, (unsigned long)pickerCells, (unsigned long)filtered);
    [self attachScreenshotOf:app named:@"4-选好友页搜索后"];
    XCTAssertLessThanOrEqual(filtered, pickerCells);
}

@end
