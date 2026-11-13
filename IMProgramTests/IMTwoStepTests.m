//  IMTwoStepTests.m
//  两步验证（TOTP + 恢复码）：纯规则（清洗 / 归一化 / 分组 / 错误码文案 / 状态页行 / leave 拦截）、REST（200020 保留 ticket、
//  200021 attempts_left、二步登录成功收尾）、日志脱敏、系统通知渲染、设置搜索登记、各页状态。app-hosted；HTTP 用 NSURLProtocol 桩。

#import <XCTest/XCTest.h>

#import "IMTwoStep.h"
#import "IMLocalization.h"
#import "IMSysEventFormatter.h"
#import "IMHTTPLogFormatter.h"
#import "IMHTTPService.h"
#import "IMHTTPService+TwoStep.h"
#import "IMTwoStepViewController.h"
#import "IMTwoStepBindViewController.h"
#import "IMTwoStepCodesViewController.h"
#import "IMTwoStepVerifyViewController.h"
#import "IMLoginTwoStepView.h"
#import "IMLoginViewController.h"
#import "IMPrivacySecurityViewController.h"
#import "IMSettingsSearchRegistry.h"
#import "IMSettingsRouter.h"

#pragma mark - HTTP 桩

@interface IMTwoStepStub : NSURLProtocol
@property (class, nonatomic, copy) NSDictionary *response;
@property (class, nonatomic, assign) NSInteger status;
@property (class, nonatomic, copy) NSString *lastPath;
@property (class, nonatomic, copy) NSDictionary *lastBody;
@end
@implementation IMTwoStepStub
static NSDictionary *sResp; static NSInteger sStatus; static NSString *sPath; static NSDictionary *sBody;
+ (NSDictionary *)response { return sResp; }
+ (void)setResponse:(NSDictionary *)v { sResp = v; }
+ (NSInteger)status { return sStatus; }
+ (void)setStatus:(NSInteger)v { sStatus = v; }
+ (NSString *)lastPath { return sPath; }
+ (void)setLastPath:(NSString *)v { sPath = v; }
+ (NSDictionary *)lastBody { return sBody; }
+ (void)setLastBody:(NSDictionary *)v { sBody = v; }
+ (BOOL)canInitWithRequest:(NSURLRequest *)r {
    NSString *p = r.URL.path;
    return [p isEqualToString:@"/api/v1/login"] || [p isEqualToString:@"/api/v1/login/two-step"] || [p hasPrefix:@"/api/v1/users/me/two-step"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    sPath = self.request.URL.path;
    NSData *body = self.request.HTTPBody;
    if (!body && self.request.HTTPBodyStream) {
        NSInputStream *in = self.request.HTTPBodyStream;
        NSMutableData *buf = [NSMutableData data];
        uint8_t tmp[1024];
        [in open];
        NSInteger n;
        while ((n = [in read:tmp maxLength:sizeof tmp]) > 0) { [buf appendBytes:tmp length:(NSUInteger)n]; }
        [in close];
        body = buf;
    }
    id obj = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
    sBody = [obj isKindOfClass:NSDictionary.class] ? obj : nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:sResp ?: @{ @"code": @0, @"data": @{} } options:0 error:NULL];
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:sStatus ?: 200 HTTPVersion:@"HTTP/1.1"
                                                     headerFields:@{ @"Content-Type": @"application/json" }];
    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

#pragma mark - 页面私有成员（运行时访问，不改生产可见性）

@interface IMLoginViewController (TwoStepTestAccess)
- (void)beginTwoStepWithTicket:(NSString *)ticket host:(NSString *)host tab:(NSInteger)tab;
- (void)leaveSubpage;
- (void)handleTwoStepFailure:(NSError *)error recovery:(BOOL)recovery;
@end
@interface IMTwoStepCodesViewController (TestAccess)
- (void)toggleSaved;
@end
@interface IMTwoStepBindViewController (TestAccess)
- (void)toggleManual;
@end
@interface IMTwoStepVerifyViewController (TestAccess)
- (BOOL)textField:(UITextField *)tf shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
- (void)toggleMethod;
@end

@interface IMLoginTwoStepView (TestAccess)
- (BOOL)textField:(UITextField *)tf shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
@end

@interface IMTwoStepTests : XCTestCase
@end

@implementation IMTwoStepTests {
    NSString *_savedHost;
}

- (void)setUp {
    [super setUp];
    [IMLocalization.shared setPreference:IMLanguagePrefZhHans];
    _savedHost = IMHTTPService.sharedService.host;
    IMHTTPService.sharedService.host = @"127.0.0.1:59392";
    sResp = nil; sStatus = 0; sPath = nil; sBody = nil;
    [NSURLProtocol registerClass:IMTwoStepStub.class];
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:IMTwoStepStub.class];
    [IMHTTPService.sharedService invalidateToken];
    IMHTTPService.sharedService.password = nil;
    IMHTTPService.sharedService.host = _savedHost;
    [IMLocalization.shared setPreference:IMLanguagePrefZhHans];
    [super tearDown];
}

#pragma mark - 6 位清洗

- (void)test_清洗_粘贴带空格与分隔符 {
    XCTAssertEqualObjects(IMTwoStepSanitizeCode(@"123 456"), @"123456");
    XCTAssertEqualObjects(IMTwoStepSanitizeCode(@"12-34-56"), @"123456");
    XCTAssertEqualObjects(IMTwoStepSanitizeCode(@" 123\n456 "), @"123456");
}
- (void)test_清洗_过滤非数字_截6位_全角数字 {
    XCTAssertEqualObjects(IMTwoStepSanitizeCode(@"a1b2c3"), @"123");
    XCTAssertEqualObjects(IMTwoStepSanitizeCode(@"1234567890"), @"123456");
    XCTAssertEqualObjects(IMTwoStepSanitizeCode(@"１２３４５６"), @"123456");
    XCTAssertEqualObjects(IMTwoStepSanitizeCode(@"٣٤"), @"", @"阿拉伯数字不接受");
    XCTAssertEqualObjects(IMTwoStepSanitizeCode(nil), @"");
    XCTAssertEqualObjects(IMTwoStepSanitizeCode(@"12😀34"), @"1234");
}
- (void)test_满6位判定 {
    XCTAssertTrue(IMTwoStepCodeIsComplete(@"123456"));
    XCTAssertFalse(IMTwoStepCodeIsComplete(@"12345"));
    XCTAssertFalse(IMTwoStepCodeIsComplete(@"12345a"));
    XCTAssertFalse(IMTwoStepCodeIsComplete(@"1234567"));
    XCTAssertFalse(IMTwoStepCodeIsComplete(nil));
}

#pragma mark - 恢复码

- (void)test_恢复码归一化_大小写连字符空格 {
    XCTAssertEqualObjects(IMTwoStepNormalizeRecovery(@"K7M2Q-9XW3P"), @"k7m2q9xw3p");
    XCTAssertEqualObjects(IMTwoStepNormalizeRecovery(@" k7m2q 9xw3p\n"), @"k7m2q9xw3p");
    XCTAssertEqualObjects(IMTwoStepNormalizeRecovery(@"k7m2q–9xw3p"), @"k7m2q9xw3p", @"粘贴自富文本的长破折号");
    XCTAssertEqualObjects(IMTwoStepNormalizeRecovery(nil), @"");
    XCTAssertTrue(IMTwoStepRecoveryIsComplete(@"K7M2Q-9XW3P"));
    XCTAssertFalse(IMTwoStepRecoveryIsComplete(@"K7M2Q-9XW3"));
    XCTAssertFalse(IMTwoStepRecoveryIsComplete(@"K7M2Q-9XW3PX"));
}
- (void)test_恢复码框_只拒超长_组词期间放行 {
    NSString *twelve = @"k7m2q-9xw3p-1"; // 13 字符
    XCTAssertEqual(twelve.length, 13u);
    XCTAssertTrue(IMTwoStepRecoveryAllowsEdit(@"k7m2q-9xw3p", NSMakeRange(11, 0), @"1", NO), @"12 字符放行");
    XCTAssertFalse(IMTwoStepRecoveryAllowsEdit(@"k7m2q-9xw3p1", NSMakeRange(12, 0), @"2", NO), @"第 13 个字符拒绝");
    XCTAssertTrue(IMTwoStepRecoveryAllowsEdit(@"k7m2q-9xw3p1", NSMakeRange(0, 1), @"", NO), @"删除永远放行");
    XCTAssertFalse(IMTwoStepRecoveryAllowsEdit(@"", NSMakeRange(0, 0), @"aaaaaaaaaaaaa", NO), @"粘贴超长拒绝");
    XCTAssertTrue(IMTwoStepRecoveryAllowsEdit(@"k7m2q-9xw3p1", NSMakeRange(12, 0), @"zhong", YES), @"输入法组词期间不干预");
}

- (void)test_粘贴提取恢复码 {
    XCTAssertEqualObjects(IMTwoStepExtractRecoveryCode(@"k7m2q-9xw3p"), @"k7m2q9xw3p");
    XCTAssertEqualObjects(IMTwoStepExtractRecoveryCode(@"K7M2Q 9XW3P"), @"k7m2q9xw3p");
    XCTAssertEqualObjects(IMTwoStepExtractRecoveryCode(@"k7m2q9xw3p"), @"k7m2q9xw3p");
    XCTAssertEqualObjects(IMTwoStepExtractRecoveryCode(@"  1. k7m2q-9xw3p\n"), @"k7m2q9xw3p", @"序号前缀");
    XCTAssertEqualObjects(IMTwoStepExtractRecoveryCode(@"恢复码：k7m2q\u20139xw3p"), @"k7m2q9xw3p", @"中文前缀 + 长破折号");
    NSString *all = IMTwoStepRecoveryClipboardText(@[@"aaaaa-bbbbb", @"ccccc-ddddd", @"eeeee-fffff"]);
    XCTAssertEqualObjects(IMTwoStepExtractRecoveryCode(all), @"aaaaabbbbb", @"整份清单取第一个");
    XCTAssertNil(IMTwoStepExtractRecoveryCode(@"hello world"));
    XCTAssertNil(IMTwoStepExtractRecoveryCode(@"k7m2q-9xw3"), @"不足 10 位");
    XCTAssertNil(IMTwoStepExtractRecoveryCode(@"k7m2q-0xw3p"), @"含字符集外的 0");
    XCTAssertNil(IMTwoStepExtractRecoveryCode(@"k7m2q9xw3pzz"), @"不从更长的词里截");
    XCTAssertNil(IMTwoStepExtractRecoveryCode(nil));
    XCTAssertEqualObjects(IMTwoStepFormatRecovery(@"k7m2q9xw3p"), @"k7m2q-9xw3p");
}
- (void)test_粘贴判定 {
    XCTAssertTrue(IMTwoStepEditLooksLikePaste(@"", NSMakeRange(0, 0), @"ab"));
    XCTAssertTrue(IMTwoStepEditLooksLikePaste(@"", NSMakeRange(0, 0), @"\n"));
    XCTAssertTrue(IMTwoStepEditLooksLikePaste(@"k7m2q-9xw3p", NSMakeRange(11, 0), @"x") == NO);
    XCTAssertTrue(IMTwoStepEditLooksLikePaste(@"k7m2q-9xw3p1", NSMakeRange(12, 0), @"x"), @"会超长");
    XCTAssertFalse(IMTwoStepEditLooksLikePaste(@"abc", NSMakeRange(3, 0), @"d"));
}
- (void)test_恢复码框粘贴整份清单_替换为第一个码 {
    IMTwoStepVerifyViewController *vc = [[IMTwoStepVerifyViewController alloc] initWithHost:@"h" userID:@"u1" mode:IMTwoStepVerifyModeDisable];
    [vc loadViewIfNeeded];
    [vc toggleMethod];
    UITextField *rec = [vc valueForKey:@"recoveryField"];
    NSString *list = @"1. aaaaa-bbbbb\n2. ccccc-ddddd\n3. eeeee-fffff\n";
    BOOL allowed = [vc textField:rec shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:list];
    XCTAssertFalse(allowed, @"已由我们替换，系统不再插入原文");
    XCTAssertEqualObjects(rec.text, @"aaaaa-bbbbb");
    XCTAssertTrue(vc.primaryButton.enabled, @"粘贴后触发 EditingChanged，按钮可用（身份确认在弹层里，页面上没有密码框）");
    // 提取不到：仍按原规则拒超长
    rec.text = @"";
    XCTAssertFalse([vc textField:rec shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@"zzzzzzzzzzzzzzzzzzzz"]);
    XCTAssertEqualObjects(rec.text, @"");
}
- (void)test_登录二步页恢复码框粘贴 {
    IMLoginTwoStepView *v = [IMLoginTwoStepView new];
    [[v valueForKey:@"toggleButton"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    BOOL allowed = [v textField:v.recoveryField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@"恢复码: K7M2Q-9XW3P\n"];
    XCTAssertFalse(allowed);
    XCTAssertEqualObjects(v.recoveryField.text, @"k7m2q-9xw3p");
}

#pragma mark - 分组展示

- (void)test_密钥4位一组 {
    XCTAssertEqualObjects(IMTwoStepGroupSecret(@"JBSWY3DPEHPK3PXP", 4, 0), @"JBSW Y3DP EHPK 3PXP");
    XCTAssertEqualObjects(IMTwoStepGroupSecret(@"JBSWY3DPEHPK3PXP", 4, 2), @"JBSW Y3DP\nEHPK 3PXP");
    XCTAssertEqualObjects(IMTwoStepGroupSecret(@"JBSWY3DPEH", 4, 0), @"JBSW Y3DP EH", @"尾组不足 4 位");
    XCTAssertEqualObjects(IMTwoStepGroupSecret(@"JBSW Y3DP-EHPK", 4, 0), @"JBSW Y3DP EHPK", @"已有分隔先去掉");
    XCTAssertEqualObjects(IMTwoStepGroupSecret(nil, 4, 4), @"");
    NSString *full = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"; // 20 字节 → 32 位 Base32
    NSString *grouped = IMTwoStepGroupSecret(full, 4, 4);
    XCTAssertEqual([grouped componentsSeparatedByString:@"\n"].count, 2u);
    XCTAssertEqualObjects([[grouped stringByReplacingOccurrencesOfString:@" " withString:@""] stringByReplacingOccurrencesOfString:@"\n" withString:@""], full);
}

#pragma mark - 状态页行 / 隐私页行

- (void)test_恢复码剩余_橙色阈值与footer {
    XCTAssertFalse(IMTwoStepRecoveryIsLow(3));
    XCTAssertTrue(IMTwoStepRecoveryIsLow(2));
    XCTAssertTrue(IMTwoStepRecoveryIsLow(0));
    XCTAssertFalse(IMTwoStepRecoveryIsLow(-1), @"服务端没给不当成低");
    XCTAssertNil(IMTwoStepRecoveryFooter(8));
    XCTAssertEqualObjects(IMTwoStepRecoveryFooter(2), IMLocalized(@"twostep.recovery.low_footer"));
    XCTAssertEqualObjects(IMTwoStepRecoveryRemainingText(8), @"剩余 8 个");
    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    XCTAssertEqualObjects(IMTwoStepRecoveryRemainingText(8), @"8 left");
}
- (void)test_隐私页行右值_加载前留空 {
    XCTAssertNil(IMTwoStepRowValueText(nil));
    XCTAssertEqualObjects(IMTwoStepRowValueText(@YES), @"开启");
    XCTAssertEqualObjects(IMTwoStepRowValueText(@NO), @"关闭");
}
- (void)test_状态解析 {
    IMTwoStepState *off = [IMTwoStepState stateFromJSON:@{ @"enabled": @NO }];
    XCTAssertFalse(off.enabled); XCTAssertNil(off.enabledAt); XCTAssertEqual(off.recoveryRemaining, -1);
    XCTAssertNil([off enabledSinceText]);
    IMTwoStepState *on = [IMTwoStepState stateFromJSON:@{ @"enabled": @YES, @"enabled_at": @1761696000000, @"recovery_remaining": @7 }];
    XCTAssertTrue(on.enabled); XCTAssertEqual(on.recoveryRemaining, 7);
    XCTAssertEqualWithAccuracy(on.enabledAt.timeIntervalSince1970, 1761696000, 1);
    XCTAssertTrue([[on enabledSinceText] hasSuffix:@"开启"]);
    XCTAssertNil([IMTwoStepState stateFromJSON:nil]);
    XCTAssertNil([IMTwoStepState stateFromJSON:@[@1]]);
}
- (void)test_恢复码文件与剪贴板正文 {
    NSArray *codes = @[@"aaaaa-bbbbb", @"ccccc-ddddd"];
    XCTAssertEqualObjects(IMTwoStepRecoveryClipboardText(codes), @"aaaaa-bbbbb\nccccc-ddddd");
    NSString *file = IMTwoStepRecoveryFileText(codes);
    XCTAssertTrue([file hasPrefix:IMLocalized(@"twostep.codes.file_header")]);
    XCTAssertTrue([file hasSuffix:@"aaaaa-bbbbb\nccccc-ddddd\n"]);
    XCTAssertEqualObjects(IMTwoStepParseRecoveryCodes(@[@"a", @1, @"", NSNull.null, @"b"]), (@[@"a", @"b"]));
    XCTAssertEqual(IMTwoStepParseRecoveryCodes(nil).count, 0u);
}

#pragma mark - 错误码 → 文案

- (void)test_错误文案_登录第二步_剩余次数 {
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200021, IMTwoStepErrorContextLogin, 2, NO, @"x"), @"验证码不正确，还可尝试 2 次");
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200021, IMTwoStepErrorContextLogin, 1, NO, @"x"), @"验证码不正确，还可尝试 1 次");
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200021, IMTwoStepErrorContextLogin, 3, NO, @"x"), @"验证码不正确", @">2 次不提示剩余");
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200021, IMTwoStepErrorContextLogin, -1, NO, @"x"), @"验证码不正确", @"服务端没给");
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200021, IMTwoStepErrorContextLogin, 0, NO, @"x"), @"验证码不正确");
}
- (void)test_错误文案_各上下文 {
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200021, IMTwoStepErrorContextBind, -1, NO, @"x"), IMLocalized(@"twostep.error.code_invalid"));
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200021, IMTwoStepErrorContextManage, 2, NO, @"x"), IMLocalized(@"twostep.error.code_invalid"));
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200022, IMTwoStepErrorContextLogin, -1, NO, @"x"), @"已超时，请重新登录");
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200022, IMTwoStepErrorContextBind, -1, NO, @"x"), @"已超时，请重新开始");
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200002, IMTwoStepErrorContextPassword, -1, NO, @"x"), @"密码不正确");
    XCTAssertEqualObjects(IMTwoStepErrorMessage(100002, IMTwoStepErrorContextLogin, -1, NO, @"x"), @"尝试次数过多，请稍后再试");
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200023, IMTwoStepErrorContextManage, -1, NO, @"x"), IMLocalized(@"twostep.error.not_enabled"));
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200024, IMTwoStepErrorContextPassword, -1, NO, @"x"), IMLocalized(@"twostep.error.already_enabled"));
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200025, IMTwoStepErrorContextPassword, -1, NO, @"x"), IMLocalized(@"twostep.error.unavailable"));
    XCTAssertEqualObjects(IMTwoStepErrorMessage(500000, IMTwoStepErrorContextLogin, -1, NO, @"兜底"), @"兜底");
    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200021, IMTwoStepErrorContextLogin, 2, NO, @"x"), @"Incorrect code. 2 attempts left.");
}
- (void)test_错误文案_刚开启后追加等待提示 {
    NSString *base = IMLocalized(@"twostep.error.code_invalid_short");
    NSString *hint = IMLocalized(@"twostep.bind.wait_next");
    XCTAssertEqualObjects(IMTwoStepErrorMessage(200021, IMTwoStepErrorContextLogin, -1, YES, @"x"),
                          ([NSString stringWithFormat:@"%@\n%@", base, hint]));
    XCTAssertFalse([IMTwoStepErrorMessage(200021, IMTwoStepErrorContextBind, -1, YES, @"x") containsString:hint], @"绑定页的码是当下刚生成的，不追加");
}
- (void)test_防重放提示窗口 {
    IMTwoStepMarkEnabledNow();
    XCTAssertTrue(IMTwoStepRecentlyEnabled([NSDate date]));
    XCTAssertFalse(IMTwoStepRecentlyEnabled([NSDate dateWithTimeIntervalSinceNow:IMTwoStepReplayHintWindow + 1]));
}
- (void)test_流程作废判定 {
    XCTAssertTrue(IMTwoStepErrorEndsFlow(200022, IMTwoStepErrorContextLogin));
    XCTAssertTrue(IMTwoStepErrorEndsFlow(200022, IMTwoStepErrorContextBind));
    XCTAssertFalse(IMTwoStepErrorEndsFlow(200021, IMTwoStepErrorContextLogin));
    XCTAssertFalse(IMTwoStepErrorEndsFlow(200022, IMTwoStepErrorContextManage));
}

#pragma mark - 状态机

- (void)test_登录失败动作 {
    XCTAssertEqual(IMTwoStepLoginActionForError(200021, NO), IMTwoStepLoginActionRetryCode, @"错码：清空数字框重聚焦");
    XCTAssertEqual(IMTwoStepLoginActionForError(200021, YES), IMTwoStepLoginActionShowError, @"恢复码框不清空");
    XCTAssertEqual(IMTwoStepLoginActionForError(200022, NO), IMTwoStepLoginActionExpired);
    XCTAssertEqual(IMTwoStepLoginActionForError(200022, YES), IMTwoStepLoginActionExpired);
    XCTAssertEqual(IMTwoStepLoginActionForError(-1, NO), IMTwoStepLoginActionRetryCode, @"网络错：数字框也要清空才能再次自动提交");
}
- (void)test_自动提交条件 {
    XCTAssertTrue(IMTwoStepShouldAutoSubmit(@"123456", NO));
    XCTAssertFalse(IMTwoStepShouldAutoSubmit(@"123456", YES), @"在途不重复提交");
    XCTAssertFalse(IMTwoStepShouldAutoSubmit(@"12345", NO));
}
- (void)test_leave拦截与完成条件 {
    XCTAssertTrue(IMTwoStepShouldInterceptLeave(YES, NO));
    XCTAssertFalse(IMTwoStepShouldInterceptLeave(YES, YES), @"点过完成后不再拦截");
    XCTAssertFalse(IMTwoStepShouldInterceptLeave(NO, NO), @"别的页不拦");
    XCTAssertFalse(IMTwoStepCanFinish(NO));
    XCTAssertTrue(IMTwoStepCanFinish(YES));
}
- (void)test_验证页提交条件 {
    XCTAssertFalse(IMTwoStepCanSubmitVerify(@"12345", NO));
    XCTAssertTrue(IMTwoStepCanSubmitVerify(@"123456", NO));
    XCTAssertFalse(IMTwoStepCanSubmitVerify(@"123456", YES), @"恢复码模式下 6 位数字不算");
    XCTAssertTrue(IMTwoStepCanSubmitVerify(@"K7M2Q-9XW3P", YES));
}

#pragma mark - REST：HTTP 400 的标准信封必须保留 data

- (void)test_登录200020_HTTP400仍带回ticket {
    sStatus = 400;
    sResp = @{ @"code": @200020, @"message": @"two-step required",
               @"data": @{ @"ticket": @"TICKET-1", @"methods": @[@"totp", @"recovery"], @"expires_in": @300 } };
    IMHTTPService.sharedService.password = @"Test1234";
    [IMHTTPService.sharedService invalidateToken];
    XCTestExpectation *done = [self expectationWithDescription:@"login"];
    [IMHTTPService.sharedService loginWithUsername:@"twostep02" completion:^(NSString *token, NSString *userID, NSError *error) {
        XCTAssertNil(token);
        XCTAssertEqual(error.code, 200020);
        XCTAssertEqualObjects(error.userInfo[IMErrorTwoStepTicketKey], @"TICKET-1");
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:5];
    XCTAssertEqualObjects(sPath, @"/api/v1/login");
}

- (void)test_二步登录成功_与登录同一收尾且请求体只有ticket和code {
    sResp = @{ @"code": @0, @"data": @{ @"token": @"tok-2fa", @"uid": @"1000042", @"expires_in": @3600 } };
    XCTestExpectation *done = [self expectationWithDescription:@"2fa"];
    [IMHTTPService.sharedService loginTwoStepWithTicket:@"T9" code:@"123456" completion:^(NSString *token, NSString *userID, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(token, @"tok-2fa");
        XCTAssertEqualObjects(userID, @"1000042");
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:5];
    XCTAssertEqualObjects(sPath, @"/api/v1/login/two-step");
    XCTAssertEqualObjects(sBody, (@{ @"ticket": @"T9", @"code": @"123456" }));
    XCTAssertEqualObjects(IMHTTPService.sharedService.currentToken, @"tok-2fa", @"与 /login 同一条收尾：token 进缓存");
}

- (void)test_二步登录200021带剩余次数_200022不带 {
    sStatus = 400;
    sResp = @{ @"code": @200021, @"message": @"bad", @"data": @{ @"attempts_left": @2 } };
    XCTestExpectation *a = [self expectationWithDescription:@"a"];
    [IMHTTPService.sharedService loginTwoStepWithTicket:@"T" code:@"000000" completion:^(NSString *token, NSString *userID, NSError *error) {
        XCTAssertEqual(error.code, 200021);
        XCTAssertEqualObjects(error.userInfo[IMErrorTwoStepAttemptsLeftKey], @2);
        [a fulfill];
    }];
    [self waitForExpectations:@[a] timeout:5];
    sResp = @{ @"code": @200022, @"message": @"expired", @"data": [NSNull null] };
    XCTestExpectation *b = [self expectationWithDescription:@"b"];
    [IMHTTPService.sharedService loginTwoStepWithTicket:@"T" code:@"000000" completion:^(NSString *token, NSString *userID, NSError *error) {
        XCTAssertEqual(error.code, 200022);
        XCTAssertNil(error.userInfo[IMErrorTwoStepAttemptsLeftKey]);
        [b fulfill];
    }];
    [self waitForExpectations:@[b] timeout:5];
}

- (void)test_管理接口_路径与请求体 {
    NSString *t = @"tok";
    XCTestExpectation *e = [self expectationWithDescription:@"all"];
    sResp = @{ @"code": @0, @"data": @{ @"enabled": @YES, @"enabled_at": @1761696000000, @"recovery_remaining": @9 } };
    [IMHTTPService.sharedService fetchTwoStepStateWithToken:t completion:^(IMTwoStepState *state, NSError *error) {
        XCTAssertEqualObjects(sPath, @"/api/v1/users/me/two-step");
        XCTAssertTrue(state.enabled); XCTAssertEqual(state.recoveryRemaining, 9);
        sResp = @{ @"code": @0, @"data": @{ @"secret": @"JBSWY3DPEHPK3PXP", @"otpauth_uri": @"otpauth://totp/IM:u?secret=JBSWY3DPEHPK3PXP", @"expires_in": @1800 } };
        [IMHTTPService.sharedService setupTwoStepWithToken:t proof:[IMIdentityProof passwordProof:@"pw"] completion:^(IMTwoStepSetup *setup, NSError *e2) {
            XCTAssertEqualObjects(sPath, @"/api/v1/users/me/two-step/setup");
            XCTAssertEqualObjects(sBody, (@{ @"proof": @{ @"password": @"pw" } }));
            XCTAssertEqualObjects(setup.secret, @"JBSWY3DPEHPK3PXP");
            XCTAssertEqual(setup.expiresIn, 1800);
            NSArray *ten = @[@"a1",@"a2",@"a3",@"a4",@"a5",@"a6",@"a7",@"a8",@"a9",@"b0"];
            sResp = @{ @"code": @0, @"data": @{ @"recovery_codes": ten } };
            [IMHTTPService.sharedService enableTwoStepWithToken:t code:@"123456" completion:^(NSArray *codes, NSError *e3) {
                XCTAssertEqualObjects(sPath, @"/api/v1/users/me/two-step/enable");
                XCTAssertEqualObjects(sBody, @{ @"code": @"123456" });
                XCTAssertEqual(codes.count, 10u);
                [IMHTTPService.sharedService regenerateRecoveryCodesWithToken:t proof:[IMIdentityProof smsProof:@"123456"] code:@"k7m2q9xw3p" completion:^(NSArray *c2, NSError *e4) {
                    XCTAssertEqualObjects(sPath, @"/api/v1/users/me/two-step/recovery-codes");
                    XCTAssertEqualObjects(sBody, (@{ @"proof": @{ @"sms_code": @"123456" }, @"code": @"k7m2q9xw3p" }));
                    XCTAssertEqual(c2.count, 10u);
                    sResp = @{ @"code": @0, @"data": @{ @"ok": @YES } };
                    [IMHTTPService.sharedService disableTwoStepWithToken:t proof:[IMIdentityProof passwordProof:@"pw"] code:@"654321" completion:^(NSError *e5) {
                        XCTAssertNil(e5);
                        XCTAssertEqualObjects(sPath, @"/api/v1/users/me/two-step/disable");
                        XCTAssertEqualObjects(sBody, (@{ @"proof": @{ @"password": @"pw" }, @"code": @"654321" }));
                        [e fulfill];
                    }];
                }];
            }];
        }];
    }];
    [self waitForExpectations:@[e] timeout:10];
}

- (void)test_enable成功码但无恢复码当失败 {
    sResp = @{ @"code": @0, @"data": @{ @"recovery_codes": @[] } };
    XCTestExpectation *e = [self expectationWithDescription:@"e"];
    [IMHTTPService.sharedService enableTwoStepWithToken:@"t" code:@"123456" completion:^(NSArray *codes, NSError *error) {
        XCTAssertNil(codes); XCTAssertNotNil(error);
        [e fulfill];
    }];
    [self waitForExpectations:@[e] timeout:5];
}

#pragma mark - 日志脱敏

- (void)test_日志不含验证码_密钥_恢复码_ticket {
    NSDictionary *req = @{ @"ticket": @"TICKET-1", @"code": @"123456", @"password": @"pw" };
    NSDictionary *resp = @{ @"code": @0, @"data": @{ @"secret": @"JBSWY3DP", @"otpauth_uri": @"otpauth://totp/x?secret=JBSWY3DP",
                                                      @"recovery_codes": @[@"aaaaa-bbbbb"], @"ticket": @"TICKET-2", @"refresh_token": @"r" } };
    for (NSNumber *business in @[@YES, @NO]) {
        NSDictionary *a = IMHTTPSanitizedJSONObject(req, business.boolValue);
        NSDictionary *b = IMHTTPSanitizedJSONObject(resp, business.boolValue);
        XCTAssertEqualObjects(a[@"ticket"], @"***"); XCTAssertEqualObjects(a[@"code"], @"***"); XCTAssertEqualObjects(a[@"password"], @"***");
        XCTAssertEqualObjects(b[@"code"], @0, @"信封里的数字业务码要留着，否则无法排障");
        XCTAssertEqualObjects(b[@"data"][@"secret"], @"***");
        XCTAssertEqualObjects(b[@"data"][@"otpauth_uri"], @"***");
        XCTAssertEqualObjects(b[@"data"][@"recovery_codes"], @"***");
        XCTAssertEqualObjects(b[@"data"][@"ticket"], @"***");
    }
    NSData *raw = [NSJSONSerialization dataWithJSONObject:resp options:0 error:NULL];
    NSString *line = IMHTTPLogBody(raw, @"application/json", YES);
    for (NSString *secret in @[@"JBSWY3DP", @"aaaaa-bbbbb", @"TICKET-2", @"otpauth://"]) {
        XCTAssertFalse([line containsString:secret], @"日志泄露 %@", secret);
    }
}

#pragma mark - 系统通知渲染

- (void)test_恢复码登录系统通知_中英 {
    NSDictionary *args = @{ @"left": @"7", @"at": @"2026-10-29T10:00:00Z", @"device": @"iPhone 17" };
    NSString *zh = IMTextForNoticeSysEvent(@"twostep_recovery_used", args);
    XCTAssertNotNil(zh);
    NSArray *lines = [zh componentsSeparatedByString:@"\n"];
    XCTAssertEqual(lines.count, 3u);
    XCTAssertTrue([lines[0] containsString:@"剩余 7 个恢复码"], @"%@", lines[0]);
    XCTAssertTrue([lines[1] containsString:@"iPhone 17"]);
    XCTAssertEqualObjects(lines[2], IMLocalized(@"sys.notice.twostep_recovery_used.footer"));
    NSString *noDevice = IMTextForNoticeSysEvent(@"twostep_recovery_used", @{ @"left": @"0", @"at": @"2026-10-29T10:00:00Z" });
    XCTAssertEqual([noDevice componentsSeparatedByString:@"\n"].count, 2u, @"无 device 不出设备行");
    [IMLocalization.shared setPreference:IMLanguagePrefEnglish];
    NSString *en = IMTextForNoticeSysEvent(@"twostep_recovery_used", args);
    XCTAssertTrue([en containsString:@"7 recovery codes left"], @"%@", en);
}

#pragma mark - 设置搜索 / 路由

- (void)test_设置搜索登记两步验证 {
    IMSettingsSearchEntry *hit = nil;
    for (IMSettingsSearchEntry *e in [IMSettingsSearchRegistry allEntries]) { if ([e.entryID isEqualToString:@"privacy.twoStep"]) { hit = e; } }
    XCTAssertNotNil(hit);
    XCTAssertEqualObjects(hit.path, (@[IMLocalized(@"settings.row.privacy"), IMLocalized(@"ps.row.two_factor")]));
    XCTAssertEqualObjects(hit.route, (@[@"privacy", @"privacy/twoStep"]));
    NSArray *found = [IMSettingsSearchRegistry filterEntries:[IMSettingsSearchRegistry allEntries] keyword:@"两步"];
    XCTAssertTrue([[found valueForKey:@"entryID"] containsObject:@"privacy.twoStep"]);
    NSArray *vcs = [IMSettingsRouter viewControllersForRoute:@[@"privacy", @"privacy/twoStep"] host:@"h" userID:@"u1"];
    XCTAssertEqual(vcs.count, 2u);
    XCTAssertTrue([vcs.lastObject isKindOfClass:IMTwoStepViewController.class]);
}

- (void)test_隐私页两步验证行已转活 {
    IMPrivacySecurityViewController *vc = [[IMPrivacySecurityViewController alloc] initWithHost:@"h" userID:@"u1"];
    [vc loadViewIfNeeded];
    id row = nil;
    for (id group in [vc valueForKey:@"groups"]) {
        for (id r in [group valueForKey:@"rows"]) { if ([[r valueForKey:@"rowId"] isEqualToString:@"twoStep"]) { row = r; } }
    }
    XCTAssertNotNil(row);
    XCTAssertEqualObjects([row valueForKey:@"isPlaceholder"], @NO, @"去掉 comingSoon / 灰置");
    XCTAssertNil([row valueForKey:@"rightValue"], @"加载前留空");
    XCTAssertNotNil([row valueForKey:@"handler"]);
}

#pragma mark - 各页状态

- (void)test_恢复码页_只有勾选后才能完成且返回被锁 {
    IMTwoStepCodesViewController *vc = [[IMTwoStepCodesViewController alloc] initWithHost:@"h" userID:@"u1"
        recoveryCodes:@[@"aaaaa-bbbbb", @"ccccc-ddddd"] regenerated:NO];
    [vc loadViewIfNeeded];
    XCTAssertTrue([vc locksBackNavigation]);
    XCTAssertFalse(vc.primaryButton.enabled);
    XCTAssertEqualWithAccuracy(vc.primaryButton.alpha, 0.5, 0.01);
    [vc toggleSaved];
    XCTAssertTrue(vc.primaryButton.enabled);
    XCTAssertEqualWithAccuracy(vc.primaryButton.alpha, 1.0, 0.01);
    [vc toggleSaved];
    XCTAssertFalse(vc.primaryButton.enabled);
}

- (void)test_绑定页_6位框属性与手动密钥折叠 {
    IMTwoStepSetup *setup = [IMTwoStepSetup new];
    setup.secret = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    setup.otpauthURI = @"otpauth://totp/IM:u?secret=ABCDEFGHIJKLMNOPQRSTUVWXYZ234567&issuer=IM";
    IMTwoStepBindViewController *vc = [[IMTwoStepBindViewController alloc] initWithHost:@"h" userID:@"u1" setup:setup];
    [vc loadViewIfNeeded];
    UITextField *code = [vc valueForKey:@"codeField"];
    XCTAssertEqual(code.keyboardType, UIKeyboardTypeNumberPad);
    XCTAssertEqualObjects(code.textContentType, UITextContentTypeOneTimeCode);
    XCTAssertFalse(vc.primaryButton.enabled);
    code.text = @"123 456";
    [code sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqualObjects(code.text, @"123456", @"粘贴「123 456」被清洗");
    XCTAssertTrue(vc.primaryButton.enabled);
    UITableView *tv = vc.tableView;
    [tv layoutIfNeeded];
    NSInteger rowsBefore = [tv numberOfRowsInSection:1];
    [vc toggleManual];
    [tv layoutIfNeeded];
    XCTAssertEqual([tv numberOfRowsInSection:1], rowsBefore + 1, @"展开后多一行密钥");
}

- (void)test_验证页_切换恢复码_关闭为红按钮 {
    IMTwoStepVerifyViewController *vc = [[IMTwoStepVerifyViewController alloc] initWithHost:@"h" userID:@"u1" mode:IMTwoStepVerifyModeDisable];
    [vc loadViewIfNeeded];
    XCTAssertEqualObjects(vc.primaryButton.backgroundColor, UIColor.systemRedColor);
    UITextField *code = [vc valueForKey:@"codeField"], *rec = [vc valueForKey:@"recoveryField"];
    code.text = @"123456"; [code sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertTrue(vc.primaryButton.enabled);
    [vc toggleMethod];
    XCTAssertFalse(vc.primaryButton.enabled, @"换成恢复码后，6 位动态码不再算数");
    XCTAssertEqualObjects(code.text, @"", @"换方式丢掉另一种码");
    XCTAssertEqual(rec.autocapitalizationType, UITextAutocapitalizationTypeNone);
    XCTAssertEqual(rec.autocorrectionType, UITextAutocorrectionTypeNo);
    XCTAssertEqual(rec.spellCheckingType, UITextSpellCheckingTypeNo);
    rec.text = @"K7M2Q-9XW3P"; [rec sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertTrue(vc.primaryButton.enabled);
    XCTAssertEqualObjects(rec.text, @"K7M2Q-9XW3P", @"输入过程不改写文本，归一化只在提交时做");
    IMTwoStepVerifyViewController *regen = [[IMTwoStepVerifyViewController alloc] initWithHost:@"h" userID:@"u1" mode:IMTwoStepVerifyModeRegenerate];
    [regen loadViewIfNeeded];
    XCTAssertEqualObjects(regen.primaryButton.backgroundColor, UIColor.systemBlueColor);
}

- (void)test_入口页是流程根 {
    IMTwoStepViewController *root = [[IMTwoStepViewController alloc] initWithHost:@"h" userID:@"u1"];
    XCTAssertTrue([root isFlowRoot]);
}

#pragma mark - 登录二步页

- (void)test_二步页_输满6位自动提交_在途不重复 {
    IMLoginTwoStepView *v = [IMLoginTwoStepView new];
    __block NSInteger calls = 0; __block NSString *got = nil; __block BOOL rec = YES;
    v.onSubmit = ^(NSString *code, BOOL recovery) { calls++; got = code; rec = recovery; };
    v.codeField.text = @"12345";
    [v.codeField sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqual(calls, 0);
    v.codeField.text = @"123 456";
    [v.codeField sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqual(calls, 1);
    XCTAssertEqualObjects(got, @"123456");
    XCTAssertFalse(rec);
    v.busy = YES;
    v.codeField.text = @"654321";
    [v.codeField sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqual(calls, 1, @"在途不重复提交");
}

- (void)test_二步页_恢复码模式提交归一化且不清空 {
    IMLoginTwoStepView *v = [IMLoginTwoStepView new];
    __block NSString *got = nil; __block BOOL rec = NO;
    v.onSubmit = ^(NSString *code, BOOL recovery) { got = code; rec = recovery; };
    [v.superview layoutIfNeeded];
    [[v valueForKey:@"toggleButton"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertTrue(v.recoveryMode);
    XCTAssertFalse(v.submitButton.hidden);
    XCTAssertTrue(v.codeField.hidden);
    XCTAssertEqual(v.recoveryField.autocapitalizationType, UITextAutocapitalizationTypeNone);
    XCTAssertEqual(v.recoveryField.autocorrectionType, UITextAutocorrectionTypeNo);
    XCTAssertEqual(v.recoveryField.spellCheckingType, UITextSpellCheckingTypeNo);
    v.recoveryField.text = @"K7M2Q-9XW3P";
    [v.submitButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertEqualObjects(got, @"k7m2q9xw3p");
    XCTAssertTrue(rec);
    XCTAssertEqualObjects(v.recoveryField.text, @"K7M2Q-9XW3P", @"提交不改写输入框");
}

- (void)test_登录页_进二步页隐藏密码页控件_返回恢复并丢ticket {
    IMLoginViewController *vc = [IMLoginViewController new];
    [vc loadViewIfNeeded];
    UITextField *user = [vc valueForKey:@"userIDField"], *pw = [vc valueForKey:@"passwordField"];
    IMLoginTwoStepView *two = [vc valueForKey:@"twoStepView"];
    XCTAssertTrue(two.hidden);
    XCTAssertFalse(user.hidden);
    [vc beginTwoStepWithTicket:@"T1" host:@"127.0.0.1:8080" tab:1];
    XCTAssertFalse(two.hidden);
    XCTAssertTrue(user.hidden); XCTAssertTrue(pw.hidden);
    XCTAssertTrue([[vc valueForKey:@"loginButton"] isHidden]);
    XCTAssertEqualObjects([vc valueForKey:@"twoStepTicket"], @"T1");
    [vc leaveSubpage];
    XCTAssertTrue(two.hidden);
    XCTAssertFalse(user.hidden); XCTAssertFalse(pw.hidden);
    XCTAssertFalse([[vc valueForKey:@"loginButton"] isHidden]);
    XCTAssertTrue([[vc valueForKey:@"registerButton"] isHidden], @"登录页签下注册按钮本就隐藏，恢复不能把它放出来");
    XCTAssertNil([vc valueForKey:@"twoStepTicket"], @"离开二步页即丢 ticket");
}

- (void)test_登录页_ticket失效回密码页并提示 {
    IMLoginViewController *vc = [IMLoginViewController new];
    [vc loadViewIfNeeded];
    [vc beginTwoStepWithTicket:@"T1" host:@"h" tab:1];
    NSError *err = [NSError errorWithDomain:@"IMHTTPService" code:200022 userInfo:@{ NSLocalizedDescriptionKey: @"x" }];
    [vc handleTwoStepFailure:err recovery:NO];
    XCTAssertTrue([[vc valueForKey:@"twoStepView"] isHidden]);
    XCTAssertNil([vc valueForKey:@"twoStepTicket"]);
    UILabel *errorLabel = [vc valueForKey:@"errorLabel"];
    XCTAssertEqualObjects(errorLabel.text, @"已超时，请重新登录");
    XCTAssertFalse(errorLabel.hidden);
}

- (void)test_登录页_错码清空数字框并显示剩余次数 {
    IMLoginViewController *vc = [IMLoginViewController new];
    [vc loadViewIfNeeded];
    [vc beginTwoStepWithTicket:@"T1" host:@"h" tab:1];
    IMLoginTwoStepView *two = [vc valueForKey:@"twoStepView"];
    two.codeField.text = @"123456";
    NSError *err = [NSError errorWithDomain:@"IMHTTPService" code:200021
                                   userInfo:@{ NSLocalizedDescriptionKey: @"x", IMErrorTwoStepAttemptsLeftKey: @2 }];
    [vc handleTwoStepFailure:err recovery:NO];
    XCTAssertEqualObjects(two.codeField.text, @"");
    XCTAssertEqualObjects([[two valueForKey:@"errorLabel"] text], @"验证码不正确，还可尝试 2 次");
    XCTAssertFalse([two isHidden], @"仍停在二步页");
    XCTAssertEqualObjects([vc valueForKey:@"twoStepTicket"], @"T1", @"码错不丢 ticket");
}

@end
