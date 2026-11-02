//  IMAppInfoTests.m
//  「关于我们」：版本串、法务页链接拼接、页面行为（点版本复制）、设置页入口与搜索命中。

#import <XCTest/XCTest.h>
#import "IMAppInfo.h"
#import "IMAboutViewController.h"
#import "IMSettingsRouter.h"
#import "IMSettingsSearchRegistry.h"
#import "IMLoginViewController.h"
#import "IMLocalization.h"

@interface IMAppInfoTests : XCTestCase
@end

@implementation IMAppInfoTests

- (void)testVersionStringCombinesShortAndBuild {
    XCTAssertEqualObjects([IMAppInfo versionStringWithShortVersion:@"1.0.0" build:@"12"], @"1.0.0 (12)");
    XCTAssertEqualObjects([IMAppInfo versionStringWithShortVersion:@"1.0.0" build:nil], @"1.0.0");
    XCTAssertEqualObjects([IMAppInfo versionStringWithShortVersion:@"" build:@"12"], @"12");
    XCTAssertEqualObjects([IMAppInfo versionStringWithShortVersion:nil build:nil], @"-");
}

- (void)testClipboardStringCarriesPlatformName {
    XCTAssertTrue([IMAppInfo.versionClipboardString hasPrefix:@"iOS "]);
    XCTAssertTrue([IMAppInfo.versionClipboardString hasSuffix:IMAppInfo.versionString]);
}

- (void)testLegalURLUsesHostPathAndLanguage {
    NSURL *zh = [IMAppInfo legalURLForPath:IMLegalPathPrivacy host:@"10.0.0.2:8080" language:@"zh-Hans"];
    XCTAssertEqualObjects(zh.path, @"/legal/privacy");
    XCTAssertEqualObjects(zh.query, @"lang=zh-Hans");
    XCTAssertEqualObjects(zh.host, @"10.0.0.2");
    NSURL *en = [IMAppInfo legalURLForPath:IMLegalPathSupport host:@"10.0.0.2:8080" language:@"en"];
    XCTAssertEqualObjects(en.path, @"/support");
    XCTAssertEqualObjects(en.query, @"lang=en");
    XCTAssertEqualObjects([IMAppInfo legalURLForPath:IMLegalPathTerms host:@"h:1" language:@"fr"].query, @"lang=zh-Hans", @"未知语言回退中文");
    // 显式 scheme 变体（登录页用）：按传入 scheme 拼，不读/不改共享单例。
    NSURL *https = [IMAppInfo legalURLForPath:IMLegalPathTerms host:@"h:1" scheme:@"https" language:@"en"];
    XCTAssertEqualObjects(https.absoluteString, @"https://h:1/legal/terms?lang=en");
    XCTAssertNil([IMAppInfo legalURLForPath:@"/api/v1/login" host:@"h:1" scheme:@"https" language:@"en"], @"白名单外路径仍拒");
}

- (void)testLegalURLRejectsEmptyHostAndUnknownPath {
    XCTAssertNil([IMAppInfo legalURLForPath:IMLegalPathPrivacy host:@"" language:@"en"]);
    XCTAssertNil([IMAppInfo legalURLForPath:IMLegalPathPrivacy host:nil language:@"en"]);
    XCTAssertNil([IMAppInfo legalURLForPath:@"/api/v1/login" host:@"h:1" language:@"en"], @"只允许三个法务页路径");
}

- (void)testAboutPageHasFourRowsAndVersionTapCopies {
    IMAboutViewController *vc = [[IMAboutViewController alloc] initWithHost:@"127.0.0.1:1"];
    [vc loadViewIfNeeded];
    UITableView *tv = nil;
    for (UIView *v in vc.view.subviews) { if ([v isKindOfClass:UITableView.class]) { tv = (UITableView *)v; } }
    XCTAssertNotNil(tv);
    XCTAssertEqual([tv numberOfRowsInSection:0], 4);
    UIPasteboard.generalPasteboard.string = @"";
    [tv.delegate tableView:tv didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
    XCTAssertEqualObjects(UIPasteboard.generalPasteboard.string, IMAppInfo.versionClipboardString);
}

- (void)testRouterBuildsAboutPage {
    NSArray *pages = [IMSettingsRouter viewControllersForRoute:@[@"about"] host:@"h:1" userID:@"u"];
    XCTAssertEqual(pages.count, 1u);
    XCTAssertTrue([pages.firstObject isKindOfClass:IMAboutViewController.class]);
}

/// 批②：登录页底部「继续即表示同意…」为隐式同意提示（无勾选框），两段链接可点、分流到条款/隐私页。
- (void)testLoginAgreeFooterHasTwoLegalLinks {
    IMLoginViewController *vc = [IMLoginViewController new];
    [vc loadViewIfNeeded];
    UITextView *footer = [self firstTextViewWithIdentifier:@"login.agree_footer" in:vc.view];
    XCTAssertNotNil(footer, @"登录页应有同意提示 UITextView");
    NSString *terms = IMLocalized(@"about.terms"), *privacy = IMLocalized(@"about.privacy_policy");
    XCTAssertTrue([footer.text containsString:terms]);
    XCTAssertTrue([footer.text containsString:privacy]);
    NSMutableSet<NSString *> *linkHosts = [NSMutableSet set];
    [footer.attributedText enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, footer.attributedText.length)
                                      options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
        if ([value isKindOfClass:NSURL.class]) { [linkHosts addObject:[(NSURL *)value host]]; }
    }];
    XCTAssertEqualObjects(linkHosts, ([NSSet setWithObjects:@"terms", @"privacy", nil]), @"两段链接分别指向条款/隐私");
}

- (nullable UITextView *)firstTextViewWithIdentifier:(NSString *)identifier in:(UIView *)root {
    for (UIView *v in root.subviews) {
        if ([v isKindOfClass:UITextView.class] && [v.accessibilityIdentifier isEqualToString:identifier]) { return (UITextView *)v; }
        UITextView *found = [self firstTextViewWithIdentifier:identifier in:v];
        if (found) { return found; }
    }
    return nil;
}

- (void)testSearchAliasesHitAboutEntry {
    NSArray<IMSettingsSearchEntry *> *all = [IMSettingsSearchRegistry allEntries];
    for (NSString *kw in @[@"隐私政策", @"服务条款", @"技术支持", @"版本"]) {
        NSArray *hits = [IMSettingsSearchRegistry filterEntries:all keyword:kw];
        NSArray *ids = [hits valueForKey:@"entryID"];
        XCTAssertTrue([ids containsObject:@"about"], @"搜「%@」应命中关于我们", kw);
    }
}

@end
