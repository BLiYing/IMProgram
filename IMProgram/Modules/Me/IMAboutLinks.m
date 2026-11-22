//  IMAboutLinks.m

#import "IMAboutLinks.h"
#import "IMAppInfo.h"
#import "IMLog.h"
#import "IMServerEndpoint.h"

NSString *const IMAboutLinkFieldPrivacy = @"privacy_url";
NSString *const IMAboutLinkFieldTerms = @"terms_url";
NSString *const IMAboutLinkFieldSupport = @"support_url";
NSString *const IMAboutLinkFieldCustomerService = @"customer_service_url";
NSString *const IMCSLinkKeyName = @"name";
NSString *const IMCSLinkKeyURL = @"url";

@interface IMAboutLinks ()
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *links;
@property (nonatomic, copy, nullable) NSArray<NSDictionary<NSString *, NSString *> *> *csLinks;
@property (nonatomic, copy, nullable) NSString *cacheKey;
@end

@implementation IMAboutLinks

+ (instancetype)shared {
    static IMAboutLinks *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [IMAboutLinks new]; });
    return inst;
}

+ (NSArray<NSString *> *)allFields {
    return @[IMAboutLinkFieldPrivacy, IMAboutLinkFieldTerms, IMAboutLinkFieldSupport, IMAboutLinkFieldCustomerService];
}

+ (NSString *)keyForScheme:(NSString *)scheme host:(NSString *)host {
    return [NSString stringWithFormat:@"%@://%@", scheme.length > 0 ? scheme : IMServerSchemeHTTP, host ?: @""];
}

- (NSDictionary<NSString *, NSString *> *)cachedLinksForScheme:(NSString *)scheme host:(NSString *)host {
    if (host.length == 0) { return nil; }
    @synchronized (self) {
        return [self.cacheKey isEqualToString:[IMAboutLinks keyForScheme:scheme host:host]] ? self.links : nil;
    }
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)cachedCSLinksForScheme:(NSString *)scheme host:(NSString *)host {
    if (host.length == 0) { return nil; }
    @synchronized (self) {
        return [self.cacheKey isEqualToString:[IMAboutLinks keyForScheme:scheme host:host]] ? self.csLinks : nil;
    }
}

- (void)refreshWithScheme:(NSString *)scheme host:(NSString *)host token:(NSString *)token
                  timeout:(NSTimeInterval)timeout completion:(void (^)(BOOL))completion {
    void (^finish)(BOOL) = ^(BOOL ok) {
        if (!completion) { return; }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(ok); });
    };
    if (host.length == 0) { finish(NO); return; }
    NSString *s = scheme.length > 0 ? scheme : IMServerSchemeHTTP;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/api/v1/about-links", s, host]];
    if (!url) { finish(NO); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = timeout > 0 ? timeout : 8;
    if (token.length > 0) { [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"]; }
    NSString *key = [IMAboutLinks keyForScheme:s host:host];
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        NSDictionary *parsed = error ? nil : [IMAboutLinks linksFromResponseData:data];
        if (!parsed) {
            // 老服务端 404 / 离线 / 异常响应都走这里：静默回退内置路径，只留一条 warn 便于排障。
            IMLogWarnWithTag(IMLogTagHTTP, @"about_links_fetch_failed host=%@ err=%@", host, error.localizedDescription ?: @"bad_response");
            finish(NO);
            return;
        }
        NSArray *cs = [IMAboutLinks csLinksFromResponseData:data];
        @synchronized (self) { self.links = parsed; self.csLinks = cs; self.cacheKey = key; }
        finish(YES);
    }] resume];
}

/// 信封 → data 字典；code≠0 / 非 JSON / data 缺失 → nil（四链接与 cs_links 共用一次解析口径）。
+ (nullable NSDictionary *)envelopeDataFromResponseData:(NSData *)data {
    if (data.length == 0) { return nil; }
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:NSDictionary.class]) { return nil; }
    // code 可能是 null / 字符串：NSNull 没有 integerValue，直接发消息会崩。
    id code = root[@"code"];
    if (![code isKindOfClass:NSNumber.class] || [code integerValue] != 0) { return nil; }
    NSDictionary *d = root[@"data"];
    return [d isKindOfClass:NSDictionary.class] ? d : nil;
}

+ (NSDictionary<NSString *, NSString *> *)linksFromResponseData:(NSData *)data {
    NSDictionary *d = [self envelopeDataFromResponseData:data];
    if (!d) { return nil; }
    NSMutableDictionary<NSString *, NSString *> *out = [NSMutableDictionary dictionary];
    for (NSString *f in [self allFields]) {
        if ([d[f] isKindOfClass:NSString.class]) { out[f] = d[f]; }
    }
    return out;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)csLinksFromResponseData:(NSData *)data {
    // 缺 cs_links（老服务端，或新服务端 0 条时省略）→ nil，由调用方退回 customer_service_url（0 条时它也是空串 → 隐藏行），同 Web。
    id raw = [self envelopeDataFromResponseData:data][@"cs_links"];
    if (![raw isKindOfClass:NSArray.class]) { return nil; }
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSMutableArray *out = [NSMutableArray array];
    for (id item in (NSArray *)raw) {
        if (![item isKindOfClass:NSDictionary.class]) { continue; }
        NSString *u = [item[IMCSLinkKeyURL] isKindOfClass:NSString.class] ? [item[IMCSLinkKeyURL] stringByTrimmingCharactersInSet:ws] : nil;
        // 只收绝对 http(s)：先挡 "/" 开头（URLForConfigValue 会把它当本服务托管页），再交它校验 scheme 与主机。
        if ([u hasPrefix:@"/"] || ![self URLForConfigValue:u host:nil scheme:nil language:@""]) { continue; }
        NSString *n = [item[IMCSLinkKeyName] isKindOfClass:NSString.class] ? [item[IMCSLinkKeyName] stringByTrimmingCharactersInSet:ws] : @"";
        [out addObject:@{IMCSLinkKeyName: n, IMCSLinkKeyURL: u}];
    }
    return out;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)customerServiceEntriesWithCSLinks:(NSArray<NSDictionary<NSString *, NSString *> *> *)csLinks
                                                                                  links:(NSDictionary<NSString *, NSString *> *)links
                                                                                   host:(NSString *)host scheme:(NSString *)scheme
                                                                               language:(NSString *)language {
    if (csLinks) { return csLinks; }
    NSURL *u = [self URLForField:IMAboutLinkFieldCustomerService links:links host:host scheme:scheme language:language];
    return u ? @[@{IMCSLinkKeyName: @"", IMCSLinkKeyURL: u.absoluteString}] : @[];
}

+ (NSURL *)URLForConfigValue:(NSString *)value host:(NSString *)host scheme:(NSString *)scheme language:(NSString *)language {
    value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (value.length == 0) { return nil; }
    if ([value hasPrefix:@"/"]) {
        return [IMAppInfo legalURLForPath:value host:host scheme:scheme ?: IMServerSchemeHTTP language:language];
    }
    NSURL *url = [NSURL URLWithString:value];
    NSString *sch = url.scheme.lowercaseString;
    // 只放行 http(s)：后台是人填的，javascript:/file:/自定义 scheme 一律当非法。
    if (!url || !([sch isEqualToString:@"http"] || [sch isEqualToString:@"https"]) || url.host.length == 0) { return nil; }
    return url;
}

+ (NSURL *)URLForField:(NSString *)field links:(NSDictionary<NSString *, NSString *> *)links
                  host:(NSString *)host scheme:(NSString *)scheme language:(NSString *)language {
    NSString *value = links[field];
    if ([field isEqualToString:IMAboutLinkFieldCustomerService]) {
        return [self URLForConfigValue:value host:host scheme:scheme language:language];
    }
    NSURL *url = [self URLForConfigValue:value host:host scheme:scheme language:language];
    if (url) { return url; }
    // 法务页不可缺：没拉到 / 值非法 → 内置路径（与改造前行为一致）。
    NSString *builtin = [field isEqualToString:IMAboutLinkFieldPrivacy] ? IMLegalPathPrivacy
                      : [field isEqualToString:IMAboutLinkFieldTerms] ? IMLegalPathTerms : IMLegalPathSupport;
    return [IMAppInfo legalURLForPath:builtin host:host scheme:scheme ?: IMServerSchemeHTTP language:language];
}

#pragma mark - 客服 WebView 纯函数

NSString *const IMBeaconUAMarker = @"BeaconApp/";

+ (NSString *)beaconUserAgentWithBase:(NSString *)base version:(NSString *)version {
    base = base ?: @"";
    if ([base containsString:IMBeaconUAMarker]) { return base; }
    NSString *v = [version stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (v.length == 0) { v = @"0.0.0"; }
    NSString *tag = [NSString stringWithFormat:@"%@%@ (iOS)", IMBeaconUAMarker, v];
    return base.length == 0 ? tag : [NSString stringWithFormat:@"%@ %@", base, tag];
}

+ (IMAboutNavDecision)navigationDecisionForURL:(NSURL *)url {
    NSString *sch = url.scheme.lowercaseString;
    if (sch.length == 0) { return IMAboutNavDecisionBlock; }
    if ([sch isEqualToString:@"http"] || [sch isEqualToString:@"https"]) {
        return url.host.length > 0 ? IMAboutNavDecisionAllow : IMAboutNavDecisionBlock;
    }
    if ([sch isEqualToString:@"about"]) {
        return [url.absoluteString.lowercaseString isEqualToString:@"about:blank"] ? IMAboutNavDecisionAllow : IMAboutNavDecisionBlock;
    }
    static NSSet<NSString *> *blocked;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ blocked = [NSSet setWithArray:@[@"javascript", @"file", @"data", @"blob", @"vbscript", @"ftp"]]; });
    return [blocked containsObject:sch] ? IMAboutNavDecisionBlock : IMAboutNavDecisionExternal;
}

@end
