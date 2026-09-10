//
//  AppDelegate.m
//  IMProgram
//
//  Created by liying on 2026/6/13.
//

#import "AppDelegate.h"
#import "IMLog.h"
#import "IMNetworkMonitor.h"
#import "IMDownloadSettingsStore.h"
#import "IMServerConfigStore.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    IMLogConfigure();
    // B0/B5 基线的**冷启动起点**（OFFLINE_BACKLOG_DESIGN §5）。iOS 没有桌面端 `--perf` 那样的
    // 测量入口，三个动作的耗时只能从 dev-logsink 日志里按时间戳相减算，所以这几个低频标记
    // 是唯一的量具。终点是会话列表的 conv_list_visible。
    IMLog(@"app_launched");
    [[IMNetworkMonitor shared] start];        // 网络类型实时源（自动下载决策用，M4-7）
    [[IMDownloadSettingsStore shared] start];  // 自动下载策略：拉取 + 监听 capabilities_update 重拉（登录后 token 就绪即拉）
    [[IMServerConfigStore shared] start];      // 部署级配额/能力（群上限、是否提供超级群）：登录后拉一次
    return YES;
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
