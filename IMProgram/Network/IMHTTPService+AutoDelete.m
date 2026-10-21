//  IMHTTPService+AutoDelete.m

#import "IMHTTPService+AutoDelete.h"
#import "IMHTTPService+Private.h"
#import "IMAutoDelete.h"
#import "IMLocalization.h"

@implementation IMHTTPService (AutoDelete)

- (void)updateConversationSettingsWithToken:(NSString *)token convID:(NSString *)convID
                                   pinnedAt:(int64_t)pinnedAt muted:(BOOL)muted muteUntil:(NSNumber *)muteUntil
                               markedUnread:(BOOL)markedUnread autoDeleteSec:(NSNumber *)autoDeleteSec
                                 completion:(void (^)(NSError *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/v1/conversations/%@/settings",
                      [convID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet] ?: @""];
    NSMutableDictionary *body = [@{ @"pinned_at": @(pinnedAt), @"muted": @(muted), @"marked_unread": @(markedUnread) } mutableCopy];
    if (muteUntil) { body[@"mute_until"] = muteUntil; } // 省略即让服务端保留未到期的原值（PROTOCOL.md §6.10）
    // 省略 = 服务端保留库里原值（PROTOCOL §6.8.1）：只改置顶 / 免打扰时不带，既不会清零，也不会拿本机可能过期的
    // 缓存（升级后小表还是空的 / 别端刚改而本机还没收到 conv_update）盖掉别端刚设的档位。只有显式改档位才带。
    if (autoDeleteSec) { body[@"auto_delete_sec"] = autoDeleteSec; }
    NSMutableURLRequest *req = [self authedRequestForPath:path method:@"PUT" token:token body:body];
    [self runOKRequest:req fallback:IMLocalized(@"conv.error.settings_failed") completion:completion];
}

- (void)fetchAutoDeleteDefaultWithToken:(NSString *)token completion:(void (^)(int64_t, NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/privacy" method:@"GET" token:token body:nil];
    [self runDataRequest:req fallback:IMLocalized(@"autodel.save_failed") completion:^(NSDictionary *data, NSError *error) {
        completion(error ? 0 : IMAutoDeleteSecFromJSON(data[@"auto_delete_default_sec"]), error);
    }];
}

- (void)saveAutoDeleteDefault:(int64_t)sec token:(NSString *)token completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *req = [self authedRequestForPath:@"/api/v1/users/me/privacy" method:@"PUT" token:token
                                                     body:@{ @"auto_delete_default_sec": @(sec) }];
    [self runOKRequest:req fallback:IMLocalized(@"autodel.save_failed") completion:completion];
}

@end
