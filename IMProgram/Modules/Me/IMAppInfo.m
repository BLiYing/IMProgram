//  IMAppInfo.m

#import "IMAppInfo.h"
#import "IMServerEndpoint.h"
#import "IMLocalization.h"

NSString *const IMLegalPathPrivacy = @"/legal/privacy";
NSString *const IMLegalPathTerms = @"/legal/terms";
NSString *const IMLegalPathSupport = @"/support";

@implementation IMAppInfo

+ (NSString *)versionStringWithShortVersion:(NSString *)shortVersion build:(NSString *)build {
    BOOL hasShort = shortVersion.length > 0, hasBuild = build.length > 0;
    if (hasShort && hasBuild) { return [NSString stringWithFormat:@"%@ (%@)", shortVersion, build]; }
    if (hasShort) { return shortVersion; }
    if (hasBuild) { return build; }
    return @"-";
}

+ (NSString *)versionString {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return [self versionStringWithShortVersion:info[@"CFBundleShortVersionString"] build:info[@"CFBundleVersion"]];
}

+ (NSString *)versionClipboardString {
    return [@"iOS " stringByAppendingString:[self versionString]];
}

+ (NSURL *)legalURLForPath:(NSString *)path host:(NSString *)host language:(NSString *)language {
    return [self legalURLForPath:path host:host scheme:IMServerEndpoint.shared.scheme language:language];
}

+ (NSURL *)legalURLForPath:(NSString *)path host:(NSString *)host scheme:(NSString *)scheme language:(NSString *)language {
    static NSSet<NSString *> *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ allowed = [NSSet setWithObjects:IMLegalPathPrivacy, IMLegalPathTerms, IMLegalPathSupport, nil]; });
    if (host.length == 0 || ![allowed containsObject:path]) { return nil; }
    NSString *s = scheme.length > 0 ? scheme : IMServerSchemeHTTP;
    NSString *lang = [language isEqualToString:@"en"] ? @"en" : @"zh-Hans";
    // 与 IMServerEndpoint.httpURLForHost 同样的拼法，但 scheme 显式传入、不读也不改共享单例。
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@?lang=%@", s, host, path, lang]];
}

@end
