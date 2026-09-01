//  IMChatMessageLogic.m

#import "IMChatMessageLogic.h"

#import "IMMessageModel.h"
#import "IMPendingMediaStore.h"

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

NSArray<IMMentionSpan *> *IMChatScanMentionSpans(NSString *text, NSDictionary<NSString *, NSString *> *nameToUID) {
    if (text.length == 0 || nameToUID.count == 0) { return @[]; }
    // 长名优先：`@小美丽` 必须先于 `@小美` 命中，否则前缀会把长名切碎。
    NSArray<NSString *> *names = [nameToUID.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if (a.length == b.length) { return NSOrderedSame; }
        return a.length > b.length ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSMutableArray<IMMentionSpan *> *out = [NSMutableArray array];
    NSUInteger i = 0, len = text.length;
    while (i < len) {
        if ([text characterAtIndex:i] == '@') {
            NSString *hit = nil;
            for (NSString *n in names) {
                if (n.length == 0) { continue; }
                NSUInteger tokenLen = n.length + 1;
                if (i + tokenLen > len) { continue; }
                if (![[text substringWithRange:NSMakeRange(i + 1, n.length)] isEqualToString:n]) { continue; }
                NSUInteger after = i + tokenLen;
                if (after >= len || [ws characterIsMember:[text characterAtIndex:after]]) { hit = n; break; }
            }
            if (hit) {
                IMMentionSpan *span = [IMMentionSpan new];
                span.range = NSMakeRange(i, hit.length + 1);
                NSString *uid = nameToUID[hit];
                span.uid = uid.length > 0 ? uid : nil; // 空串=@所有人
                [out addObject:span];
                i += hit.length + 1;
                continue;
            }
        }
        i += 1;
    }
    return out;
}

NSArray<IMMentionSpan *> *IMChatValidMentionSpans(NSString *text, NSArray<IMMentionSpan *> *spans) {
    if (text.length == 0 || spans.count == 0) { return @[]; }
    NSArray<IMMentionSpan *> *sorted = [spans sortedArrayUsingComparator:^NSComparisonResult(IMMentionSpan *a, IMMentionSpan *b) {
        if (a.range.location == b.range.location) { return NSOrderedSame; }
        return a.range.location < b.range.location ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray<IMMentionSpan *> *out = [NSMutableArray array];
    NSUInteger end = 0;
    for (IMMentionSpan *s in sorted) {
        NSRange r = s.range;
        if (r.length == 0 || NSMaxRange(r) > text.length) { continue; }
        if (r.location < end) { continue; }                              // 与前一段重叠
        if ([text characterAtIndex:r.location] != '@') { continue; }      // 位置对不上（编辑过/脏数据）
        [out addObject:s];
        end = NSMaxRange(r);
    }
    return out;
}

BOOL IMContentTypeCountsAsUnread(NSString *_Nullable contentType) {
    NSString *ct = contentType ?: @"";
    return !([ct isEqualToString:@"system"] || [ct isEqualToString:@"msg_op"]);
}

NSString *IMConversationPublicName(BOOL isGroup, NSString *groupName, NSString *peerNickname, NSString *peerID) {
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *name = [(isGroup ? groupName : peerNickname) stringByTrimmingCharactersInSet:ws];
    if (name.length > 0) { return name; }
    NSString *uid = [peerID stringByTrimmingCharactersInSet:ws];
    if (!isGroup && uid.length > 0) { return uid; }
    return isGroup ? @"群聊" : @"聊天";
}

NSString *IMChatRecordTitle(BOOL isGroup, NSString *peerPublicName, NSString *myPublicName) {
    if (isGroup) { return @"群聊的聊天记录"; }
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *peer = [(peerPublicName ?: @"") stringByTrimmingCharactersInSet:ws];
    NSString *me = [(myPublicName ?: @"") stringByTrimmingCharactersInSet:ws];
    if (peer.length > 0 && me.length > 0) { return [NSString stringWithFormat:@"%@和%@的聊天记录", peer, me]; }
    if (peer.length > 0 || me.length > 0) { return [NSString stringWithFormat:@"%@的聊天记录", (peer.length > 0 ? peer : me)]; }
    return @"聊天记录";
}

IMResendPolicy IMResendPolicyForMessage(IMMessageModel *message, BOOL mine) {
    if (!message || !mine) { return IMResendPolicyNone; }
    if (message.status != IMMessageStatusFailed) { return IMResendPolicyNone; }
    // 已拿到 conv_seq = 服务端确实收下了；此时还挂着 failed 只可能是脏数据，重发会造重复。
    if (message.convSeq > 0) { return IMResendPolicyNone; }
    // **本地还留着字节的，先判重传——必须排在 note 之前**：content 是本地引用就说明服务端从没见过
    // 这条（连 send_msg 都还没发出去），任何"被服务端拒收"的解释都不成立。
    // 反例（2026-08-30 /code-review 抓到）：语音上传失败会无条件写 note（"语音上传失败"），
    // 若先判 note 就会把它归成"拒收→不可重发"，红❗照显却点不动，重传路径整条失效。
    // `file://` 是 2026-08-27 前语音失败件落库的 tmp 绝对路径（旧方言，仍可能躺在老库里）：
    // 必须一并归到重传，否则会被当成服务器地址原样发出去，对端收到一条永远打不开的语音
    // （正是 2026-08-26 修过的那个坑）。
    if (message.content.length > 0
        && ([IMPendingMediaStore isLocalRef:message.content]
            || [message.content hasPrefix:@"file://"])) {
        return IMResendPolicyRetryUpload;
    }
    // 被服务端明确拒收（拉黑 200102 / 非好友 200103 / 禁言 300004·300208 / 全员禁言 300206 /
    // 非群成员 300203 / 内容过大 300001）：原样重发必然再次被拒，给入口只是让用户白等一轮超时。
    // 这些消息的恢复入口是气泡下方系统行（如 200103 → 发好友申请），不是红❗。
    // 语音"发送中断，请重新录制"那条也带 note，同样落到这里——它 content 为空，本就无从重发。
    if (message.note.length > 0) { return IMResendPolicyNone; }
    // 排队/压缩期就失败：还没落盘，content 空。服务器上没有这条 → 从本地副本重传，
    // 换新 client_msg_id 不会重复。
    if (message.content.length == 0) { return IMResendPolicyRetryUpload; }
    return IMResendPolicySameID;
}
