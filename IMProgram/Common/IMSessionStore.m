//  IMSessionStore.m

#import "IMSessionStore.h"

static NSString * const kIMSessionHostKey     = @"im_session_host";
static NSString * const kIMSessionUserIDKey   = @"im_session_uid";      // 内部 ID（业务用）
static NSString * const kIMSessionUsernameKey  = @"im_session_username"; // 公开句柄（登录用）
static NSString * const kIMSessionPasswordKey = @"im_session_pwd";     // **遗留**：仅供一次性迁移读取后删除
static NSString * const kIMSessionSchemeKey   = @"im_session_scheme";  // http / https
static NSString * const kIMSessionRefreshKey  = @"im_session_refresh"; // 续期凭据（替代明文密码）

// 说明：这里存的是**续期凭据**而非账号明文密码（2026-09-03 起，理由见 .h 头注释）。
// 仍落 NSUserDefaults 而非 Keychain：未签名装机（CODE_SIGNING_ALLOWED=NO）下 Keychain 无
// entitlement 会静默失败、保持登录直接不可用。凭据可吊销且只作用于本设备，故这个折中可接受；
// 迁 Keychain 是签名之后的另一件事。
@implementation IMSessionStore

+ (void)saveHost:(NSString *)host
          userID:(NSString *)userID
        username:(NSString *)username {
    if (userID.length == 0) { return; }
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:(host ?: @"") forKey:kIMSessionHostKey];
    [d setObject:userID forKey:kIMSessionUserIDKey];
    [d setObject:(username ?: @"") forKey:kIMSessionUsernameKey];
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

+ (NSString *)refreshToken {
    NSString *t = [NSUserDefaults.standardUserDefaults stringForKey:kIMSessionRefreshKey];
    return t.length > 0 ? t : nil;
}

+ (void)saveRefreshToken:(NSString *)token {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (token.length == 0) {
        [d removeObjectForKey:kIMSessionRefreshKey];
    } else {
        [d setObject:token forKey:kIMSessionRefreshKey];
    }
    [d synchronize];
}

+ (NSString *)legacyPassword {
    NSString *p = [NSUserDefaults.standardUserDefaults stringForKey:kIMSessionPasswordKey];
    return p.length > 0 ? p : nil;
}

+ (void)clearLegacyPassword {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kIMSessionPasswordKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

+ (void)clear {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d removeObjectForKey:kIMSessionUserIDKey];
    [d removeObjectForKey:kIMSessionUsernameKey];
    [d removeObjectForKey:kIMSessionRefreshKey];
    [d removeObjectForKey:kIMSessionPasswordKey]; // 遗留明文密码：退登也一并擦掉
    // host / scheme 保留（下次登录默认回填方便；协议是"连哪台服务器"的属性，不随账号走）。
    [d synchronize];
}

@end
