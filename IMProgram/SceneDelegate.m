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
#import "IMSocketManager.h"
#import "UIViewController+IMToast.h"
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
    // 被踢下线（多设备管理）：socket 握手吃 401 时发此通知，强制回登录页。跨登录态常驻。
    // 先 remove 再 add：scene 断开后系统可能重连并再次 willConnectToSession，避免重复注册导致一次 401 触发多次登出。
    [NSNotificationCenter.defaultCenter removeObserver:self name:IMSocketDidRevokeSessionNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleSessionRevoked)
                                               name:IMSocketDidRevokeSessionNotification object:nil];
    [IMAppearance.shared applyInterfaceStyle];
    IMLog(@"launch hasSession=%d uid=%@ host=%@", [IMSessionStore hasSession], IMSessionStore.userID, IMSessionStore.host);
    if ([IMSessionStore hasSession]) {
        // 本地会话是启动导航的依据：即使服务器不可达，也先进入主界面展示本地会话和“未连接”。
        // 会话页负责静默登录、区分网络失败与鉴权失败，并由 socket 自动重连。
        NSString *host = IMSessionStore.host ?: @"";
        NSString *uid = IMSessionStore.userID ?: @"";
        IMHTTPService.sharedService.host = host;
        // username 是重登凭据（登录接口不认内部 ID），不恢复它会让静默重登拿 uid 去登录、必然失败。
        IMHTTPService.sharedService.username = IMSessionStore.username ?: @"";
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

/// 会话被服务端吊销（在其他设备"退出该设备/退出其他所有设备"把本机踢了）：清登录态 + 回登录页。
/// 通知在主线程发；幂等——已在登录页则只补一次提示。
- (void)handleSessionRevoked {
    if ([self.window.rootViewController isKindOfClass:UINavigationController.class]
        && [((UINavigationController *)self.window.rootViewController).topViewController isKindOfClass:IMLoginViewController.class]) {
        return;
    }
    IMLog(@"session revoked → 强制登出回登录页");
    [IMSocketManager.sharedManager disconnect];
    [IMHTTPService.sharedService invalidateToken];
    [IMSessionStore clear]; // 清持久化会话：下次启动直接回登录页，不再静默重登
    [self showLogin];
    [UIViewController im_showGlobalToast:@"该账号已在其他设备退出登录，请重新登录"];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    [NSNotificationCenter.defaultCenter removeObserver:self name:IMSocketDidRevokeSessionNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
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
