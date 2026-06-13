//  IMMessageModel.m

#import "IMMessageModel.h"

@implementation IMMessageModel

+ (instancetype)receivedMessageWithNewMsgData:(NSDictionary *)data {
    IMMessageModel *m = [IMMessageModel new];
    m.serverMsgID = [self stringForKey:@"server_msg_id" in:data];
    m.convID      = [self stringForKey:@"conv_id" in:data];
    m.from        = [self stringForKey:@"from" in:data];
    m.contentType = [self stringForKey:@"content_type" in:data] ?: @"text";
    m.content     = [self stringForKey:@"content" in:data] ?: @"";
    m.convSeq     = [data[@"conv_seq"] longLongValue];
    m.timestamp   = [data[@"timestamp"] longLongValue];
    m.status      = IMMessageStatusReceived;
    return m;
}

/// 安全取字符串：非字符串类型返回 nil，避免脏数据崩溃。
+ (nullable NSString *)stringForKey:(NSString *)key in:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

@end
