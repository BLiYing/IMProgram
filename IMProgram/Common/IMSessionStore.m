//  IMSessionStore.m

#import "IMSessionStore.h"

static NSString * const kIMSessionHostKey     = @"im_session_host";
static NSString * const kIMSessionUserIDKey   = @"im_session_uid";      // 内部 ID（业务用）
static NSString * const kIMSessionUsernameKey  = @"im_session_username"; // 公开句柄（登录用）
static NSString * const kIMSessionPasswordKey = @"im_session_pwd";
static NSString * const kIMSessionSchemeKey   = @"im_session_scheme";  // http / https

// 说明：password 暂存 NSUserDefaults。理由——本工程是开发骨架（ws:// + NSAllowsArbitraryLoads），
// 且用户以未签名方式（CODE_SIGNING_ALLOWED=NO）装模拟器，Keychain 无 entitlement 会静默失败、导致
// 保持登录失效。生产签名后应改回 Keychain（SecItem*）。见 CONVENTIONS 安全约定。
@implementation IMSessionStore

+ (void)saveHost:(NSString *)host
          userID:(NSString *)userID
        username:(NSString *)username
        password:(NSString *)password {
    if (userID.length == 0) { return; }
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:(host ?: @"") forKey:kIMSessionHostKey];
    [d setObject:userID forKey:kIMSessionUserIDKey];
    [d setObject:(username ?: @"") forKey:kIMSessionUsernameKey];
    [d setObject:(password ?: @"") forKey:kIMSessionPasswordKey];
    [d synchronize];
}

+ (BOOL)hasSession {
    return [NSUserDefaults.standardUserDefaults stringForKey:kIMSessionUserIDKey].length > 0;
}

+ (NSString *)host {
    return [NSUserDefaults.standardUserDefaults stringForKey:kIMSessionHostKey];
}

+ (NSString *)scheme {
    return [NSUserDefaults.standardUserDefaults stringForKey:kIMSessionSchemeKey];
}

+ (void)saveScheme:(NSString *)scheme {
    if (scheme.length == 0) { return; }
    [NSUserDefaults.standardUserDefaults setObject:scheme forKey:kIMSessionSchemeKey];
}

+ (NSString *)userID {
    return [NSUserDefaults.standardUserDefaults stringForKey:kIMSessionUserIDKey];
}

+ (NSString *)username {
    return [NSUserDefaults.standardUserDefaults stringForKey:kIMSessionUsernameKey];
}

+ (NSString *)password {
    return [NSUserDefaults.standardUserDefaults stringForKey:kIMSessionPasswordKey];
}

+ (void)clear {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d removeObjectForKey:kIMSessionUserIDKey];
    [d removeObjectForKey:kIMSessionUsernameKey];
    [d removeObjectForKey:kIMSessionPasswordKey];
    // host / scheme 保留（下次登录默认回填方便；协议是"连哪台服务器"的属性，不随账号走）。
    [d synchronize];
}

@end
