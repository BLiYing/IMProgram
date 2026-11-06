#import "IMRtcConfig.h"

static NSString * const kIMRtcWSURLOverrideKey = @"im_rtc_ws_url_override";

@implementation IMRtcConfig

+ (instancetype)load {
    NSString *override = [self normalizedWSURL:[NSUserDefaults.standardUserDefaults stringForKey:kIMRtcWSURLOverrideKey]];
    if (override) { return [[self alloc] initWithDictionary:@{ @"wsUrl": override }]; }
    NSString *path = [NSBundle.mainBundle pathForResource:@"IMRtcConfig.local" ofType:@"plist"];
    return [[self alloc] initWithDictionary:path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil];
}

+ (NSString *)normalizedWSURL:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0
        || [trimmed rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
        return nil;
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
    NSString *scheme = components.scheme.lowercaseString;
    BOOL isWebSocket = [scheme isEqualToString:@"ws"] || [scheme isEqualToString:@"wss"];
    return isWebSocket && components.host.length > 0 ? trimmed : nil;
}

+ (void)saveWSURLOverride:(NSString *)wsURL {
    [NSUserDefaults.standardUserDefaults setObject:wsURL forKey:kIMRtcWSURLOverrideKey]; // nil = 删除
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    if ((self = [super init])) {
        _wsURL = [self trimmed:dict[@"wsUrl"]];
    }
    return self;
}

- (NSString *)trimmed:(id)value {
    return [value isKindOfClass:NSString.class]
        ? [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
}

- (NSArray<NSString *> *)missingKeys {
    NSMutableArray *missing = [NSMutableArray array];
    if (self.wsURL.length == 0) { [missing addObject:@"wsUrl"]; }
    return missing;
}

- (BOOL)isUsable { return self.missingKeys.count == 0; }

+ (NSString *)problemForID:(NSString *)identifier kind:(NSString *)kind {
    if (identifier.length == 0) { return [kind stringByAppendingString:@" 为空"]; }
    if ([identifier rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
        return [NSString stringWithFormat:@"%@ 含空白：%@", kind, identifier];
    }
    if ([identifier lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 64) {
        return [kind stringByAppendingString:@" 超过 64 字节"];
    }
    return nil;
}

@end
