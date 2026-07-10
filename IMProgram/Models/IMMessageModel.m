//  IMMessageModel.m

#import "IMMessageModel.h"

@implementation IMMessageModel

+ (instancetype)receivedMessageWithNewMsgData:(NSDictionary *)data {
    IMMessageModel *m = [IMMessageModel new];
    m.serverMsgID = [self stringForKey:@"server_msg_id" in:data];
    m.convID      = [self stringForKey:@"conv_id" in:data];
    m.from        = [self stringForKey:@"from" in:data];
    m.fromNickname = [self stringForKey:@"from_nickname" in:data];
    m.contentType = [self stringForKey:@"content_type" in:data] ?: @"text";
    m.content     = [self stringForKey:@"content" in:data] ?: @"";
    m.convSeq     = [data[@"conv_seq"] longLongValue];
    m.timestamp   = [data[@"timestamp"] longLongValue];
    m.status      = IMMessageStatusReceived;
    return m;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"client_msg_id"] = self.clientMsgID ?: @"";
    if (self.serverMsgID) { d[@"server_msg_id"] = self.serverMsgID; }
    d[@"conv_id"] = self.convID ?: @"";
    if (self.from) { d[@"from"] = self.from; }
    if (self.fromNickname) { d[@"from_nickname"] = self.fromNickname; }
    if (self.to) { d[@"to"] = self.to; }
    d[@"content_type"] = self.contentType ?: @"text";
    d[@"content"] = self.content ?: @"";
    d[@"conv_seq"] = @(self.convSeq);
    d[@"timestamp"] = @(self.timestamp);
    d[@"status"] = @(self.status);
    return d;
}

+ (instancetype)messageFromDictionary:(NSDictionary *)dict {
    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = [self stringForKey:@"client_msg_id" in:dict];
    m.serverMsgID = [self stringForKey:@"server_msg_id" in:dict];
    m.convID      = [self stringForKey:@"conv_id" in:dict];
    m.from        = [self stringForKey:@"from" in:dict];
    m.fromNickname = [self stringForKey:@"from_nickname" in:dict];
    m.to          = [self stringForKey:@"to" in:dict];
    m.contentType = [self stringForKey:@"content_type" in:dict] ?: @"text";
    m.content     = [self stringForKey:@"content" in:dict] ?: @"";
    m.convSeq     = [dict[@"conv_seq"] longLongValue];
    m.timestamp   = [dict[@"timestamp"] longLongValue];
    m.status      = (IMMessageStatus)[dict[@"status"] integerValue];
    return m;
}

/// 安全取字符串：非字符串类型返回 nil，避免脏数据崩溃。
+ (nullable NSString *)stringForKey:(NSString *)key in:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

@end
