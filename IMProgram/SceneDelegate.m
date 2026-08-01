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
#import "IMAppearance.h"

@interface SceneDelegate ()

@end

@implementation SceneDelegate


- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    // 以纯代码设置根控制器（覆盖 Storyboard 默认页）。
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    if (![windowScene isKindOfClass:UIWindowScene.class]) { return; }

    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    [IMAppearance.shared applyInterfaceStyle];
    IMLog(@"launch hasSession=%d uid=%@ host=%@", [IMSessionStore hasSession], IMSessionStore.userID, IMSessionStore.host);
    if ([IMSessionStore hasSession]) {
        // 本地会话是启动导航的依据：即使服务器不可达，也先进入主界面展示本地会话和“未连接”。
        // 会话页负责静默登录、区分网络失败与鉴权失败，并由 socket 自动重连。
        NSString *host = IMSessionStore.host ?: @"";
        NSString *uid = IMSessionStore.userID ?: @"";
        IMHTTPService.sharedService.host = host;
        IMHTTPService.sharedService.password = IMSessionStore.password ?: @"";
        self.window.rootViewController = [[IMMainTabBarController alloc] initWithHost:host userID:uid];
    } else {
        [self showLogin];
    }
    [self.window makeKeyAndVisible];
    [IMAppearance.shared applyInterfaceStyle];
    self.window.tintColor = IMAppearance.shared.accentColor;
}

- (void)showLogin {
    IMLoginViewController *login = [IMLoginViewController new];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:login];
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
