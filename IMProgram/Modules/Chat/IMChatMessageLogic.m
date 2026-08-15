//  IMChatMessageLogic.m

#import "IMChatMessageLogic.h"
#import "IMMessageModel.h"
#import "IMMediaUtil.h"

BOOL IMChatTextContainsMentionToken(NSString *_Nullable text, NSString *_Nullable displayName) {
    if (text.length == 0 || displayName.length == 0) { return NO; }
    NSString *needle = [@"@" stringByAppendingString:displayName];
    NSUInteger from = 0;
    while (from <= text.length - MIN(text.length, 1)) {
        NSRange scan = NSMakeRange(from, text.length - from);
        if (scan.length < needle.length) { return NO; }
        NSRange hit = [text rangeOfString:needle options:0 range:scan];
        if (hit.location == NSNotFound) { return NO; }
        NSUInteger after = hit.location + hit.length;
        if (after >= text.length) { return YES; } // 到结尾即完整 token
        unichar next = [text characterAtIndex:after];
        if ([NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:next]) { return YES; }
        from = hit.location + 1; // 命中的是更长名字的前缀，继续往后找
    }
    return NO;
}

BOOL IMContentTypeCountsAsUnread(NSString *_Nullable contentType) {
    NSString *ct = contentType ?: @"";
    return !([ct isEqualToString:@"system"] || [ct isEqualToString:@"msg_op"]);
}

NSString *IMReplySnippet(IMMessageModel *m) {
    if ([m.contentType isEqualToString:@"image"]) { return @"[图片]"; }
    if ([m.contentType isEqualToString:@"video"]) { return @"[视频]"; }
    if ([m.contentType isEqualToString:@"file"]) {
        NSString *fn = m.fileName.length > 0 ? m.fileName : IMMediaFileName(m.content);
        return fn.length > 0 ? [@"[文件] " stringByAppendingString:fn] : @"[文件]";
    }
    if ([m.contentType isEqualToString:@"chat_record"]) { return IMChatRecordSnippet(m.content); } // [聊天记录] 标题
    NSString *c = m.content ?: @"";
    return c.length > 60 ? [[c substringToIndex:60] stringByAppendingString:@"…"] : c;
}
