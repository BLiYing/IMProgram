//  IMPresence.m

#import "IMPresence.h"
#import "IMTimeUtil.h"
#import "IMTheme.h"
#import "IMLocalization.h"

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
    return self.onlineUntil > IMNowMillis();
}

- (NSString *)subtitleText {
    if (self.isOnline) { return IMLocalized(@"common.online"); }
    if (self.lastSeen > 0) { return [self relativeLastSeenText]; }
    // 无精确时间（未知或将来被隐私设置抹掉）时回退到粗档文案。
    switch (self.level) {
        // 档位说 online 但租约已过期/缺失：**不能**显示「在线」——没有租约就没有到期时刻，
        // 这个「在线」再也不会被时间推翻，会永久停在错误状态。从宽也只到「最近在线」。
        case IMPresenceLevelOnline:    return IMLocalized(@"presence.recently");
        case IMPresenceLevelRecently:  return IMLocalized(@"presence.recently");
        case IMPresenceLevelLastWeek:  return IMLocalized(@"presence.last_week");
        case IMPresenceLevelLastMonth: return IMLocalized(@"presence.last_month");
        case IMPresenceLevelLongAgo:   return IMLocalized(@"presence.long_ago");
        case IMPresenceLevelUnknown:   return @"";
    }
}

/// 由 lastSeen 生成精确相对文案（微信/Telegram 风格的分级粒度）。
- (NSString *)relativeLastSeenText {
    NSDate *seen = [NSDate dateWithTimeIntervalSince1970:self.lastSeen / 1000.0];
    NSTimeInterval elapsed = -seen.timeIntervalSinceNow;
    if (elapsed < 60) { return IMLocalized(@"presence.just_now"); }
    if (elapsed < 3600) { return IMLocalizedFormat(@"presence.minutes_ago", (long)(elapsed / 60)); }

    NSCalendar *cal = NSCalendar.currentCalendar;
    NSString *hm = [[IMTheme timeFormatterForCurrentLanguage] stringFromDate:seen];
    if ([cal isDateInToday:seen]) { return IMLocalizedFormat(@"presence.today_at", hm); }
    if ([cal isDateInYesterday:seen]) { return IMLocalizedFormat(@"presence.yesterday_at", hm); }
    // 跨年时带上年份，避免「1月2日」指向去年却看不出来（dateLabelForDate: 已按同年 / 往年分段）。
    return IMLocalizedFormat(@"presence.on_date", [IMTheme dateLabelForDate:seen]);
}

@end
