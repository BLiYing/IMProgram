//  IMPresence.m

#import "IMPresence.h"

/// 档位字符串 → 枚举（脏数据安全：未知串落 Unknown）。
static IMPresenceLevel IMPresenceLevelFromString(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) { return IMPresenceLevelUnknown; }
    if ([s isEqualToString:@"online"])     { return IMPresenceLevelOnline; }
    if ([s isEqualToString:@"recently"])   { return IMPresenceLevelRecently; }
    if ([s isEqualToString:@"last_week"])  { return IMPresenceLevelLastWeek; }
    if ([s isEqualToString:@"last_month"]) { return IMPresenceLevelLastMonth; }
    if ([s isEqualToString:@"long_ago"])   { return IMPresenceLevelLongAgo; }
    return IMPresenceLevelUnknown;
}

static int64_t IMPresenceInt64(NSDictionary *dict, NSString *key) {
    id v = dict[key];
    return [v respondsToSelector:@selector(longLongValue)] ? [v longLongValue] : 0;
}

@implementation IMPresence

+ (instancetype)presenceWithStatusKey:(NSString *)statusKey
                       onlineUntilKey:(NSString *)untilKey
                          lastSeenKey:(NSString *)seenKey
                                 dict:(NSDictionary *)dict {
    IMPresence *p = [IMPresence new];
    if (![dict isKindOfClass:[NSDictionary class]]) { return p; }
    p.level = IMPresenceLevelFromString(dict[statusKey]);
    p.onlineUntil = IMPresenceInt64(dict, untilKey);
    p.lastSeen = IMPresenceInt64(dict, seenKey);
    return p;
}

+ (instancetype)presenceFromConversationDictionary:(NSDictionary *)dict {
    return [self presenceWithStatusKey:@"peer_presence"
                        onlineUntilKey:@"peer_online_until"
                           lastSeenKey:@"peer_last_seen"
                                  dict:dict];
}

+ (instancetype)presenceFromProfileDictionary:(NSDictionary *)dict {
    return [self presenceWithStatusKey:@"presence" onlineUntilKey:@"online_until" lastSeenKey:@"last_seen" dict:dict];
}

+ (instancetype)presenceFromFrameDictionary:(NSDictionary *)dict {
    return [self presenceWithStatusKey:@"status" onlineUntilKey:@"online_until" lastSeenKey:@"last_seen" dict:dict];
}

- (BOOL)isOnline {
    // 只认租约，不认 level==Online：档位是取快照那一刻的判定，租约才是可随时间推移重算的依据。
    return self.onlineUntil > (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
}

- (NSString *)subtitleText {
    if (self.isOnline) { return @"在线"; }
    if (self.lastSeen > 0) { return [self relativeLastSeenText]; }
    // 无精确时间（未知或将来被隐私设置抹掉）时回退到粗档文案。
    switch (self.level) {
        case IMPresenceLevelOnline:    return @"在线"; // 租约已过期但档位仍为 online：快照偏旧，从宽显示
        case IMPresenceLevelRecently:  return @"最近在线";
        case IMPresenceLevelLastWeek:  return @"一周内在线";
        case IMPresenceLevelLastMonth: return @"一个月内在线";
        case IMPresenceLevelLongAgo:   return @"很久未上线";
        case IMPresenceLevelUnknown:   return @"";
    }
}

/// 由 lastSeen 生成精确相对文案（微信/Telegram 风格的分级粒度）。
- (NSString *)relativeLastSeenText {
    NSDate *seen = [NSDate dateWithTimeIntervalSince1970:self.lastSeen / 1000.0];
    NSTimeInterval elapsed = -seen.timeIntervalSinceNow;
    if (elapsed < 60) { return @"刚刚在线"; }
    if (elapsed < 3600) { return [NSString stringWithFormat:@"%d 分钟前在线", (int)(elapsed / 60)]; }

    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = NSLocale.currentLocale;
    if ([cal isDateInToday:seen]) {
        fmt.dateFormat = @"HH:mm";
        return [NSString stringWithFormat:@"今天 %@ 在线", [fmt stringFromDate:seen]];
    }
    if ([cal isDateInYesterday:seen]) {
        fmt.dateFormat = @"HH:mm";
        return [NSString stringWithFormat:@"昨天 %@ 在线", [fmt stringFromDate:seen]];
    }
    // 跨年时带上年份，避免「1月2日」指向去年却看不出来。
    NSInteger seenYear = [cal component:NSCalendarUnitYear fromDate:seen];
    NSInteger nowYear = [cal component:NSCalendarUnitYear fromDate:NSDate.date];
    fmt.dateFormat = (seenYear == nowYear) ? @"M月d日" : @"yyyy年M月d日";
    return [NSString stringWithFormat:@"%@ 在线", [fmt stringFromDate:seen]];
}

@end
