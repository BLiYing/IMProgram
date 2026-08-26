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

@interface IMVoiceTranscriber ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *statusByID; ///< mid -> IMVoiceTranscribeStatus
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *textCache;          ///< key -> NSString 或 NSNull（已查过无值）
@property (nonatomic, strong) NSMutableSet<NSString *> *collapsed;                     ///< 本地折叠的 mid（「取消转文字」）
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
        _collapsed = [NSMutableSet set];
    }
    return self;
}

+ (NSString *)messageForErrorCode:(NSInteger)code fallback:(NSString *)fallback {
    // 与 IMServer internal/errcode 的 5001xx 段对齐（CONVENTIONS §2.2）。
    switch (code) {
        case 500101: return @"转文字暂未开启（服务端未配置识别引擎）";
        case 500102: return @"识别失败，请稍后重试";
        case 500103: return @"转文字服务繁忙，请稍后再试";
        case 100002: return @"操作过于频繁，请稍后再试";
        default: break;
    }
    return fallback.length > 0 ? fallback : @"转文字失败，请稍后重试";
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
              messageID:(NSString *)messageID
                   token:(NSString *)token {
    if (messageID.length == 0 || convID.length == 0 || convSeq <= 0) { return; }
    [self.collapsed removeObject:messageID]; // 重新展开

    NSString *cached = [self cachedTextForContent:content];
    if (cached.length > 0) {
        [self setStatus:IMVoiceTranscribeStatusDone forID:messageID text:cached convID:convID];
        return;
    }
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
            NSString *tip = [IMVoiceTranscriber messageForErrorCode:error.code fallback:error.localizedDescription];
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
    if ([status isEqualToString:@"done"] && text.length > 0) {
        NSString *key = IMVoiceTranscriptKey(content);
        self.textCache[key] = text;
        if (content.length > 0) { [[NSUserDefaults standardUserDefaults] setObject:text forKey:key]; }
        [self setStatus:IMVoiceTranscribeStatusDone forID:messageID text:text convID:convID];
        return;
    }
    if ([status isEqualToString:@"failed"]) {
        [self setStatus:IMVoiceTranscribeStatusUnavailable forID:messageID
                   text:[IMVoiceTranscriber messageForErrorCode:500102 fallback:nil] convID:convID];
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

- (void)collapseMessageID:(NSString *)mid {
    if (mid.length == 0) { return; }
    [self.collapsed addObject:mid];
    [self.statusByID removeObjectForKey:mid];
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
