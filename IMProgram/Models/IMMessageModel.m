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
    m.fileName    = [self stringForKey:@"file_name" in:data];
    m.fileSize    = [data[@"file_size"] longLongValue];
    m.convSeq     = [data[@"conv_seq"] longLongValue];
    m.timestamp   = [data[@"timestamp"] longLongValue];
    m.status      = IMMessageStatusReceived;
    m.recalledAt  = [data[@"recalled_at"] longLongValue];
    m.recalledBy  = [self stringForKey:@"recalled_by" in:data];
    m.deletedAt   = [data[@"deleted_at"] longLongValue]; // 任务2 为所有人删除：>0 时收端物理移除、不入库

    m.editedAt    = [data[@"edited_at"] longLongValue];
    m.pinnedAt    = [data[@"pinned_at"] longLongValue];
    m.replyToConvSeq = [data[@"reply_to_conv_seq"] longLongValue];
    m.replySnapshot  = [self stringForKey:@"reply_snapshot" in:data];
    m.replyToFrom    = [self stringForKey:@"reply_to_from" in:data];
    m.forwardFrom    = [self stringForKey:@"forward_from" in:data];
    m.groupID        = [self stringForKey:@"group_id" in:data];
    m.poster         = [self stringForKey:@"poster" in:data];
    m.mediaW         = [data[@"media_w"] integerValue];
    m.mediaH         = [data[@"media_h"] integerValue];
    m.duration       = [data[@"duration"] longLongValue];
    m.thumb          = [self stringForKey:@"thumb" in:data];
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
    if (self.fileName) { d[@"file_name"] = self.fileName; }
    if (self.fileSize > 0) { d[@"file_size"] = @(self.fileSize); }
    d[@"conv_seq"] = @(self.convSeq);
    d[@"timestamp"] = @(self.timestamp);
    d[@"status"] = @(self.status);
    if (self.recalledAt > 0) { d[@"recalled_at"] = @(self.recalledAt); }
    if (self.recalledBy) { d[@"recalled_by"] = self.recalledBy; }
    if (self.editedAt > 0) { d[@"edited_at"] = @(self.editedAt); }
    if (self.pinnedAt > 0) { d[@"pinned_at"] = @(self.pinnedAt); }
    if (self.replyToConvSeq > 0) { d[@"reply_to_conv_seq"] = @(self.replyToConvSeq); }
    if (self.replySnapshot) { d[@"reply_snapshot"] = self.replySnapshot; }
    if (self.replyToFrom) { d[@"reply_to_from"] = self.replyToFrom; }
    if (self.forwardFrom) { d[@"forward_from"] = self.forwardFrom; }
    if (self.groupID) { d[@"group_id"] = self.groupID; }
    if (self.poster) { d[@"poster"] = self.poster; }
    if (self.mediaW > 0) { d[@"media_w"] = @(self.mediaW); }
    if (self.mediaH > 0) { d[@"media_h"] = @(self.mediaH); }
    if (self.duration > 0) { d[@"duration"] = @(self.duration); }
    if (self.thumb) { d[@"thumb"] = self.thumb; }
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
    m.fileName    = [self stringForKey:@"file_name" in:dict];
    m.fileSize    = [dict[@"file_size"] longLongValue];
    m.convSeq     = [dict[@"conv_seq"] longLongValue];
    m.timestamp   = [dict[@"timestamp"] longLongValue];
    m.status      = (IMMessageStatus)[dict[@"status"] integerValue];
    m.recalledAt  = [dict[@"recalled_at"] longLongValue];
    m.recalledBy  = [self stringForKey:@"recalled_by" in:dict];
    m.editedAt    = [dict[@"edited_at"] longLongValue];
    m.pinnedAt    = [dict[@"pinned_at"] longLongValue];
    m.replyToConvSeq = [dict[@"reply_to_conv_seq"] longLongValue];
    m.replySnapshot  = [self stringForKey:@"reply_snapshot" in:dict];
    m.replyToFrom    = [self stringForKey:@"reply_to_from" in:dict];
    m.forwardFrom    = [self stringForKey:@"forward_from" in:dict];
    m.groupID        = [self stringForKey:@"group_id" in:dict];
    m.poster         = [self stringForKey:@"poster" in:dict];
    m.mediaW         = [dict[@"media_w"] integerValue];
    m.mediaH         = [dict[@"media_h"] integerValue];
    m.duration       = [dict[@"duration"] longLongValue];
    m.thumb          = [self stringForKey:@"thumb" in:dict];
    return m;
}

/// 安全取字符串：非字符串类型返回 nil，避免脏数据崩溃。
+ (nullable NSString *)stringForKey:(NSString *)key in:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

@end
