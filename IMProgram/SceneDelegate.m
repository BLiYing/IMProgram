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
#import "IMServerEndpoint.h"
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
    // 协议要在任何网络调用之前恢复：IMServerEndpoint 默认 http，晚一步恢复就会有请求走错协议。
    // 没存过（老版本升上来）时 saveScheme: 的空值保护让它保持默认 http，行为与改造前一致。
    IMServerEndpoint.shared.scheme = IMSessionStore.scheme ?: IMServerSchemeHTTP;
    IMLog(@"launch hasSession=%d uid=%@ host=%@ scheme=%@", [IMSessionStore hasSession],
          IMSessionStore.userID, IMSessionStore.host, IMServerEndpoint.shared.scheme);
    if ([IMSessionStore hasSession]) {
        // 本地会话是启动导航的依据：即使服务器不可达，也先进入主界面展示本地会话和“未连接”。
        // 会话页负责静默登录、区分网络失败与鉴权失败，并由 socket 自动重连。
        NSString *host = IMSessionStore.host ?: @"";
        NSString *uid = IMSessionStore.userID ?: @"";
        IMHTTPService.sharedService.host = host;
        // username 是重登凭据（登录接口不认内部 ID），不恢复它会让静默重登拿 uid 去登录、必然失败。
        IMHTTPService.sharedService.username = IMSessionStore.username ?: @"";
        // 保持登录改用**续期凭据**（可吊销、只作用于本设备），不再恢复明文密码（安全整改第 5 步）。
        // 老安装升级上来时还没有它：退回用遗留明文密码做最后一次登录，IMHTTPService 收到
        // refresh_token 后会立刻把明文从内存与磁盘一起擦掉（一次性迁移，见 IMSessionStore.legacyPassword）。
        IMHTTPService.sharedService.refreshToken = IMSessionStore.refreshToken;
        if (IMSessionStore.refreshToken.length == 0) {
            IMHTTPService.sharedService.password = IMSessionStore.legacyPassword ?: @"";
        }
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
    IMHTTPService.sharedService.refreshToken = nil; // invalidateToken 刻意不动它（长效凭据），登出这里必须清
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
    // 回到前台立即重连/探活，不等指数退避那一档（最长 30s）。
    // 后台期间系统会挂起 socket，多数情况下回来时连接其实已经死了但本端还不知道；
    // 已连接时 reconnectNowWithReason: 只发一次 ping 探活，写失败才走既有断线重连路径。
    [[IMSocketManager sharedManager] reconnectNowWithReason:@"foreground"];
}


- (void)sceneDidEnterBackground:(UIScene *)scene {
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.
}


@end
