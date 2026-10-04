//
//  AppDelegate.m
//  IMProgram
//
//  Created by liying on 2026/6/13.
//

#import "AppDelegate.h"
#import "IMLog.h"
#import "IMNetworkMonitor.h"
#import "IMPowerSaving.h"
#import "IMDownloadSettingsStore.h"
#import "IMServerConfigStore.h"
#import "IMPushTokenManager.h"
#import "IMAccountNotifySettingsSync.h"
#import "IMPendingNotificationRoute.h"
#import "IMPushRetract.h"
#import <UserNotifications/UserNotifications.h>

@interface AppDelegate () <UNUserNotificationCenterDelegate>

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    IMLogConfigure();
    // B0/B5 基线的**冷启动起点**（OFFLINE_BACKLOG_DESIGN §5）。iOS 没有桌面端 `--perf` 那样的
    // 测量入口，三个动作的耗时只能从 dev-logsink 日志里按时间戳相减算，所以这几个低频标记
    // 是唯一的量具。终点是会话列表的 conv_list_visible。
    IMLog(@"app_launched");
    // M5：尽早设 delegate——冷启动可能在系统早期就回调 didReceiveNotificationResponse（点通知冷启）。
    UNUserNotificationCenter.currentNotificationCenter.delegate = self;
    [[IMPowerSaving shared] start];           // 省电模式：电量 / 低电量模式监听 + 自动开启提示（本机数据，与登录无关）
    [[IMNetworkMonitor shared] start];        // 网络类型实时源（自动下载决策用，M4-7）
    [[IMDownloadSettingsStore shared] start];  // 自动下载策略：拉取 + 监听 capabilities_update 重拉（登录后 token 就绪即拉）
    [[IMServerConfigStore shared] start];      // 部署级配额/能力（群上限、是否提供超级群）：登录后拉一次
    [[IMPushTokenManager shared] start];             // M5：登录/每次(重)连即尝试注册推送令牌
    [[IMAccountNotifySettingsSync shared] start];    // M5：账号级通知设置迁移/多端同步
    return YES;
}

#pragma mark - 推送令牌注册回调（M5，转发给 IMPushTokenManager）

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    [IMPushTokenManager.shared didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    [IMPushTokenManager.shared didFailToRegisterForRemoteNotificationsWithError:error];
}

/// 带 content-available 的推送把挂起中的 App 唤醒（M5，PUSH_M5_DESIGN §3.5）：目前只有「已读清通知」一种——
/// 本人在别的设备上读过了，删掉通知中心里该会话已读的那几条（角标已由推送本身改好）。
/// 前台收到的普通推送也会走到这里，认不出是清通知就什么都不做。
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
    fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler {
    NSString *convID = nil;
    int64_t upTo = 0;
    if (!IMPushReadClearFromPayload(userInfo, &convID, &upTo)) {
        completionHandler(UIBackgroundFetchResultNoData);
        return;
    }
    IMLogPush(@"push_read_clear_received conv_id=%@ up_to=%lld", convID, upTo);
    IMPushClearDeliveredNotificationsReadThrough(convID, upTo, ^{
        completionHandler(UIBackgroundFetchResultNoData);
    });
}

#pragma mark - UNUserNotificationCenterDelegate（M5）

/// App 在前台收到通知：不弹系统横幅/提示音——应用内横幅逻辑（NOTIFICATIONS_DESIGN §3.1 banner）已经
/// 覆盖前台提醒，两套机制同时响会重复提醒用户。
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
        willPresentNotification:(UNNotification *)notification
          withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    completionHandler(UNNotificationPresentationOptionNone);
}

/// 点击通知（含冷启动点击）：取 conv_id 记入 IMPendingNotificationRoute，待主界面就绪后打开会话
/// （PUSH_M5_DESIGN §3.2、PROTOCOL §6.14 APNs payload 的 conv_id）。
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
 didReceiveNotificationResponse:(UNNotificationResponse *)response
          withCompletionHandler:(void (^)(void))completionHandler {
    NSString *convID = IMPushConvIDFromUserInfo(response.notification.request.content.userInfo);
    if (convID.length > 0) {
        IMLogPush(@"push_tap_received conv_id=%@", convID);
        [IMPendingNotificationRoute.shared setPendingConvID:convID title:response.notification.request.content.title];
    }
    completionHandler();
}


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}


@end
