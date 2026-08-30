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

IMResendPolicy IMResendPolicyForMessage(IMMessageModel *message, BOOL mine) {
    if (!message || !mine) { return IMResendPolicyNone; }
    if (message.status != IMMessageStatusFailed) { return IMResendPolicyNone; }
    // 已拿到 conv_seq = 服务端确实收下了；此时还挂着 failed 只可能是脏数据，重发会造重复。
    if (message.convSeq > 0) { return IMResendPolicyNone; }
    // 被服务端明确拒收（拉黑 200102 / 非好友 200103 / 禁言 300004·300208 / 全员禁言 300206 /
    // 非群成员 300203 / 内容过大 300001）：原样重发必然再次被拒，给入口只是让用户白等一轮超时。
    // 这些消息的恢复入口是气泡下方系统行（如 200103 → 发好友申请），不是红❗。
    // 语音"发送中断，请重新录制"那条也带 note，同样落到这里——它 content 为空，本就无从重发。
    if (message.note.length > 0) { return IMResendPolicyNone; }
    // 本地待发件：content 还是 im-pending:// 本地引用，或排队/压缩期压根还没落盘（content 空）。
    // 服务器上没有这条 → 从本地副本重传，换新 client_msg_id 不会重复。
    // `file://` 是 2026-08-27 前语音失败件落库的 tmp 绝对路径（旧方言，仍可能躺在老库里）：
    // 必须一并归到重传，否则会被当成服务器地址原样发出去，对端收到一条永远打不开的语音
    // （正是 2026-08-26 修过的那个坑）。
    if (message.content.length == 0
        || [IMPendingMediaStore isLocalRef:message.content]
        || [message.content hasPrefix:@"file://"]) {
        return IMResendPolicyRetryUpload;
    }
    return IMResendPolicySameID;
}
