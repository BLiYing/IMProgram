//  IMHTTPService+Push.m

#import "IMHTTPService+Push.h"
#import "IMHTTPService+Private.h"
#import "IMLocalization.h"

@implementation IMHTTPService (Push)

- (void)registerPushTokenWithToken:(NSString *)token
                           provider:(NSString *)provider
                     deviceTokenHex:(NSString *)deviceTokenHex
                        environment:(NSString *)environment
                           bundleID:(NSString *)bundleID
                             locale:(NSString *)locale
                         completion:(void (^)(NSError *_Nullable error))completion {
    NSDictionary *body = @{
        @"provider":    provider ?: @"apns",
        @"token":       deviceTokenHex ?: @"",
        @"environment": environment ?: @"production",
        @"bundle_id":   bundleID ?: @"",
        @"locale":      locale ?: @"en",
    };
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/push/token" method:@"PUT" token:token body:body];
    [self runOKRequest:req fallback:IMLocalized(@"common.action_failed") completion:completion];
}

- (void)deletePushTokenWithToken:(NSString *)token
                       completion:(void (^)(NSError *_Nullable error))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/push/token" method:@"DELETE" token:token body:nil];
    [self runOKRequest:req fallback:IMLocalized(@"common.action_failed") completion:completion];
}

- (void)notifySettingsWithToken:(NSString *)token
                      completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/notify-settings" method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:IMLocalized(@"common.action_failed") completion:completion];
}

- (void)updateNotifySettingsWithToken:(NSString *)token
                              settings:(NSDictionary *)settings
                            completion:(void (^)(NSDictionary *_Nullable data, NSError *_Nullable error))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/notify-settings" method:@"PUT" token:token
                                                       body:@{ @"settings": settings ?: @{} }];
    [self runDataRequest:req fallback:IMLocalized(@"common.action_failed") completion:completion];
}

@end
