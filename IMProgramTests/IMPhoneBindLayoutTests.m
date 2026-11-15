//  IMPhoneBindLayoutTests.m
//  「登录手机号」绑定 / 更换页版式：更换页「当前手机号 …」说明行左对齐、文字左沿与下方输入框（「+86」、验证码框）一致，
//  13pt 次要字色，与输入卡片间距约 8；绑定页（无说明行）两行输入的文字左沿同样对齐。

#import <XCTest/XCTest.h>
#import "IMPhoneAuth.h"
#import "IMPhoneBindViewController.h"
#import "IMSMSCodeField.h"
#import "IMTheme.h"

@interface IMPhoneBindLayoutTests : XCTestCase
@end

@implementation IMPhoneBindLayoutTests

static UIView *IMPBLFind(UIView *root, BOOL (^match)(UIView *v)) {
    if (match(root)) { return root; }
    for (UIView *s in root.subviews) {
        UIView *hit = IMPBLFind(s, match);
        if (hit) { return hit; }
    }
    return nil;
}

- (IMPhoneBindViewController *)pageBound:(BOOL)bound window:(UIWindow **)outWindow {
    IMSecurityState *s = [IMSecurityState stateFromJSON:@{ @"phone_bound": @(bound), @"phone_masked": @"+86 159****0001", @"password_set": @YES }];
    IMPhoneBindViewController *vc = [[IMPhoneBindViewController alloc] initWithHost:@"127.0.0.1:59397" userID:@"u-layout" security:s];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    UIWindowScene *scene = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) { if ([sc isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)sc; break; } }
    UIWindow *w = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:CGRectZero];
    w.frame = CGRectMake(0, 0, 440, 956);
    w.rootViewController = nav;
    [w makeKeyAndVisible];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    [vc.view layoutIfNeeded];
    *outWindow = w;
    return vc;
}

- (CGRect)frameOf:(UIView *)v in:(UIView *)root { return [v convertRect:v.bounds toView:root]; }

- (void)test_更换页_当前手机号行_左沿与输入框对齐_次要字_间距8 {
    UIWindow *w = nil;
    IMPhoneBindViewController *vc = [self pageBound:YES window:&w];
    UILabel *current = (UILabel *)IMPBLFind(vc.tableView, ^BOOL(UIView *v) {
        return [v isKindOfClass:UILabel.class] && [((UILabel *)v).text containsString:@"159****0001"];
    });
    XCTAssertNotNil(current);
    UIButton *cc = (UIButton *)IMPBLFind(vc.tableView, ^BOOL(UIView *v) { return [v.accessibilityIdentifier isEqualToString:@"phone.country_code"]; });
    CGRect label = [self frameOf:current in:vc.view];
    CGRect ccTitle = [self frameOf:cc.titleLabel in:vc.view];
    CGRect code = [self frameOf:vc.codeField in:vc.view];
    CGRect phoneCell = [self frameOf:vc.phoneField.superview in:vc.view];
    XCTAssertEqual(current.textAlignment, NSTextAlignmentNatural, @"左对齐");
    XCTAssertEqualWithAccuracy(CGRectGetMinX(label), CGRectGetMinX(ccTitle), 1, @"与「+86」左沿对齐");
    XCTAssertEqualWithAccuracy(CGRectGetMinX(label), CGRectGetMinX(code), 1, @"与验证码框左沿对齐");
    XCTAssertEqualWithAccuracy(CGRectGetMinY(phoneCell) - CGRectGetMaxY(label), 8, 2, @"与输入卡片间距约 8");
    XCTAssertEqual(current.font.pointSize, 13);
    XCTAssertEqualObjects(current.textColor, IMTheme.textSecondary);
    w.hidden = YES;
}

- (void)test_绑定页_没有当前手机号行_两行输入文字左沿对齐 {
    UIWindow *w = nil;
    IMPhoneBindViewController *vc = [self pageBound:NO window:&w];
    XCTAssertNil(IMPBLFind(vc.tableView, ^BOOL(UIView *v) {
        return [v isKindOfClass:UILabel.class] && [((UILabel *)v).text containsString:@"159****0001"];
    }), @"绑定页不显示当前手机号");
    UIButton *cc = (UIButton *)IMPBLFind(vc.tableView, ^BOOL(UIView *v) { return [v.accessibilityIdentifier isEqualToString:@"phone.country_code"]; });
    XCTAssertEqualWithAccuracy(CGRectGetMinX([self frameOf:cc.titleLabel in:vc.view]), CGRectGetMinX([self frameOf:vc.codeField in:vc.view]), 1);
    w.hidden = YES;
}

@end
