//  IMDownloadSettings.m

#import "IMDownloadSettings.h"

static const int64_t kMB = 1LL << 20;

@implementation IMDownloadCategoryRule
@end

@implementation IMDownloadNetworkPolicy
@end

@implementation IMDownloadSettings

+ (IMDownloadCategoryRule *)ruleSingle:(BOOL)single group:(BOOL)group maxBytes:(int64_t)maxBytes {
    IMDownloadCategoryRule *r = [IMDownloadCategoryRule new];
    r.single = single;
    r.group = group;
    r.maxBytes = maxBytes;
    return r;
}

+ (IMDownloadNetworkPolicy *)policyEnabled:(BOOL)enabled videoMax:(int64_t)videoMax fileMax:(int64_t)fileMax {
    IMDownloadNetworkPolicy *p = [IMDownloadNetworkPolicy new];
    p.enabled = enabled;
    p.image = [self ruleSingle:YES group:YES maxBytes:0];          // 图片无上限
    p.video = [self ruleSingle:YES group:YES maxBytes:videoMax];
    p.file = [self ruleSingle:YES group:YES maxBytes:fileMax];
    return p;
}

+ (instancetype)defaultSettings {
    IMDownloadSettings *s = [IMDownloadSettings new];
    s.version = 0;
    s.cellular = [self policyEnabled:YES videoMax:10 * kMB fileMax:1 * kMB]; // 中档
    s.wifi = [self policyEnabled:YES videoMax:15 * kMB fileMax:3 * kMB];     // 高档
    return s;
}

#pragma mark - 解析（容错：缺字段回退默认对应项）

static BOOL IMBoolFromJSON(NSDictionary *json, NSString *key, BOOL fallback) {
    id v = json[key];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : fallback;
}

static int64_t IMInt64FromJSON(NSDictionary *json, NSString *key, int64_t fallback) {
    id v = json[key];
    return [v isKindOfClass:[NSNumber class]] ? [v longLongValue] : fallback;
}

+ (IMDownloadCategoryRule *)ruleFromJSON:(id)json fallback:(IMDownloadCategoryRule *)fallback {
    if (![json isKindOfClass:[NSDictionary class]]) { return fallback; }
    NSDictionary *d = json;
    return [self ruleSingle:IMBoolFromJSON(d, @"single", fallback.single)
                      group:IMBoolFromJSON(d, @"group", fallback.group)
                   maxBytes:IMInt64FromJSON(d, @"max_bytes", fallback.maxBytes)];
}

+ (IMDownloadNetworkPolicy *)policyFromJSON:(id)json fallback:(IMDownloadNetworkPolicy *)fallback {
    if (![json isKindOfClass:[NSDictionary class]]) { return fallback; }
    NSDictionary *d = json;
    IMDownloadNetworkPolicy *p = [IMDownloadNetworkPolicy new];
    p.enabled = IMBoolFromJSON(d, @"enabled", fallback.enabled);
    p.image = [self ruleFromJSON:d[@"image"] fallback:fallback.image];
    p.video = [self ruleFromJSON:d[@"video"] fallback:fallback.video];
    p.file = [self ruleFromJSON:d[@"file"] fallback:fallback.file];
    return p;
}

static NSDictionary *IMRuleToJSON(IMDownloadCategoryRule *r) {
    return @{ @"single": @(r.single), @"group": @(r.group), @"max_bytes": @(r.maxBytes) };
}

static NSDictionary *IMPolicyToJSON(IMDownloadNetworkPolicy *p) {
    return @{ @"enabled": @(p.enabled), @"image": IMRuleToJSON(p.image),
              @"video": IMRuleToJSON(p.video), @"file": IMRuleToJSON(p.file) };
}

- (NSDictionary *)toSettingsDictionary {
    return @{ @"cellular": IMPolicyToJSON(self.cellular), @"wifi": IMPolicyToJSON(self.wifi) };
}

- (instancetype)deepCopy {
    IMDownloadSettings *c = [IMDownloadSettings fromJSON:@{ @"settings": [self toSettingsDictionary] }];
    c.version = self.version;
    return c;
}

- (BOOL)isEquivalentTo:(IMDownloadSettings *)other {
    if (!other) { return NO; }
    return [[self toSettingsDictionary] isEqualToDictionary:[other toSettingsDictionary]];
}

+ (instancetype)fromJSON:(NSDictionary *)root {
    IMDownloadSettings *def = [self defaultSettings];
    if (![root isKindOfClass:[NSDictionary class]]) { return def; }
    // 兼容 {version, settings:{cellular,wifi}}（GET 的 data）与直接 {cellular,wifi}。
    NSDictionary *settings = [root[@"settings"] isKindOfClass:[NSDictionary class]] ? root[@"settings"] : root;
    IMDownloadSettings *s = [IMDownloadSettings new];
    s.version = IMInt64FromJSON(root, @"version", 0);
    s.cellular = [self policyFromJSON:settings[@"cellular"] fallback:def.cellular];
    s.wifi = [self policyFromJSON:settings[@"wifi"] fallback:def.wifi];
    return s;
}

@end
