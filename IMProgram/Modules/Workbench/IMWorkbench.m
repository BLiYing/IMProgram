//  IMWorkbench.m

#import "IMWorkbench.h"
#include <arpa/inet.h>

NSNotificationName const IMWorkbenchDidChangeNotification = @"IMWorkbenchDidChangeNotification";

/// 本机 / 内网主机：localhost、*.local、回环、私有网段（10/8、172.16/12、192.168/16、IPv6 ::1 与 fc00::/7）。
static BOOL IMWorkbenchIsLocalHost(NSString *host) {
    NSString *h = host.lowercaseString;
    if (h.length == 0) { return NO; }
    if ([h hasPrefix:@"["] && [h hasSuffix:@"]"]) { h = [h substringWithRange:NSMakeRange(1, h.length - 2)]; }
    if ([h isEqualToString:@"localhost"] || [h hasSuffix:@".local"]) { return YES; }
    // 纯数字加点的写法只认标准四段十进制、不许前导零：`010.x` 在浏览器里按八进制算成别的地址（三端同口径）
    if ([h rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789."].invertedSet].location == NSNotFound) {
        NSArray<NSString *> *parts = [h componentsSeparatedByString:@"."];
        if (parts.count != 4) { return NO; }
        for (NSString *p in parts) {
            if (p.length == 0 || p.length > 3 || (p.length > 1 && [p hasPrefix:@"0"]) || p.integerValue > 255) { return NO; }
        }
    }
    struct in_addr v4;
    if (inet_pton(AF_INET, h.UTF8String, &v4) == 1) {
        uint32_t ip = ntohl(v4.s_addr);
        uint8_t a = ip >> 24, b = (ip >> 16) & 0xff;
        return a == 127 || a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
    }
    struct in6_addr v6;
    if (inet_pton(AF_INET6, h.UTF8String, &v6) == 1) {
        static const uint8_t loop[16] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1};
        return memcmp(v6.s6_addr, loop, 16) == 0 || (v6.s6_addr[0] & 0xfe) == 0xfc;
    }
    return NO;
}

@implementation IMWorkbenchSection
- (instancetype)initWithTitle:(NSString *)title apps:(NSArray<NSDictionary *> *)apps {
    self = [super init];
    if (self) { _title = [title copy]; _apps = [apps copy]; }
    return self;
}
@end

@implementation IMWorkbench

+ (NSArray<IMWorkbenchSection *> *)sectionsFromGroups:(NSArray *)groups otherTitle:(NSString *)otherTitle soleTitle:(NSString *)soleTitle {
    NSMutableArray<IMWorkbenchSection *> *out = [NSMutableArray array];
    BOOL onlyUngrouped = YES;
    for (id g in ([groups isKindOfClass:NSArray.class] ? groups : @[])) {
        if (![g isKindOfClass:NSDictionary.class]) { continue; }
        NSArray *apps = [g[@"apps"] isKindOfClass:NSArray.class] ? g[@"apps"] : @[];
        NSMutableArray *valid = [NSMutableArray array];
        for (id a in apps) {
            if ([a isKindOfClass:NSDictionary.class] && [a[@"app_id"] isKindOfClass:NSString.class]) { [valid addObject:a]; }
        }
        if (valid.count == 0) { continue; }
        NSString *name = [g[@"name"] isKindOfClass:NSString.class]
            ? [g[@"name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
        if (name.length > 0) { onlyUngrouped = NO; }
        [out addObject:[[IMWorkbenchSection alloc] initWithTitle:(name.length > 0 ? name : otherTitle) apps:valid]];
    }
    if (out.count == 1 && onlyUngrouped && soleTitle.length > 0) {
        return @[[[IMWorkbenchSection alloc] initWithTitle:soleTitle apps:out.firstObject.apps]];
    }
    return out;
}

+ (BOOL)isAllowedWebURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    if (url.host.length == 0 || url.user.length > 0) { return NO; }
    if ([scheme isEqualToString:@"https"]) { return YES; }
    return [scheme isEqualToString:@"http"] && IMWorkbenchIsLocalHost(url.host);
}


+ (NSURL *)urlByRemovingTicket:(NSURL *)url {
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *query = c.percentEncodedQuery;
    if (!query) { return url; }
    // 按编码后的原文逐段过滤（不经 queryItems：那会把 %41 解码成 A，其余参数就变了）；键按解码后比对，im%5Fticket 也算
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        NSString *key = [pair componentsSeparatedByString:@"="].firstObject;
        if (pair.length > 0 && ![(key.stringByRemovingPercentEncoding ?: key) isEqualToString:@"im_ticket"]) { [kept addObject:pair]; }
    }
    c.percentEncodedQuery = kept.count > 0 ? [kept componentsJoinedByString:@"&"] : nil;
    return c.URL ?: url;
}

+ (NSString *)pickUnitIDFrom:(NSArray<NSDictionary<NSString *, NSString *> *> *)units saved:(NSString *)saved {
    for (NSDictionary *u in units) {
        if (saved.length > 0 && [u[@"unit_id"] isEqualToString:saved]) { return saved; }
    }
    return units.firstObject[@"unit_id"];
}

static NSString *IMWorkbenchUnitKey(NSString *userID) { return [@"im.workbench.unit." stringByAppendingString:userID ?: @""]; }

+ (NSString *)savedUnitIDForUser:(NSString *)userID {
    return [NSUserDefaults.standardUserDefaults stringForKey:IMWorkbenchUnitKey(userID)];
}

+ (void)saveUnitID:(NSString *)unitID forUser:(NSString *)userID {
    if (unitID.length == 0 || userID.length == 0) { return; }
    [NSUserDefaults.standardUserDefaults setObject:unitID forKey:IMWorkbenchUnitKey(userID)];
}

@end
