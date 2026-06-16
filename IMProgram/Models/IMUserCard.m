//  IMUserCard.m

#import "IMUserCard.h"

IMFriendStatus IMFriendStatusFromString(NSString *s) {
    if ([s isEqualToString:@"requested"]) { return IMFriendStatusRequested; }
    if ([s isEqualToString:@"pending"])   { return IMFriendStatusPending; }
    if ([s isEqualToString:@"accepted"])  { return IMFriendStatusAccepted; }
    if ([s isEqualToString:@"blocked"])   { return IMFriendStatusBlocked; }
    return IMFriendStatusNone;
}

@implementation IMUserCard

+ (NSArray<IMUserCard *> *)cardsFromArray:(NSArray *)array {
    if (![array isKindOfClass:[NSArray class]]) { return @[]; }
    NSMutableArray<IMUserCard *> *out = [NSMutableArray arrayWithCapacity:array.count];
    for (id item in array) {
        if (![item isKindOfClass:[NSDictionary class]]) { continue; }
        [out addObject:[self cardFromDictionary:item]];
    }
    return out;
}

+ (instancetype)cardFromDictionary:(NSDictionary *)dict {
    IMUserCard *c = [IMUserCard new];
    c.userID = [self stringForKey:@"user_id" in:dict];
    c.nickname = [self stringForKey:@"nickname" in:dict];
    c.avatarURL = [self stringForKey:@"avatar_url" in:dict];
    c.status = IMFriendStatusFromString([self stringForKey:@"status" in:dict]);
    c.updatedAt = [dict[@"updated_at"] respondsToSelector:@selector(longLongValue)] ? [dict[@"updated_at"] longLongValue] : 0;

    NSMutableArray<NSString *> *tags = [NSMutableArray array];
    if ([dict[@"tags"] isKindOfClass:[NSArray class]]) {
        for (id t in dict[@"tags"]) {
            if ([t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) { [tags addObject:t]; }
        }
    }
    c.tags = tags;
    return c;
}

- (NSString *)displayName {
    NSString *nick = [self.nickname stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return nick.length > 0 ? nick : self.userID;
}

+ (NSString *)stringForKey:(NSString *)key in:(NSDictionary *)dict {
    id v = dict[key];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

@end
