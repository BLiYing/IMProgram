//  IMUploadPolicyS3aUITests.m
//  后台「系统设置」S3a（server-config 下发的上传策略：总开关 / 单文件上限 / 禁可执行文件）的**模拟器实测脚本**
//  ——不是常规回归，默认跳过。设计：../IMServer/docs/design/SYSTEM_SETTINGS_DESIGN.md。
//
//  前置（脚本不负责改后台值，每条用例跑之前先用管理端把策略调好）：
//    testA_UploadDisabled  ← sys.upload.enabled=0
//    testB_Cap1MB          ← sys.upload.enabled=1, sys.upload.max_file_bytes=1048576
//  模拟器相册最新的一张是小图（< 1 MB），其后是一段 > 1 MB 的视频（xcrun simctl addmedia booted …，先视频后图）；
//  已授权相册 / 麦克风（xcrun simctl privacy booted grant photos|microphone com.libeyond.IMProgram）。
//  吐司不进无障碍树：每一步截图挂进 .xcresult（KeepAlways），以截图为证。
//
//  跑法（每条用例单独跑，跑之前改好后台值）：
//    TEST_RUNNER_IM_S3A_UITEST=1 xcodebuild test -workspace IMProgram.xcworkspace -scheme IMProgram \
//      -destination 'id=<模拟器 UDID>' -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
//      -only-testing:IMProgramUITests/IMUploadPolicyS3aUITests/testA_UploadDisabled -resultBundlePath build/S3aUI.xcresult

#import <XCTest/XCTest.h>
#import "IMUITestLogin.h"

@interface IMUploadPolicyS3aUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation IMUploadPolicyS3aUITests

- (void)setUp {
    self.continueAfterFailure = YES;
    if (![NSProcessInfo.processInfo.environment[@"IM_S3A_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"需要本机开发后端与后台上传策略测试值，设 TEST_RUNNER_IM_S3A_UITEST=1 才跑");
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

- (void)dumpTree:(NSString *)name {
    XCTAttachment *a = [XCTAttachment attachmentWithString:self.app.debugDescription];
    a.name = name;
    a.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:a];
}

- (XCUIElement *)waitFor:(XCUIElement *)e named:(NSString *)name {
    if (![e waitForExistenceWithTimeout:15]) {
        [self shot:[NSString stringWithFormat:@"找不到-%@", name]];
        [self dumpTree:[NSString stringWithFormat:@"树-找不到-%@", name]];
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
    [NSThread sleepForTimeInterval:3.0]; // 等连上并拉到 server-config（上传策略）
}

- (void)openChatWith:(NSString *)name {
    [self.app.tabBars.buttons[@"消息"] tap];
    [[self waitFor:self.app.staticTexts[name].firstMatch named:name] tap];
    [NSThread sleepForTimeInterval:1.5];
}

/// 输入栏的按钮按 SF Symbol 默认无障碍名找（自绘输入栏没设 accessibilityLabel）。
- (XCUIElement *)inputBarButton:(NSArray<NSString *> *)labels {
    return [self.app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label IN %@ OR identifier IN %@", labels, labels]].firstMatch;
}

/// 聊天页 → 「+」→ 照片 → 自建相册选择器。
- (void)openPhotoPicker {
    XCUIElement *plus = [self inputBarButton:@[@"add", @"Add", @"plus.circle"]];
    [[self waitFor:plus named:@"输入栏 +"] tap];
    [NSThread sleepForTimeInterval:1.0];
    [self shot:@"附件面板"];
    XCUIElement *photo = self.app.buttons[@"photo"].firstMatch; // 面板项图标按钮（SF Symbol 名），文字「照片」不可点
    [[self waitFor:photo named:@"面板 照片"] tap];
    [NSThread sleepForTimeInterval:2.0];
    // 安装后首次进相册会弹系统授权（simctl privacy grant 会被重装冲掉）：在 SpringBoard 里点「允许完全访问」。
    XCUIApplication *sb = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.springboard"];
    XCUIElement *allow = [sb.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label IN %@",
                          @[@"Allow Full Access", @"允许完全访问"]]].firstMatch;
    if ([allow waitForExistenceWithTimeout:3]) { [allow tap]; [NSThread sleepForTimeInterval:2.0]; }
    [self waitFor:self.app.collectionViews.cells.firstMatch named:@"相册格子"];
    [NSThread sleepForTimeInterval:1.0];
}

- (XCUIElement *)pickerSendButton {
    return [self.app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label BEGINSWITH %@", @"发送"]].firstMatch;
}

/// 吐司约 2 秒：连拍三张。
- (void)burst:(NSString *)prefix {
    [NSThread sleepForTimeInterval:0.2];
    [self shot:[prefix stringByAppendingString:@"-a"]];
    [NSThread sleepForTimeInterval:0.5];
    [self shot:[prefix stringByAppendingString:@"-b"]];
    [NSThread sleepForTimeInterval:2.5];
    [self shot:[prefix stringByAppendingString:@"-c"]];
}

/// ① 总开关关：相册选一张小图发送 → 吐司「管理员已暂停发送文件」，不上屏新气泡；语音同样被拦。
- (void)testA_UploadDisabled {
    XCUIApplication *app = self.app;
    [self loginIfNeeded];
    [self openChatWith:@"用户1002"];
    [self shot:@"A01-单聊-发送前"];

    [self openPhotoPicker];
    // 基线在「附件面板开着」时取（选择器关掉后面板仍开着）：XCUITest 只数已加载的格子，表高一变数目就变。
    NSUInteger cellsBefore = app.tables.firstMatch.cells.count;
    [self shot:@"A02-相册选择器"];
    [app.collectionViews.cells.firstMatch tap]; // 最新的一张 = 小图
    [NSThread sleepForTimeInterval:0.6];
    [self shot:@"A03-选中1张"];
    [[self waitFor:[self pickerSendButton] named:@"选择器 发送"] tap];
    [self burst:@"A04-发送后吐司"];
    NSUInteger cellsAfter = app.tables.firstMatch.cells.count;
    XCTAssertEqual(cellsAfter, cellsBefore, @"上传已关：不应上屏新的图片气泡（前 %lu 后 %lu）",
                   (unsigned long)cellsBefore, (unsigned long)cellsAfter);

    // 语音（可选）：收起面板后按住话筒 2.5 秒松手。
    XCUIElement *plus = [self inputBarButton:@[@"add", @"Add", @"plus.circle"]];
    if (plus.exists && plus.isHittable) { [plus tap]; [NSThread sleepForTimeInterval:0.8]; } // 收起附件面板
    XCUIElement *mic = [self inputBarButton:@[@"waveform.circle", @"mic", @"Microphone"]];
    if (![mic waitForExistenceWithTimeout:3]) {
        [self dumpTree:@"A05-找不到话筒"];
        return;
    }
    [self shot:@"A05-语音前"];
    NSUInteger cellsBeforeVoice = app.tables.firstMatch.cells.count; // 面板已收起：重取基线
    [mic pressForDuration:2.5];
    [self burst:@"A06-语音松手后吐司"];
    XCTAssertEqual(app.tables.firstMatch.cells.count, cellsBeforeVoice, @"上传已关：语音也不应上屏");
}

/// ② 开关开 + 上限 1 MB：> 1 MB 的视频点不选（吐司「超过 1 MB」）；小图照常发出。
- (void)testB_Cap1MB {
    XCUIApplication *app = self.app;
    [self loginIfNeeded];
    [self openChatWith:@"用户1002"];
    [self shot:@"B01-单聊-发送前"];

    [self openPhotoPicker];
    [self shot:@"B02-相册选择器"];
    // 第二格 = > 1 MB 的视频：点它应被拒、不计入选择。
    XCUIElement *video = [app.collectionViews.cells elementBoundByIndex:1];
    [video tap];
    [self burst:@"B03-点超限视频"];
    XCUIElement *send = [self pickerSendButton];
    XCTAssertFalse([send.label containsString:@"(1)"], @"超限视频不应被选中（发送按钮「%@」）", send.label);

    // 第一格 = 小图：选中 → 发送(1)
    [app.collectionViews.cells.firstMatch tap];
    [NSThread sleepForTimeInterval:0.6];
    [self shot:@"B04-选中小图"];
    XCTAssertTrue([[self pickerSendButton].label containsString:@"(1)"], @"小图应可选（发送按钮「%@」）", [self pickerSendButton].label);
    [[self pickerSendButton] tap];
    [self burst:@"B05-小图发送后"];
    [NSThread sleepForTimeInterval:3.0];
    [self shot:@"B06-小图发送完成"];
}

/// 「+」→ 文件 → 「从文件中选择」→ 系统文件浏览器的「我的 iPhone」里点 fileName。
- (void)pickFromFiles:(NSString *)fileName prefix:(NSString *)prefix {
    XCUIApplication *app = self.app;
    XCUIElement *plus = [self inputBarButton:@[@"add", @"Add", @"plus.circle"]];
    [[self waitFor:plus named:@"输入栏 +"] tap];
    [NSThread sleepForTimeInterval:1.0];
    XCUIElement *file = [app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label IN %@ OR identifier IN %@",
                         @[@"document", @"doc", @"文件"], @[@"document", @"doc", @"文件"]]].firstMatch;
    [[self waitFor:file named:@"面板 文件"] tap];
    [NSThread sleepForTimeInterval:1.5];
    [[self waitFor:app.staticTexts[@"从文件中选择"].firstMatch named:@"从文件中选择"] tap];
    [NSThread sleepForTimeInterval:2.5];
    [self shot:[prefix stringByAppendingString:@"-系统文件浏览器"]];
    XCUIElement *target = [app.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", fileName]].firstMatch;
    if (![target waitForExistenceWithTimeout:4]) {
        // 不在当前目录：回到「浏览」→「我的 iPhone」
        XCUIElement *browse = [app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label IN %@", @[@"浏览", @"Browse"]]].firstMatch;
        if ([browse waitForExistenceWithTimeout:5]) { [browse tap]; [NSThread sleepForTimeInterval:1.5]; }
        [self dumpTree:[prefix stringByAppendingString:@"-树-浏览"]];
        XCUIElement *onPhone = [[app descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:[NSPredicate predicateWithFormat:@"label IN %@",
                                @[@"我的 iPhone", @"On My iPhone"]]].firstMatch;
        [[self waitFor:onPhone named:@"我的 iPhone"] tap];
        [NSThread sleepForTimeInterval:2.0];
        target = [app.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", fileName]].firstMatch;
    }
    [self shot:[prefix stringByAppendingString:@"-定位文件"]];
    [[self waitFor:target named:fileName] tap];
}

/// ③ 开关开 + 禁可执行文件：系统文件浏览器选 .apk → 吐司「管理员已禁止发送安装包和可执行文件」不上屏；.zip 照常发出。
/// 前置：sys.upload.block_executables=1；模拟器「文件」App「我的 iPhone」里放 s3a-test.apk 与 s3a-ok3.zip。
- (void)testC_BlockExecutables {
    XCUIApplication *app = self.app;
    [self loginIfNeeded];
    [self openChatWith:@"用户1002"];
    [self pickFromFiles:@"s3a-test.apk" prefix:@"C01"];
    [self burst:@"C02-apk吐司"];
    // 按文件名找气泡（不比格子数：XCUITest 只数已加载的格子，面板 / 键盘改变表高时数目会变）
    XCUIElement *apkBubble = [app.tables.firstMatch.staticTexts matchingPredicate:
                              [NSPredicate predicateWithFormat:@"label CONTAINS %@", @"s3a-test.apk"]].firstMatch;
    XCTAssertFalse(apkBubble.exists, @"被禁类型不应上屏");

    [self pickFromFiles:@"s3a-ok3.zip" prefix:@"C03"];
    [NSThread sleepForTimeInterval:4.0];
    [self shot:@"C04-zip发送后"];
    XCUIElement *zipBubble = [app.tables.firstMatch.staticTexts matchingPredicate:
                              [NSPredicate predicateWithFormat:@"label CONTAINS %@", @"s3a-ok3.zip"]].firstMatch;
    XCTAssertTrue(zipBubble.exists, @".zip 应正常发出");
}

@end
