//
//  IMVoiceTranscriber.m
//

#import "IMVoiceTranscriber.h"
#import "IMHTTPService.h"

NSNotificationName const IMVoiceTranscriberDidChangeNotification = @"IMVoiceTranscriberDidChangeNotification";

/// 本地缓存 key：按**音频路径**，与服务端 im_voice_transcript 的主键同口径。
/// 不再带 uid/conv——转写结果与会话解耦（同一条语音转发多次只有一份文本），
/// 也就不会再出现 2026-08-26 那种"写入用登录 uid、读取用 message.to"的 key 错位。
static NSString *IMVoiceTranscriptKey(NSString *content) {
    return [@"im.voice.transcript.v2." stringByAppendingString:content ?: @""];
}

/// 「取消转文字」的折叠名单也要落盘：转写文本本身是永久缓存（NSUserDefaults），
/// 折叠状态若只在内存里，杀掉 App 再进会话就会被缓存重新展开——用户取消过的又冒出来
/// （2026-08-26 实测）。名单只存 messageID（收到的消息用 serverMsgID，跨启动稳定）。
static NSString *const kIMVoiceTranscriptCollapsedKey = @"im.voice.transcript.collapsed.v1";
/// 名单上限：折叠是"这条我不想看"的一次性偏好，无限增长没意义；超限按加入顺序淘汰最旧的。
static const NSUInteger kIMVoiceTranscriptCollapsedMax = 500;

@interface IMVoiceTranscriber ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *statusByID; ///< mid -> IMVoiceTranscribeStatus
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *textCache;          ///< key -> NSString 或 NSNull（已查过无值）
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *collapsed;              ///< 本地折叠的 mid（「取消转文字」），落盘、按加入顺序淘汰
@end

@implementation IMVoiceTranscriber

+ (instancetype)sharedTranscriber {
    static IMVoiceTranscriber *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [IMVoiceTranscriber new]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _statusByID = [NSMutableDictionary dictionary];
        _textCache = [NSMutableDictionary dictionary];
        NSArray *saved = [[NSUserDefaults standardUserDefaults] stringArrayForKey:kIMVoiceTranscriptCollapsedKey];
        _collapsed = saved.count > 0 ? [NSMutableOrderedSet orderedSetWithArray:saved] : [NSMutableOrderedSet orderedSet];
    }
    return self;
}

- (nullable NSString *)cachedTextForContent:(NSString *)content {
    if (content.length == 0) { return nil; }
    // 内存缓存优先——滚动列表 configure 每 cell 都会来查一次，直接读 NSUserDefaults
    // 会触发磁盘同步 IO，语音多时列表明显卡顿（2026-08-26 实测过的坑）。
    NSString *key = IMVoiceTranscriptKey(content);
    id v = self.textCache[key];
    if (v == NSNull.null) { return nil; }
    if ([v isKindOfClass:NSString.class]) { return [(NSString *)v length] > 0 ? v : nil; }
    NSString *t = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    self.textCache[key] = t.length > 0 ? (id)t : (id)NSNull.null;
    return t.length > 0 ? t : nil;
}

- (void)transcribeConvID:(NSString *)convID
                 convSeq:(int64_t)convSeq
                 content:(NSString *)content
               messageID:(NSString *)messageID {
    if (messageID.length == 0 || convID.length == 0 || convSeq <= 0) { return; }
    [self expandMessageID:messageID];

    NSString *cached = [self cachedTextForContent:content];
    if (cached.length > 0) {
        [self setStatus:IMVoiceTranscribeStatusDone forID:messageID text:cached convID:convID];
        return;
    }
    // 已入队就别再发一遍：pending 期间没有本地缓存，菜单仍显「转文字」，用户等不及会连点，
    // 每点一次就是一个 POST（各占服务端一次限流额度）+ 结果到达时一轮整表行高重算。
    // 逃生门是「取消转文字」——collapseMessageID: 会清掉状态位。
    if ([self statusForMessageID:messageID] == IMVoiceTranscribeStatusRecognizing) { return; }
    NSString *token = IMHTTPService.sharedService.currentToken ?: @"";
    if (token.length == 0) {
        [self setStatus:IMVoiceTranscribeStatusUnavailable forID:messageID text:@"未登录，无法转文字" convID:convID];
        return;
    }
    [self setStatus:IMVoiceTranscribeStatusRecognizing forID:messageID text:nil convID:convID];

    __weak typeof(self) weakSelf = self;
    [[IMHTTPService sharedService] transcribeVoiceWithToken:token convID:convID convSeq:convSeq
                                                 completion:^(NSString *status, NSString *text, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        if (error) {
            // 文案已由 IMHTTPService 按业务码映射（IMFriendlyMessageForCode，含 5001xx/100002）。
            NSString *tip = error.localizedDescription.length > 0 ? error.localizedDescription : @"转文字失败，请稍后重试";
            [self setStatus:IMVoiceTranscribeStatusUnavailable forID:messageID text:tip convID:convID];
            return;
        }
        // pending：服务端已入队，保持"识别中…"，等 WS voice_transcript 帧。
        [self applyRemoteStatus:status text:text content:content convID:convID messageID:messageID];
    }];
}

- (void)applyRemoteStatus:(NSString *)status
                     text:(NSString *)text
                  content:(NSString *)content
                   convID:(NSString *)convID
                messageID:(NSString *)messageID {
    if (messageID.length == 0) { return; }
    BOOL collapsed = [self isCollapsedMessageID:messageID]; ///< 等结果期间用户点了「取消转文字」
    if ([status isEqualToString:@"done"] && text.length > 0) {
        NSString *key = IMVoiceTranscriptKey(content);
        self.textCache[key] = text;
        if (content.length > 0) { [[NSUserDefaults standardUserDefaults] setObject:text forKey:key]; }
        // 结果照落缓存（下次点开秒出），但**不广播**——否则识别中途取消的那条会被结果重新撑开。
        if (collapsed) { return; }
        [self setStatus:IMVoiceTranscribeStatusDone forID:messageID text:text convID:convID];
        return;
    }
    if (collapsed) { return; }
    if ([status isEqualToString:@"failed"]) {
        [self setStatus:IMVoiceTranscribeStatusUnavailable forID:messageID
                   text:IMFriendlyMessageForCode(500102) convID:convID]; // TranscribeFailed
        return;
    }
    // pending 或空 status：维持识别中。
    [self setStatus:IMVoiceTranscribeStatusRecognizing forID:messageID text:nil convID:convID];
}

- (IMVoiceTranscribeStatus)statusForMessageID:(NSString *)mid {
    if (mid.length == 0) { return IMVoiceTranscribeStatusIdle; }
    NSNumber *n = self.statusByID[mid];
    return n ? (IMVoiceTranscribeStatus)n.integerValue : IMVoiceTranscribeStatusIdle;
}

- (nullable NSString *)visibleTextForMessageID:(NSString *)mid content:(NSString *)content {
    if ([self isCollapsedMessageID:mid]) { return nil; }
    return [self cachedTextForContent:content];
}

- (void)expandMessageID:(NSString *)mid {
    if (![self.collapsed containsObject:mid]) { return; }
    [self.collapsed removeObject:mid];
    [self persistCollapsed]; // 折叠名单落盘，跨启动一致
}

- (void)collapseMessageID:(NSString *)mid {
    if (mid.length == 0) { return; }
    [self.collapsed removeObject:mid]; // 先移再加，保证重复折叠时刷新到队尾（淘汰按最久未折叠）
    [self.collapsed addObject:mid];
    while (self.collapsed.count > kIMVoiceTranscriptCollapsedMax) {
        [self.collapsed removeObjectAtIndex:0];
    }
    [self.statusByID removeObjectForKey:mid];
    [self persistCollapsed];
}

- (void)persistCollapsed {
    [[NSUserDefaults standardUserDefaults] setObject:self.collapsed.array forKey:kIMVoiceTranscriptCollapsedKey];
}

- (BOOL)isCollapsedMessageID:(NSString *)mid {
    return mid.length > 0 && [self.collapsed containsObject:mid];
}

- (void)setStatus:(IMVoiceTranscribeStatus)status forID:(NSString *)mid text:(nullable NSString *)text convID:(nullable NSString *)convID {
    if (mid.length == 0) { return; }
    self.statusByID[mid] = @(status);
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"messageID"] = mid;
    if (convID) { info[@"convID"] = convID; }
    info[@"status"] = @(status);
    if (text) { info[@"text"] = text; }
    [[NSNotificationCenter defaultCenter] postNotificationName:IMVoiceTranscriberDidChangeNotification object:self userInfo:info];
}

@end
