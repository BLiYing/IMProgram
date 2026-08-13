//  IMDeviceModels.m

#import "IMDeviceModels.h"

#pragma mark - 脏数据安全取值（与 IMQRModels 同范式）

static NSString *IMDevString(NSDictionary *d, NSString *k) {
    id v = d[k];
    return [v isKindOfClass:NSString.class] ? v : @"";
}
static int64_t IMDevInt64(NSDictionary *d, NSString *k) {
    id v = d[k];
    return [v respondsToSelector:@selector(longLongValue)] ? [v longLongValue] : 0;
}
static BOOL IMDevBool(NSDictionary *d, NSString *k) {
    id v = d[k];
    return [v isKindOfClass:NSNumber.class] ? [v boolValue] : NO;
}

/// 平台 → 展示名。
static NSString *IMDevPlatformLabel(NSString *p) {
    if ([p isEqualToString:@"ios"]) { return @"iOS"; }
    if ([p isEqualToString:@"android"]) { return @"Android"; }
    if ([p isEqualToString:@"web"]) { return @"网页版"; }
    if ([p isEqualToString:@"desktop"]) { return @"桌面端"; }
    return @"未知设备";
}

/// 毫秒时间戳 → "刚刚 / X 分钟前活跃 / X 小时前活跃 / X 天前活跃"。
static NSString *IMDevRelativeActive(int64_t ms) {
    if (ms <= 0) { return @"离线"; }
    NSTimeInterval sec = NSDate.date.timeIntervalSince1970 - (NSTimeInterval)ms / 1000.0;
    if (sec < 0) { sec = 0; }
    if (sec < 60) { return @"刚刚活跃"; }
    if (sec < 3600) { return [NSString stringWithFormat:@"%ld 分钟前活跃", (long)(sec / 60)]; }
    if (sec < 86400) { return [NSString stringWithFormat:@"%ld 小时前活跃", (long)(sec / 3600)]; }
    return [NSString stringWithFormat:@"%ld 天前活跃", (long)(sec / 86400)];
}

@implementation IMDeviceSession

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) { return nil; }
    NSString *sid = IMDevString(dict, @"session_id");
    if (sid.length == 0) { return nil; }
    IMDeviceSession *s = [IMDeviceSession new];
    s.sessionID = sid;
    s.platform = IMDevString(dict, @"platform");
    s.deviceName = IMDevString(dict, @"device_name");
    s.appVersion = IMDevString(dict, @"app_version");
    s.loginIP = IMDevString(dict, @"login_ip");
    s.loginLoc = IMDevString(dict, @"login_loc");
    s.createdAt = IMDevInt64(dict, @"created_at");
    s.lastActiveAt = IMDevInt64(dict, @"last_active_at");
    s.online = IMDevBool(dict, @"online");
    s.current = IMDevBool(dict, @"current");
    return s;
}

+ (NSArray<IMDeviceSession *> *)fromArray:(NSArray *)arr {
    if (![arr isKindOfClass:NSArray.class]) { return @[]; }
    NSMutableArray<IMDeviceSession *> *out = [NSMutableArray arrayWithCapacity:arr.count];
    for (id item in arr) {
        IMDeviceSession *s = [IMDeviceSession fromDictionary:item];
        if (s) { [out addObject:s]; }
    }
    return out;
}

- (NSString *)platformEmoji {
    if ([self.platform isEqualToString:@"ios"]) { return @"📱"; }
    if ([self.platform isEqualToString:@"android"]) { return @"🤖"; }
    if ([self.platform isEqualToString:@"web"]) { return @"💻"; }
    if ([self.platform isEqualToString:@"desktop"]) { return @"🖥"; }
    return @"📟";
}

- (NSString *)platformLabel { return IMDevPlatformLabel(self.platform); }

- (NSString *)statusLine {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (self.online) {
        [parts addObject:@"在线"];
        [parts addObject:IMDevPlatformLabel(self.platform)];
    } else {
        [parts addObject:IMDevRelativeActive(self.lastActiveAt)];
    }
    if (self.loginLoc.length > 0) { [parts addObject:self.loginLoc]; }
    if (self.loginIP.length > 0) { [parts addObject:self.loginIP]; }
    return [parts componentsJoinedByString:@" · "];
}

- (NSString *)lastActiveText { return IMDevRelativeActive(self.lastActiveAt); }

- (NSString *)loginTimeText {
    if (self.createdAt <= 0) { return @"—"; }
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd HH:mm";
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)self.createdAt / 1000.0]];
}

@end
