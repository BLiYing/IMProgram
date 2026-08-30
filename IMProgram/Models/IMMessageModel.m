//  IMMessageModel.m

#import "IMMessageModel.h"

#import "IMRemarkStore.h"   // 名字段的本机显示名（备注优先）

@implementation IMSysSegment

+ (NSArray<IMSysSegment *> *)segmentsFromArray:(NSArray *)array {
    if (![array isKindOfClass:NSArray.class] || array.count == 0) { return nil; }
    NSMutableArray<IMSysSegment *> *out = [NSMutableArray arrayWithCapacity:array.count];
    for (id item in array) {
        if (![item isKindOfClass:NSDictionary.class]) { continue; }
        id text = item[@"text"], uid = item[@"uid"];
        if (![text isKindOfClass:NSString.class] || [(NSString *)text length] == 0) { continue; }
        IMSysSegment *seg = [IMSysSegment new];
        seg.text = text;
        seg.uid = [uid isKindOfClass:NSString.class] && [(NSString *)uid length] > 0 ? uid : nil;
        [out addObject:seg];
    }
    return out.count > 0 ? out : nil; // 一段都解析不出 → 按"无分段"处理，收端回退整句
}

+ (NSArray<NSDictionary *> *)arrayFromSegments:(NSArray<IMSysSegment *> *)segments {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:segments.count];
    for (IMSysSegment *seg in segments) {
        if (seg.text.length == 0) { continue; }
        [out addObject:(seg.uid.length > 0 ? @{ @"uid": seg.uid, @"text": seg.text } : @{ @"text": seg.text })];
    }
    return out;
}


+ (NSString *)localNameForUID:(NSString *)uid
                      selfUID:(NSString *)selfUID
                groupNickname:(NSString *)groupNickname
                     fallback:(NSString *)fallback {
    if (uid.length == 0) { return fallback ?: @""; }
    if (selfUID.length > 0 && [uid isEqualToString:selfUID]) { return @"我"; }
    NSString *base = groupNickname.length > 0 ? groupNickname : (fallback.length > 0 ? fallback : uid);
    return [IMRemarkStore.sharedStore displayNameForUser:uid fallback:base];
}

@end

@implementation IMMessageModel

+ (instancetype)receivedMessageWithNewMsgData:(NSDictionary *)data {
    IMMessageModel *m = [IMMessageModel new];
    m.serverMsgID = [self stringForKey:@"server_msg_id" in:data];
    m.convID      = [self stringForKey:@"conv_id" in:data];
    m.from        = [self stringForKey:@"from" in:data];
    m.fromNickname = [self stringForKey:@"from_nickname" in:data];
    m.fromRole    = [self stringForKey:@"from_role" in:data];
    m.contentType = [self stringForKey:@"content_type" in:data] ?: @"text";
    m.content     = [self stringForKey:@"content" in:data] ?: @"";
    m.fileName    = [self stringForKey:@"file_name" in:data];
    m.fileSize    = [data[@"file_size"] longLongValue];
    m.caption     = [self stringForKey:@"caption" in:data]; // 图文/视频文/文件文随附文本
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
    m.waveform       = [self stringForKey:@"waveform" in:data]; // voice 振幅指纹（base64≤160 rune）
    m.mentions       = [self stringArrayForKey:@"mentions" in:data]; // M4-8：落库供转发重发（强提醒）
    m.mentionAll     = [data[@"mention_all"] boolValue];
    m.sysSegments    = [IMSysSegment segmentsFromArray:data[@"sys_segments"]]; // 系统消息可点名字（仅 system）
    return m;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"client_msg_id"] = self.clientMsgID ?: @"";
    if (self.serverMsgID) { d[@"server_msg_id"] = self.serverMsgID; }
    d[@"conv_id"] = self.convID ?: @"";
    if (self.from) { d[@"from"] = self.from; }
    if (self.fromNickname) { d[@"from_nickname"] = self.fromNickname; }
    if (self.fromRole) { d[@"from_role"] = self.fromRole; }
    if (self.to) { d[@"to"] = self.to; }
    d[@"content_type"] = self.contentType ?: @"text";
    d[@"content"] = self.content ?: @"";
    if (self.fileName) { d[@"file_name"] = self.fileName; }
    if (self.fileSize > 0) { d[@"file_size"] = @(self.fileSize); }
    if (self.caption) { d[@"caption"] = self.caption; }
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
    if (self.waveform.length > 0) { d[@"waveform"] = self.waveform; }
    if (self.mentions.count > 0) { d[@"mentions"] = self.mentions; }
    if (self.mentionAll) { d[@"mention_all"] = @YES; }
    return d;
}

+ (instancetype)messageFromDictionary:(NSDictionary *)dict {
    IMMessageModel *m = [IMMessageModel new];
    m.clientMsgID = [self stringForKey:@"client_msg_id" in:dict];
    m.serverMsgID = [self stringForKey:@"server_msg_id" in:dict];
    m.convID      = [self stringForKey:@"conv_id" in:dict];
    m.from        = [self stringForKey:@"from" in:dict];
    m.fromNickname = [self stringForKey:@"from_nickname" in:dict];
    m.fromRole    = [self stringForKey:@"from_role" in:dict];
    m.to          = [self stringForKey:@"to" in:dict];
    m.contentType = [self stringForKey:@"content_type" in:dict] ?: @"text";
    m.content     = [self stringForKey:@"content" in:dict] ?: @"";
    m.fileName    = [self stringForKey:@"file_name" in:dict];
    m.fileSize    = [dict[@"file_size"] longLongValue];
    m.caption     = [self stringForKey:@"caption" in:dict]; // 图文/视频文/文件文随附文本
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
    m.mentions       = [self stringArrayForKey:@"mentions" in:dict];
    m.mentionAll     = [dict[@"mention_all"] boolValue];
    m.sysSegments    = [IMSysSegment segmentsFromArray:dict[@"sys_segments"]];
    return m;
}

/// 安全取字符串：非字符串类型返回 nil，避免脏数据崩溃。
+ (nullable NSString *)stringForKey:(NSString *)key in:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

/// 安全取字符串数组：只收 NSArray<NSString>，掺杂非字符串元素时逐个过滤（脏数据按"未 @ 任何人"降级）。
+ (nullable NSArray<NSString *> *)stringArrayForKey:(NSString *)key in:(NSDictionary *)dict {
    id value = dict[key];
    if (![value isKindOfClass:[NSArray class]]) { return nil; }
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id v in (NSArray *)value) {
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) { [out addObject:v]; }
    }
    return out.count > 0 ? out : nil;
}

@end
