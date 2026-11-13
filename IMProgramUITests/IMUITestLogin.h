//  IMUITestLogin.h
//  UI 测试共用的登录页小工具。
//
//  登录页默认是「验证码登录」页签（PHONE_AUTH_DESIGN §4.1），「免密登录（开发）」只在「密码登录」页签显示；
//  各 UI 测试找免密按钮之前先调 IMUITestShowPasswordLogin 切过去。

#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

/// 登录页的 Logo（`login.logo`），用来判断「已回到登录页」，不依赖当前停在哪个页签。
XCUIElement *IMUITestLoginLogo(XCUIApplication *app);

/// 停在登录页时切到「密码登录」页签，返回 YES；等 timeout 秒仍不在登录页（已登录）返回 NO。
BOOL IMUITestShowPasswordLogin(XCUIApplication *app, NSTimeInterval timeout);

NS_ASSUME_NONNULL_END
