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

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    IMLogConfigure();
    [[IMNetworkMonitor shared] start];        // 网络类型实时源（自动下载决策用，M4-7）
    [[IMDownloadSettingsStore shared] start];  // 自动下载策略：拉取 + 监听 capabilities_update 重拉（登录后 token 就绪即拉）
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
