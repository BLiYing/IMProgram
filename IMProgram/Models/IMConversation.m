//  IMConversation.m

#import "IMConversation.h"

#import "IMMessageModel.h" // IMSysSegment
#import "IMPresence.h"
#import "IMRemarkStore.h"

/// JSON 布尔的严格解析：**只认 NSNumber**（JSON 的 true/false/1/0 都落成 NSNumber）。
///
/// 不能用 `respondsToSelector:@selector(boolValue)` —— NSString 也响应它，于是任何脏字符串
/// （`@"yes"`/`@"true"`/`@"1"`）都会被当成 YES。对 mention_unread 这类字段尤其危险：
/// 一个脏值就会让会话行常驻「[有人@我]」红字、并让免打扰群的未读数持续红底，用户无从消除。
static BOOL IMBoolFromJSON(id value) {
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}

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
    c.isGroup = IMBoolFromJSON(dict[@"is_group"]);
    c.name = [self stringForKey:@"name" in:dict];
    c.avatarURL = [self stringForKey:@"avatar_url" in:dict];
    c.memberCount = [dict[@"member_count"] respondsToSelector:@selector(integerValue)] ? [dict[@"member_count"] integerValue] : 0;
    c.pendingCount = [dict[@"pending_count"] respondsToSelector:@selector(integerValue)] ? [dict[@"pending_count"] integerValue] : 0;
    c.isSuper = IMBoolFromJSON(dict[@"is_super"]);
    c.peer = [self stringForKey:@"peer" in:dict];
    c.peerNickname = [self stringForKey:@"peer_nickname" in:dict];
    c.peerAvatarURL = [self stringForKey:@"peer_avatar_url" in:dict];
    c.peerRemark = [self stringForKey:@"peer_remark" in:dict]; // 好友备注（仅本人可见）；非空替代对端昵称
    // 单聊对端在线态快照（peer_presence/peer_online_until/peer_last_seen）；群聊/老响应无这些键 → nil，不显绿点。
    if (!c.isGroup && dict[@"peer_presence"]) {
        c.peerPresence = [IMPresence presenceFromConversationDictionary:dict];
    }
    c.latestConvSeq = [dict[@"latest_conv_seq"] respondsToSelector:@selector(longLongValue)] ? [dict[@"latest_conv_seq"] longLongValue] : 0;
    c.readSeq = [dict[@"read_seq"] respondsToSelector:@selector(longLongValue)] ? [dict[@"read_seq"] longLongValue] : 0;
    c.peerReadSeq = [dict[@"peer_read_seq"] respondsToSelector:@selector(longLongValue)] ? [dict[@"peer_read_seq"] longLongValue] : 0;
    c.groupReadSeq = [dict[@"group_read_seq"] respondsToSelector:@selector(longLongValue)] ? [dict[@"group_read_seq"] longLongValue] : 0;
    c.unread = [dict[@"unread"] respondsToSelector:@selector(integerValue)] ? [dict[@"unread"] integerValue] : 0;
    c.pinnedAt = [dict[@"pinned_at"] respondsToSelector:@selector(longLongValue)] ? [dict[@"pinned_at"] longLongValue] : 0;
    c.muted = IMBoolFromJSON(dict[@"muted"]);
    c.markedUnread = IMBoolFromJSON(dict[@"marked_unread"]);
    c.remark = [self stringForKey:@"remark" in:dict]; // 会话备注（G1，仅本人可见）；非空替代显示名
    c.mentionUnread = IMBoolFromJSON(dict[@"mention_unread"]);

    NSDictionary *last = [dict[@"last_message"] isKindOfClass:[NSDictionary class]] ? dict[@"last_message"] : nil;
    if (last) {
        c.lastContent = [self stringForKey:@"content" in:last];
        c.lastFrom = [self stringForKey:@"from" in:last];
        c.lastFromNickname = [self stringForKey:@"from_nickname" in:last];
        c.lastSysSegments = [IMSysSegment segmentsFromArray:last[@"sys_segments"]];
        c.lastRecalled = [last[@"recalled_at"] respondsToSelector:@selector(longLongValue)] && [last[@"recalled_at"] longLongValue] > 0;
        c.lastContentType = [self stringForKey:@"content_type" in:last];
        c.lastCaption = [self stringForKey:@"caption" in:last]; // 图说 caption：列表预览「有字显字」
        c.lastDuration = [last[@"duration"] respondsToSelector:@selector(longLongValue)] ? [last[@"duration"] longLongValue] : 0; // voice/video 时长；voice 预览"[语音] m:ss"
        c.timestamp = [last[@"timestamp"] respondsToSelector:@selector(longLongValue)] ? [last[@"timestamp"] longLongValue] : 0;
    }
    return c;
}

- (NSString *)displayName {
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *convRemark = [self.remark stringByTrimmingCharactersInSet:ws];
    if (convRemark.length > 0) { return convRemark; } // 会话备注（G1）最"就近"，群/单聊通用
    if (self.isGroup) {
        NSString *name = [self.name stringByTrimmingCharactersInSet:ws];
        return name.length > 0 ? name : @"群聊";
    }
    // 好友备注取 IMRemarkStore 的实时值而非本对象快照：列表对象常比"刚改完的备注"旧一拍，
    // 读快照会闪回旧名。store 未被喂过该 uid 时回退昵称（宁可显真名，不显过期备注）。
    NSString *nick = [self.peerNickname stringByTrimmingCharactersInSet:ws];
    return [IMRemarkStore.sharedStore displayNameForUser:self.peer
                                                fallback:(nick.length > 0 ? nick : self.peer)];
}

- (NSString *)lastPreviewText { return [self lastPreviewTextForSelfUID:nil]; }

- (NSString *)lastPreviewTextForSelfUID:(NSString *)selfUID {
    if (self.lastSysSegments.count == 0) { return self.lastContent; }
    NSMutableString *out = [NSMutableString string];
    for (IMSysSegment *seg in self.lastSysSegments) {
        if (seg.uid.length == 0) { [out appendString:seg.text ?: @""]; continue; }
        // 群昵称传 nil：会话行手上没有群成员表（那是群资料里的东西），退一级到服务端字面即可。
        [out appendString:[IMSysSegment localNameForUID:seg.uid selfUID:selfUID
                                          groupNickname:nil fallback:seg.text]];
    }
    return out.length > 0 ? out : self.lastContent;
}

+ (NSString *)stringForKey:(NSString *)key in:(NSDictionary *)dict {
    id v = dict[key];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

@end
