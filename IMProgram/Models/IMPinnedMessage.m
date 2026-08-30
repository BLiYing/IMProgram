//  IMPinnedMessage.m

#import "IMPinnedMessage.h"
#import "IMContactCard.h"
#import "IMMediaUtil.h"   // IMChatRecordSnippet：聊天记录卡片 → 「[聊天记录] 标题」

@implementation IMPinnedMessage

+ (nullable instancetype)fromJSON:(nullable NSDictionary *)json {
    if (![json isKindOfClass:[NSDictionary class]]) { return nil; }
    id seq = json[@"conv_seq"];
    int64_t convSeq = [seq respondsToSelector:@selector(longLongValue)] ? [seq longLongValue] : 0;
    if (convSeq <= 0) { return nil; } // 没有位点就无法跳转，这条对横幅毫无用处

    IMPinnedMessage *p = [IMPinnedMessage new];
    p.convSeq = convSeq;
    p.serverMsgID = [json[@"server_msg_id"] isKindOfClass:[NSString class]] ? json[@"server_msg_id"] : @"";
    p.from = [json[@"sender"] isKindOfClass:[NSString class]] ? json[@"sender"] : @"";
    NSString *nick = [json[@"from_nickname"] isKindOfClass:[NSString class]] ? json[@"from_nickname"] : nil;
    p.fromNickname = nick.length > 0 ? nick : nil;
    p.contentType = [json[@"content_type"] isKindOfClass:[NSString class]] ? json[@"content_type"] : @"text";
    p.content = [json[@"content"] isKindOfClass:[NSString class]] ? json[@"content"] : @"";
    NSString *cap = [json[@"caption"] isKindOfClass:[NSString class]] ? json[@"caption"] : nil;
    p.caption = cap.length > 0 ? cap : nil;
    id ts = json[@"timestamp"];
    p.timestamp = [ts respondsToSelector:@selector(longLongValue)] ? [ts longLongValue] : 0;
    id pinnedAt = json[@"pinned_at"];
    p.pinnedAt = [pinnedAt respondsToSelector:@selector(longLongValue)] ? [pinnedAt longLongValue] : 0;
    return p;
}

- (NSString *)previewText {
    // 图说「有字显字」：媒体/文件带 caption 时横幅显 caption 文字，否则回退类型词。
    if (self.caption.length > 0 && ([self.contentType isEqualToString:@"image"] || [self.contentType isEqualToString:@"video"] || [self.contentType isEqualToString:@"file"])) {
        return [self oneLine:self.caption];
    }
    if ([self.contentType isEqualToString:@"image"]) { return @"[图片]"; }
    if ([self.contentType isEqualToString:@"video"]) { return @"[视频]"; }
    // voice = 录制的语音条（正式类型）；audio 是 voice 落地前的旧命名，两者都要认——
    // 只认 audio 时置顶横幅/置顶列表会把语音的 content（一串 URL）原样铺出来。
    if ([self.contentType isEqualToString:@"voice"] || [self.contentType isEqualToString:@"audio"]) { return @"[语音]"; }
    if ([self.contentType isEqualToString:@"file"])  { return @"[文件]"; }
    if ([self.contentType isEqualToString:IMContentTypeContact]) { return IMContactCardPreview(self.content); }
    // 合并转发卡片：content 是整段 JSON，直接显会把 {"t":…,"items":[…]} 铺满横幅 → 统一收成「[聊天记录] 标题」
    //（与引用快照 / 会话列表预览 / 合并转发条目同一 token 口径）。
    if ([self.contentType isEqualToString:@"chat_record"]) { return IMChatRecordSnippet(self.content); }
    NSString *line = [self oneLine:self.content];
    if (line.length > 0) { return line; }
    return [self.contentType isEqualToString:@"text"] ? @"（空消息）"
                                                      : [NSString stringWithFormat:@"[%@]", self.contentType];
}

/// 折行/连续空白压成单行——横幅是单行省略号布局，换行会把它撑高。
- (NSString *)oneLine:(NSString *)s {
    if (![s isKindOfClass:[NSString class]] || s.length == 0) { return @""; }
    NSArray<NSString *> *parts = [s componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) { [kept addObject:part]; }
    }
    return [kept componentsJoinedByString:@" "];
}

- (NSString *)senderLabelForGroup:(BOOL)isGroup {
    if (!isGroup) { return @""; }
    return self.fromNickname.length > 0 ? self.fromNickname : (self.from ?: @"");
}

@end
