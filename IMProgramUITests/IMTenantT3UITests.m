//  IMTenantT3UITests.m
//  集团（多租户）v2 T3 的**模拟器实测脚本**——不是常规回归，默认跳过。
//  设计：../im-spec/design/TENANT_DESIGN.md §8；交互稿 ../im-spec/design/sketches/TENANT_CLIENT_UX_SKETCH.html。
//
//  前置：本机开发后端在跑（-dev-login），并已造好「T3自测集团」（集团本部 / 华东子公司 / 华南子公司，
//  t3_hq 本部员工、t3_east_cs 华东客服、t3_east_dev 华东员工、t3_south_cs 华南客服、t3_cust 华东客户、t3_none 无集团）。
//  华南子公司的邀请码通过环境变量 TEST_RUNNER_IM_T3_SOUTH_CODE 传入（testC 用它绑第二家）。
//  每一步截图挂进 .xcresult（KeepAlways），吐司不进无障碍树、以截图为证。
//
//  跑法：
//    TEST_RUNNER_IM_T3_UITEST=1 TEST_RUNNER_IM_T3_SOUTH_CODE=<码> xcodebuild test -workspace IMProgram.xcworkspace \
//      -scheme IMProgram -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build/DerivedData \
//      -parallel-testing-enabled NO -only-testing:IMProgramUITests/IMTenantT3UITests -resultBundlePath build/T3UI.xcresult

#import <XCTest/XCTest.h>
#import "IMUITestLogin.h"

@interface IMTenantT3UITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation IMTenantT3UITests

- (void)setUp {
    self.continueAfterFailure = NO;
    if (![NSProcessInfo.processInfo.environment[@"IM_T3_UITEST"] isEqualToString:@"1"]) {
        XCTSkip(@"需要本机开发后端与 T3 测试数据，设 TEST_RUNNER_IM_T3_UITEST=1 才跑");
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

- (XCUIElement *)text:(NSString *)label {
    return [self.app.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", label]].firstMatch;
}

/// 列表行里的标题字（入口行 cell 的 label 会拼上右值，按 cell 找不稳，直接找字）。
- (XCUIElement *)cellWithText:(NSString *)label {
    return [self.app.tables.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", label]].firstMatch;
}

/// 已登录则从「设置」页退出，回到登录页。
- (void)logoutIfNeeded {
    XCUIElement *meTab = self.app.tabBars.buttons[@"设置"];
    if (![meTab waitForExistenceWithTimeout:6]) { return; }
    [self dismissNoticeIfPresent];
    [meTab tap];
    XCUIElement *logout = self.app.buttons[@"退出登录"].firstMatch;
    if (!logout.exists) { logout = self.app.staticTexts[@"退出登录"].firstMatch; }
    for (NSInteger i = 0; i < 6 && !(logout.exists && logout.isHittable); i++) { [self.app swipeUp]; }
    [[self waitFor:logout named:@"退出登录"] tap];
    // 有确认框就点；没有（直接退出）也行，以回到登录页为准。
    XCUIElement *confirm = self.app.alerts.buttons[@"退出登录"].firstMatch;
    if (![confirm waitForExistenceWithTimeout:3]) { confirm = [self.app.sheets.buttons matchingIdentifier:@"退出登录"].firstMatch; }
    if (confirm.exists) { [confirm tap]; }
    [self waitFor:IMUITestLoginLogo(self.app) named:@"登录页"];
}

- (void)loginAs:(NSString *)username {
    [self logoutIfNeeded];
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
}

/// 审计告知弹窗（后台添加的成员首次进主界面）：有就截图并点「我知道了」。
- (BOOL)dismissNoticeIfPresent {
    XCUIElement *ok = self.app.alerts.buttons[@"我知道了"].firstMatch;
    if (![ok waitForExistenceWithTimeout:4]) { return NO; }
    [self shot:@"审计告知"];
    [ok tap];
    return YES;
}

- (void)openOrgDirectory {
    [self.app.tabBars.buttons[@"通讯录"] tap];
    XCUIElement *entry = [self cellWithText:@"组织架构"];
    [[self waitFor:entry named:@"组织架构入口"] tap];
}

/// A：本部员工——审计告知、单位列表、华东 ▸ 客服部、客服小标、资料页。
- (void)testA_StaffBrowsesDirectory {
    [self loginAs:@"t3_hq"];
    [self dismissNoticeIfPresent]; // 后台添加的成员：首次弹一次
    [self.app.tabBars.buttons[@"通讯录"] tap];
    [self shot:@"A01-通讯录首页"];
    [self openOrgDirectory];
    [self waitFor:[self text:@"华东子公司"] named:@"单位列表-华东"];
    XCTAssertTrue([self text:@"集团本部"].exists);
    XCTAssertTrue([self text:@"华南子公司"].exists);
    [self shot:@"A02-单位列表"];
    [[self text:@"华东子公司"] tap];
    [[self waitFor:[self text:@"客服部"] named:@"华东-客服部"] tap];
    [self waitFor:[self text:@"t3_east_cs"] named:@"客服成员"];
    XCTAssertTrue([self text:@"客服"].exists, @"客服小标");
    [self shot:@"A03-客服部"];
    [[self text:@"t3_east_cs"] tap];
    [NSThread sleepForTimeInterval:1.5];
    [self shot:@"A04-客服资料页"];
}

/// B：客户——只看到所绑子公司的客服，免好友直聊发消息；我的集团页。
- (void)testB_CustomerDirectChat {
    [self loginAs:@"t3_cust"];
    [self openOrgDirectory];
    // 只绑一家：直接是华东顶层；testC 绑过华南后是两家：先出单位列表（只有所绑的两家，没有本部）。
    if ([[self text:@"华南子公司"] waitForExistenceWithTimeout:4]) {
        XCTAssertFalse([self text:@"集团本部"].exists, @"客户看不到本部");
        [self shot:@"B00-客户单位列表"];
        [[self text:@"华东子公司"] tap];
    }
    [self waitFor:[self text:@"客服部"] named:@"客户视角-客服部"];
    XCTAssertFalse([self text:@"技术部"].exists, @"客户看不到不含客服的部门");
    [self shot:@"B01-客户视角顶层"];
    [[self text:@"客服部"] tap];
    [[self waitFor:[self text:@"t3_east_cs"] named:@"客服"] tap];
    XCUIElement *msg = self.app.buttons[@"消息"].firstMatch;
    [self waitFor:msg named:@"免好友直聊-消息"];
    // 免好友直聊与好友同等（2026-11-22）：搜索 / 更多 / 备注名都在
    for (NSString *t in @[@"搜索", @"更多"]) { XCTAssertTrue(self.app.buttons[t].firstMatch.exists, @"免好友直聊应有 %@", t); }
    XCTAssertTrue([self text:@"备注名"].exists, @"免好友直聊应有备注名");
    [self shot:@"B02-客服资料页（直聊）"];
    [self.app.buttons[@"更多"].firstMatch tap];
    [self waitFor:[self text:@"加好友"] named:@"更多里的加好友"];
    XCTAssertFalse([self text:@"删除好友"].exists, @"不是好友没有删除好友");
    [self shot:@"B02b-更多菜单（直聊）"];
    [[self.app coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.15)] tap]; // 点空白收起菜单
    [msg tap];
    XCUIElement *input = [self waitFor:self.app.textViews.firstMatch named:@"输入框"];
    [input tap];
    [input typeText:@"T3 客户你好"];
    NSArray *names = @[@"发送", @"Send", @"arrow.up.circle.fill", @"arrow.up"];
    XCUIElement *send = [self.app.buttons matchingPredicate:
                         [NSPredicate predicateWithFormat:@"label IN %@ OR identifier IN %@", names, names]].firstMatch;
    if ([send waitForExistenceWithTimeout:2]) { [send tap]; } else { [input typeText:@"\n"]; }
    [NSThread sleepForTimeInterval:2];
    [self shot:@"B03-直聊已发送"];
}

/// C：客户在「设置 ▸ 填写邀请码」绑第二家（错码红字 → 正确码成功）；页里列「已绑定 · 集团名」。
- (void)testC_CustomerRedeemsSecondUnit {
    NSString *code = NSProcessInfo.processInfo.environment[@"IM_T3_SOUTH_CODE"];
    [self loginAs:@"t3_cust"];
    [self.app.tabBars.buttons[@"设置"] tap];
    [[self waitFor:[self cellWithText:@"填写邀请码"] named:@"填写邀请码入口"] tap];
    [self waitFor:[self text:@"华东子公司"] named:@"已绑华东"];
    XCUIElement *field = [self waitFor:self.app.textFields[@"org.invite.field"] named:@"邀请码框"];
    [field tap];
    [field typeText:@"BADCODE1"];
    [self.app.buttons[@"org.invite.join"] tap];
    [NSThread sleepForTimeInterval:1.5];
    [self shot:@"C01-错码红字"];
    if (code.length == 0) { return; }
    [field tap];
    [field typeText:[@"" stringByPaddingToLength:12 withString:XCUIKeyboardKeyDelete startingAtIndex:0]];
    [field typeText:code];
    [self.app.buttons[@"org.invite.join"] tap];
    [self waitFor:[self text:@"华南子公司"] named:@"绑上华南"];
    [self shot:@"C02-绑定第二家"];
}

/// D：无集团（存量账号 2026-11-22 已全部迁入集团，这里用一个新注册的账号，默认 t3_fresh1；
/// 重跑可用 TEST_RUNNER_IM_T3_NONE_USER 换）——通讯录同样叫「组织架构」，点进是空态 →「填写邀请码」页（只有填码段）。
- (void)testD_NoTenantJoinEntry {
    [self loginAs:NSProcessInfo.processInfo.environment[@"IM_T3_NONE_USER"] ?: @"t3_fresh1"];
    [self.app.tabBars.buttons[@"通讯录"] tap];
    XCUIElement *org = [self cellWithText:@"组织架构"];
    [self waitFor:org named:@"组织架构入口"];
    XCTAssertFalse([self cellWithText:@"填写邀请码加入企业"].exists);
    [self shot:@"D01-无集团通讯录"];
    [org tap];
    [self waitFor:[self text:@"你还没有加入企业"] named:@"空态标题"];
    [self shot:@"D02-组织架构空态"];
    [self.app.buttons[@"org.join.invite"] tap];
    [self waitFor:self.app.textFields[@"org.invite.field"] named:@"邀请码框"];
    XCTAssertFalse([self text:@"加入后，该集团的管理员可以查看你在本集团内的聊天记录（本集团的群聊，以及你和本集团成员之间的单聊）。"].exists,
                   @"审计小字已暂停");
    [self shot:@"D03-填写邀请码（无集团）"];
    // 二级页隐藏底栏：先退回通讯录根页（填写邀请码 → 空态 → 通讯录）
    for (int i = 0; i < 2; i++) { [[self waitFor:self.app.buttons[@"返回"] named:@"返回"] tap]; [NSThread sleepForTimeInterval:0.8]; }
    [[self waitFor:self.app.tabBars.buttons[@"设置"] named:@"底栏"] tap];
    [self waitFor:[self cellWithText:@"填写邀请码"] named:@"设置页填写邀请码行"];
}

/// E：直聊关闭（跑之前用后台把 t3_east_cs 改成普通员工）→ 客户那边的会话输入栏只读「对方已不再为你提供服务」。
- (void)testE_ServiceEndedReadOnly {
    [self loginAs:@"t3_cust"];
    [self.app.tabBars.buttons[@"消息"] tap];
    [NSThread sleepForTimeInterval:2]; // 会话列表拉一次：peer_direct_chat 由有变无
    [[self waitFor:[self text:@"t3_east_cs"] named:@"客服会话"] tap];
    NSString *hint = @"不再为你提供服务";
    XCUIElement *locked = [[self.app descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:
                           [NSPredicate predicateWithFormat:@"label CONTAINS %@ OR placeholderValue CONTAINS %@ OR value CONTAINS %@",
                            hint, hint, hint]].firstMatch;
    BOOL ok = [locked waitForExistenceWithTimeout:6];
    [self shot:@"E01-直聊关闭只读"];
    XCTAssertTrue(ok, @"输入栏应只读并提示对方已不再为你提供服务");
}

/// F：后台添加的员工首次进主界面弹审计告知（默认 t3_east_dev；告知只弹一次，重跑时用 TEST_RUNNER_IM_T3_NOTICE_USER 换一个刚由后台添加的账号）；点「我知道了」后服务端 notice_pending 清掉（脚本外核对）。
- (void)testF_AuditNoticeOnce {
    // 2026-11-22 起审计告知暂停（客户端注释，服务端 notice_pending 保留）；恢复弹窗时删掉这一行。
    XCTSkip(@"审计告知暂停");
    [self logoutIfNeeded];
    XCTAssertTrue(IMUITestShowPasswordLogin(self.app, 15));
    XCUIElement *user = [self waitFor:self.app.textFields.firstMatch named:@"用户名"];
    [user tap];
    NSString *cur = [user.value isKindOfClass:NSString.class] ? user.value : @"";
    if (cur.length > 0 && ![cur isEqualToString:user.placeholderValue]) {
        [user typeText:[@"" stringByPaddingToLength:cur.length + 4 withString:XCUIKeyboardKeyDelete startingAtIndex:0]];
    }
    NSString *who = NSProcessInfo.processInfo.environment[@"IM_T3_NOTICE_USER"] ?: @"t3_east_dev";
    [user typeText:who];
    [self.app.buttons[@"免密登录（开发）"] tap];
    XCUIElement *title = [self.app.alerts.staticTexts matchingPredicate:
                          [NSPredicate predicateWithFormat:@"label == %@", @"你已加入「T3自测集团」"]].firstMatch;
    [self waitFor:title named:@"审计告知标题"];
    [self shot:@"F01-审计告知"];
    [self.app.alerts.buttons[@"我知道了"] tap];
    [NSThread sleepForTimeInterval:1.5];
    XCTAssertFalse(self.app.alerts.firstMatch.exists, @"只弹一次");
}

/// G：员工的设置页没有「填写邀请码」（员工不需要填码）；底部 Tab 叫「设置」。
- (void)testG_StaffHasNoInviteRow {
    [self loginAs:@"t3_east_dev"];
    [self.app.tabBars.buttons[@"设置"] tap];
    [self waitFor:[self cellWithText:@"关于我们"] named:@"设置页"];
    XCTAssertFalse([self cellWithText:@"填写邀请码"].exists, @"员工不显示填写邀请码");
    XCTAssertFalse([self cellWithText:@"我的集团"].exists);
    [self shot:@"G01-员工设置页"];
}

/// H：在线客服多公司（BEACON_CS_DESIGN §2.2）——客户绑了华东 + 华南且链接不同：「在线客服」先选公司，选华东打开其 Beacon 访客页、标题为公司名。
- (void)testH_CustomerPicksCompanyForOnlineService {
    [self loginAs:@"t3_cust"];
    [self dismissNoticeIfPresent];
    [self.app.tabBars.buttons[@"设置"] tap];
    XCUIElement *about = [self cellWithText:@"关于我们"];
    for (NSInteger i = 0; i < 6 && !(about.exists && about.isHittable); i++) { [self.app swipeUp]; }
    [[self waitFor:about named:@"关于我们"] tap];
    [[self waitFor:[self cellWithText:@"在线客服"] named:@"在线客服行"] tap];
    XCUIElement *east = self.app.sheets.buttons[@"华东子公司"].firstMatch;
    if (![east waitForExistenceWithTimeout:5]) { east = self.app.buttons[@"华东子公司"].firstMatch; }
    [self waitFor:east named:@"选公司-华东"];
    XCTAssertTrue(self.app.buttons[@"华南子公司"].firstMatch.exists, @"应同时列出华南子公司");
    [self shot:@"H01-选择要咨询的公司"];
    [east tap];
    [self waitFor:[self.app.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", @"华东子公司"]].firstMatch named:@"客服页标题=公司名"];
    // 等 Beacon 访客页加载（模拟器上首屏较慢）：等到出现输入框，最多 40 秒
    [self.app.webViews.textFields.firstMatch waitForExistenceWithTimeout:40];
    [self shot:@"H02-华东访客页"];
}

@end

