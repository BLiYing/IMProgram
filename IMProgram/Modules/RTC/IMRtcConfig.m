#import "IMRtcConfig.h"

@implementation IMRtcConfig

+ (instancetype)load {
    NSString *path = [NSBundle.mainBundle pathForResource:@"IMRtcConfig.local" ofType:@"plist"];
    return [[self alloc] initWithDictionary:path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    if ((self = [super init])) {
        _wsURL = [self trimmed:dict[@"wsUrl"]];
        _appID = [self trimmed:dict[@"appId"]];
        _keyID = [self trimmed:dict[@"keyId"]];
        _debugSecret = [self trimmed:dict[@"debugSecret"]];
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
    if (self.appID.length == 0) { [missing addObject:@"appId"]; }
    if (self.keyID.length == 0) { [missing addObject:@"keyId"]; }
    if (self.debugSecret.length == 0) { [missing addObject:@"debugSecret"]; }
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
