//  IMUITestLogin.m

#import "IMUITestLogin.h"

XCUIElement *IMUITestLoginLogo(XCUIApplication *app) {
    return [[app descendantsMatchingType:XCUIElementTypeAny] matchingIdentifier:@"login.logo"].firstMatch;
}

BOOL IMUITestShowPasswordLogin(XCUIApplication *app, NSTimeInterval timeout) {
    if (![IMUITestLoginLogo(app) waitForExistenceWithTimeout:timeout]) { return NO; }
    XCUIElement *tab = app.buttons[@"login.tab_password"];
    // 只开放一种登录方式时没有页签行（tab 不存在），密码表单已经在显示。
    if (tab.exists && tab.isHittable) { [tab tap]; }
    return YES;
}
