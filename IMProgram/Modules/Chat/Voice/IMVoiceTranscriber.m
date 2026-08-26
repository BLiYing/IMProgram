//
//  IMVoiceTranscriber.m
//

#import "IMVoiceTranscriber.h"
#import <Speech/Speech.h>

NSNotificationName const IMVoiceTranscriberDidChangeNotification = @"IMVoiceTranscriberDidChangeNotification";

/// 缓存 key：per-uid + per-conv + per-mid。owner 空 → "anon"。conv 空 → "na"。
/// 命名与 IMVoicePlayer 的已播集合同源，方便运维定位。
static NSString *IMVoiceTranscriptKey(NSString *ownerUID, NSString *convID, NSString *mid) {
    return [NSString stringWithFormat:@"im.voice.transcript.%@.%@.%@",
            ownerUID ?: @"anon", convID ?: @"na", mid ?: @""];
}

@interface IMVoiceTranscriber ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *statusByID; ///< 内存状态表（NSNumber = IMVoiceTranscribeStatus）
@property (nonatomic, strong, nullable) SFSpeechRecognitionTask *currentTask;
@property (nonatomic, copy, nullable) NSString *currentID;
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
    if (self) { _statusByID = [NSMutableDictionary dictionary]; }
    return self;
}

- (nullable NSString *)cachedTextForMessageID:(NSString *)mid convID:(NSString *)convID owner:(NSString *)ownerUID {
    if (!mid) { return nil; }
    NSString *t = [[NSUserDefaults standardUserDefaults] stringForKey:IMVoiceTranscriptKey(ownerUID, convID, mid)];
    return t.length > 0 ? t : nil;
}

- (IMVoiceTranscribeStatus)statusForMessageID:(NSString *)mid {
    if (!mid) { return IMVoiceTranscribeStatusIdle; }
    NSNumber *n = self.statusByID[mid];
    return n ? (IMVoiceTranscribeStatus)n.integerValue : IMVoiceTranscribeStatusIdle;
}

- (void)transcribeMessageID:(NSString *)mid convID:(NSString *)convID owner:(NSString *)ownerUID audioURL:(NSURL *)audioURL {
    if (!mid || !audioURL) { return; }

    NSString *cached = [self cachedTextForMessageID:mid convID:convID owner:ownerUID];
    if (cached) {
        [self setStatus:IMVoiceTranscribeStatusDone forID:mid text:cached convID:convID];
        return;
    }

    [self setStatus:IMVoiceTranscribeStatusRecognizing forID:mid text:nil convID:convID];
    // 先同步查一次授权状态：已授权立刻开跑；未决才弹权限；被拒/受限直接不可用（不必再弹请求，
    // 系统只弹一次；再请求也只会立刻回 Denied——用户 8-27 反馈的"提示去设置开启"其实要先区分是
    // 用户拒过、还是识别不可用——先查状态可让文案更贴切）。
    SFSpeechRecognizerAuthorizationStatus st = [SFSpeechRecognizer authorizationStatus];
    if (st == SFSpeechRecognizerAuthorizationStatusAuthorized) {
        [self runRecognitionForID:mid convID:convID owner:ownerUID audioURL:audioURL];
        return;
    }
    if (st == SFSpeechRecognizerAuthorizationStatusDenied || st == SFSpeechRecognizerAuthorizationStatusRestricted) {
        [self setStatus:IMVoiceTranscribeStatusUnavailable forID:mid text:nil convID:convID];
        return;
    }
    // Undetermined → 弹权限。
    __weak typeof(self) weakSelf = self;
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
                [self setStatus:IMVoiceTranscribeStatusUnavailable forID:mid text:nil convID:convID];
                return;
            }
            [self runRecognitionForID:mid convID:convID owner:ownerUID audioURL:audioURL];
        });
    }];
}

/// 供上层区分文案：Denied/Restricted → 引导设置；Unavailable（识别器不可用/网络等） → 通用不可用。
+ (BOOL)isAuthorizationDeniedOrRestricted {
    SFSpeechRecognizerAuthorizationStatus st = [SFSpeechRecognizer authorizationStatus];
    return st == SFSpeechRecognizerAuthorizationStatusDenied || st == SFSpeechRecognizerAuthorizationStatusRestricted;
}

- (void)runRecognitionForID:(NSString *)mid convID:(NSString *)convID owner:(NSString *)ownerUID audioURL:(NSURL *)audioURL {
    // 语言：跟随系统首选（zh-Hans/en/etc）；不可用退降到默认。
    SFSpeechRecognizer *recognizer = nil;
    for (NSString *code in [NSLocale preferredLanguages]) {
        SFSpeechRecognizer *r = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:code]];
        if (r.isAvailable) { recognizer = r; break; }
    }
    if (!recognizer) { recognizer = [SFSpeechRecognizer new]; }
    if (!recognizer.isAvailable) {
        [self setStatus:IMVoiceTranscribeStatusUnavailable forID:mid text:nil convID:convID];
        return;
    }

    SFSpeechURLRecognitionRequest *req = [[SFSpeechURLRecognitionRequest alloc] initWithURL:audioURL];
    req.shouldReportPartialResults = YES; // 逐词流出，让 UI 有渐进感（VOICE_MESSAGE_DESIGN §5.5 保留的动效）
    // 只跑一次识别——不接受同一 mid 并发。上次没结束就 cancel 换新的（其实上层 UI 应防重复触发）。
    [self.currentTask cancel];
    self.currentID = mid;
    __weak typeof(self) weakSelf = self;
    self.currentTask = [recognizer recognitionTaskWithRequest:req resultHandler:^(SFSpeechRecognitionResult *_Nullable result, NSError *_Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error && !result) {
                [self setStatus:IMVoiceTranscribeStatusUnavailable forID:mid text:nil convID:convID];
                self.currentTask = nil;
                return;
            }
            NSString *text = result.bestTranscription.formattedString ?: @"";
            [self setStatus:(result.isFinal ? IMVoiceTranscribeStatusDone : IMVoiceTranscribeStatusRecognizing)
                     forID:mid text:text convID:convID];
            if (result.isFinal) {
                // 只在识别完成时持久化，避免每次 partial 都写盘。
                if (text.length > 0) {
                    [[NSUserDefaults standardUserDefaults] setObject:text forKey:IMVoiceTranscriptKey(ownerUID, convID, mid)];
                }
                self.currentTask = nil;
            }
        });
    }];
}

- (void)setStatus:(IMVoiceTranscribeStatus)status forID:(NSString *)mid text:(nullable NSString *)text convID:(nullable NSString *)convID {
    if (!mid) { return; }
    self.statusByID[mid] = @(status);
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"messageID"] = mid;
    if (convID) { info[@"convID"] = convID; }
    info[@"status"] = @(status);
    if (text) { info[@"text"] = text; }
    [[NSNotificationCenter defaultCenter] postNotificationName:IMVoiceTranscriberDidChangeNotification object:self userInfo:info];
}

@end
