//  IMPushTokenManager.m

#import "IMPushTokenManager.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Push.h"
#import "IMSocketManager.h"
#import "IMPushSettings.h"
#import "IMLocalization.h"
#import "IMLog.h"
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

#pragma mark - 纯函数

NSString *IMPushTokenHexFromData(NSData *tokenData) {
    if (tokenData.length == 0) { return @""; }
    const unsigned char *bytes = tokenData.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:tokenData.length * 2];
    for (NSUInteger i = 0; i < tokenData.length; i++) { [hex appendFormat:@"%02x", bytes[i]]; }
    return [hex copy];
}

NSString *IMPushEnvironmentFromMobileProvisionData(NSData *rawMobileProvisionData) {
    static NSString * const kSandbox = @"sandbox";
    static NSString * const kProduction = @"production";
    if (rawMobileProvisionData.length == 0) { return kProduction; }
    // CMS 二进制信封整体按 Latin1 解码：每字节 1:1 映射成一个字符，既能在其中搜到 ASCII 标记
    // （<?xml / </plist>），转回 NSData 时字节也原样还原——不会像 UTF-8 那样因非法序列丢字节。
    NSString *raw = [[NSString alloc] initWithData:rawMobileProvisionData encoding:NSISOLatin1StringEncoding];
    if (raw.length == 0) { return kProduction; }
    NSRange start = [raw rangeOfString:@"<?xml"];
    NSRange end = [raw rangeOfString:@"</plist>"];
    if (start.location == NSNotFound || end.location == NSNotFound || end.location < start.location) {
        return kProduction;
    }
    NSUInteger endLoc = end.location + end.length;
    NSString *plistString = [raw substringWithRange:NSMakeRange(start.location, endLoc - start.location)];
    NSData *plistData = [plistString dataUsingEncoding:NSISOLatin1StringEncoding];
    if (plistData.length == 0) { return kProduction; }
    NSError *parseError = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:plistData
                                                           options:NSPropertyListImmutable
                                                            format:NULL
                                                             error:&parseError];
    if (![plist isKindOfClass:NSDictionary.class]) { return kProduction; }
    NSDictionary *entitlements = [(NSDictionary *)plist objectForKey:@"Entitlements"];
    NSString *aps = [entitlements isKindOfClass:NSDictionary.class] ? entitlements[@"aps-environment"] : nil;
    if ([aps isEqualToString:@"development"]) { return kSandbox; }
    return kProduction; // "production" 或字段缺失/未知值：保守回退生产（详见 .h 注释）
}

NSString *IMPushEnvironmentDetect(void) {
    NSString *path = [NSBundle.mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
    if (path.length == 0) { return @"production"; } // App Store 包没有这个文件
    NSData *data = [NSData dataWithContentsOfFile:path];
    return IMPushEnvironmentFromMobileProvisionData(data);
}

#pragma mark - 编排

@implementation IMPushTokenManager {
    BOOL _started;
}

+ (instancetype)shared {
    static IMPushTokenManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMPushTokenManager new]; });
    return s;
}

- (void)start {
    if (_started) { return; }
    _started = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(onSocketStateChanged:)
                                                name:IMSocketDidChangeStateNotification object:nil];
}

- (void)onSocketStateChanged:(NSNotification *)note {
    if ([note.userInfo[@"state"] integerValue] == IMSocketStateConnected) { [self registerIfEligible]; }
}

- (void)requestAuthorizationOnFirstMainScreen {
    UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
    __weak typeof(self) ws = self;
    [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:options
                                                                       completionHandler:^(BOOL granted, NSError *error) {
        if (error) {
            IMLogWarnWithTag(IMLogTagPush, @"notif_authorization_request_failed error=%@", error.localizedDescription ?: @"-");
        }
        IMLogPush(@"notif_authorization_result granted=%d", granted);
        dispatch_async(dispatch_get_main_queue(), ^{ [ws registerIfEligible]; });
    }];
}

- (void)registerIfEligible {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; } // 未登录
    if (!IMPushSettings.shared.receiveOfflinePush) { return; } // 本设备已关闭「接收离线推送」
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        BOOL authorized = settings.authorizationStatus == UNAuthorizationStatusAuthorized
            || settings.authorizationStatus == UNAuthorizationStatusProvisional
            || settings.authorizationStatus == UNAuthorizationStatusEphemeral;
        if (!authorized) { return; } // 未决定/已拒绝：不强弹，等用户在设置页或主页首次授权流程里处理
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication.sharedApplication registerForRemoteNotifications];
        });
    }];
}

- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    NSString *hex = IMPushTokenHexFromData(deviceToken);
    if (hex.length == 0) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) {
        IMLogWarnWithTag(IMLogTagPush, @"push_token_register_skip_not_logged_in");
        return;
    }
    NSString *environment = IMPushEnvironmentDetect();
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
    NSString *locale = IMLocalization.shared.language; // 已是 zh-Hans/en，与服务端字段同口径，无需再映射
    IMLogPush(@"push_token_register environment=%@ locale=%@ bundle_id=%@", environment, locale, bundleID);
    [IMHTTPService.sharedService registerPushTokenWithToken:token
                                                     provider:@"apns"
                                               deviceTokenHex:hex
                                                  environment:environment
                                                     bundleID:bundleID
                                                       locale:locale
                                                   completion:^(NSError *error) {
        if (error) {
            IMLogWarnWithTag(IMLogTagPush, @"push_token_register_failed error=%@", error.localizedDescription ?: @"-");
        } else {
            IMLogPush(@"push_token_register_ok");
        }
    }];
}

- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    IMLogWarnWithTag(IMLogTagPush, @"push_token_apns_register_failed error=%@", error.localizedDescription ?: @"-");
}

- (void)disableAndDeleteToken {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    [IMHTTPService.sharedService deletePushTokenWithToken:token completion:^(NSError *error) {
        if (error) {
            IMLogWarnWithTag(IMLogTagPush, @"push_token_delete_failed error=%@", error.localizedDescription ?: @"-");
        } else {
            IMLogPush(@"push_token_deleted");
        }
    }];
}

- (void)enableAndRegisterIfAuthorized {
    [self registerIfEligible];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
