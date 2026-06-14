//  IMConversation.m

#import "IMConversation.h"

@implementation IMConversation

+ (NSArray<IMConversation *> *)conversationsFromArray:(NSArray *)array {
    if (![array isKindOfClass:[NSArray class]]) { return @[]; }
    NSMutableArray<IMConversation *> *out = [NSMutableArray arrayWithCapacity:array.count];
    for (id item in array) {
        if (![item isKindOfClass:[NSDictionary class]]) { continue; }
        [out addObject:[self conversationFromDictionary:item]];
    }
    return out;
}

+ (instancetype)conversationFromDictionary:(NSDictionary *)dict {
    IMConversation *c = [IMConversation new];
    c.convID = [self stringForKey:@"conv_id" in:dict];
    c.peer = [self stringForKey:@"peer" in:dict];
    c.latestConvSeq = [dict[@"latest_conv_seq"] respondsToSelector:@selector(longLongValue)] ? [dict[@"latest_conv_seq"] longLongValue] : 0;
    c.unread = [dict[@"unread"] respondsToSelector:@selector(integerValue)] ? [dict[@"unread"] integerValue] : 0;

    NSDictionary *last = [dict[@"last_message"] isKindOfClass:[NSDictionary class]] ? dict[@"last_message"] : nil;
    if (last) {
        c.lastContent = [self stringForKey:@"content" in:last];
        c.lastFrom = [self stringForKey:@"from" in:last];
        c.timestamp = [last[@"timestamp"] respondsToSelector:@selector(longLongValue)] ? [last[@"timestamp"] longLongValue] : 0;
    }
    return c;
}

+ (NSString *)stringForKey:(NSString *)key in:(NSDictionary *)dict {
    id v = dict[key];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

@end
