//
//  SceneDelegate.m
//  IMProgram
//
//  Created by liying on 2026/6/13.
//

#import "SceneDelegate.h"
#import "IMLoginViewController.h"
#import "IMMainTabBarController.h"
#import "IMHTTPService.h"
#import "IMSessionStore.h"
#import "IMLog.h"

@interface SceneDelegate ()

@end

@implementation SceneDelegate


- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    // 以纯代码设置根控制器（覆盖 Storyboard 默认页）。
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    if (![windowScene isKindOfClass:UIWindowScene.class]) { return; }

    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    IMLog(@"launch hasSession=%d uid=%@ host=%@", [IMSessionStore hasSession], IMSessionStore.userID, IMSessionStore.host);
    if ([IMSessionStore hasSession]) {
        // 保持登录：先显示加载态，用已存 host/uid/password 静默重登拿新 token（socket 重连也需 password），
        // 成功直达会话主界面；失败（改密/账号异常/过期不可续）→ 回登录页。
        self.window.rootViewController = [self loadingController];
        [self restoreSession];
    } else {
        [self showLogin];
    }
    [self.window makeKeyAndVisible];
}

/// 用持久化的凭据静默重登，恢复 currentToken 后进入主界面。
- (void)restoreSession {
    NSString *host = IMSessionStore.host ?: @"";
    NSString *uid = IMSessionStore.userID ?: @"";
    IMHTTPService.sharedService.host = host;
    IMHTTPService.sharedService.password = IMSessionStore.password ?: @"";
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService loginWithUserID:uid completion:^(NSString *token, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        IMLog(@"restore silent-login token=%lu err=%@", (unsigned long)token.length, error.localizedDescription);
        if (token.length > 0) {
            self.window.rootViewController = [[IMMainTabBarController alloc] initWithHost:host userID:uid];
        } else {
            // 失败仅回登录页，不清凭据：网络临时不通时下次启动仍可自动重登（host 已回填，用户也可手动登录）。
            // 真正的鉴权失效由运行中的 bounceToLogin / 显式退出登录负责清除。
            [self showLogin];
        }
    }];
}

- (void)showLogin {
    IMLoginViewController *login = [IMLoginViewController new];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:login];
}

/// 静默重登期间的过渡页（居中转圈），避免闪现登录页。
- (UIViewController *)loadingController {
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [vc.view addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
    ]];
    return vc;
}


- (void)sceneDidDisconnect:(UIScene *)scene {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
}


- (void)sceneDidBecomeActive:(UIScene *)scene {
    // Called when the scene has moved from an inactive state to an active state.
    // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
}


- (void)sceneWillResignActive:(UIScene *)scene {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
}


- (void)sceneWillEnterForeground:(UIScene *)scene {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
}


- (void)sceneDidEnterBackground:(UIScene *)scene {
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.
}


@end
