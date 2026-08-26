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
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *textCache;         ///< 内存转写缓存：key=IMVoiceTranscriptKey；值=NSString 或 NSNull（表示已查过 NSUserDefaults 无值）
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
    if (self) {
        _statusByID = [NSMutableDictionary dictionary];
        _textCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (nullable NSString *)cachedTextForMessageID:(NSString *)mid convID:(NSString *)convID owner:(NSString *)ownerUID {
    if (!mid) { return nil; }
    // 内存缓存优先——滚动列表 configure 每 cell 都会来查一次，
    // 曾直接读 NSUserDefaults stringForKey 每次触发磁盘同步 IO → 大量语音消息时列表滑动明显卡顿（2026-08-27 修 #3）。
    NSString *key = IMVoiceTranscriptKey(ownerUID, convID, mid);
    id v = self.textCache[key];
    if (v == NSNull.null) { return nil; }      // 已查过：NSUserDefaults 里没有
    if ([v isKindOfClass:NSString.class]) { return [(NSString *)v length] > 0 ? v : nil; }
    NSString *t = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    self.textCache[key] = t.length > 0 ? (id)t : (id)NSNull.null;
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

/// 权限已给但识别器 available=NO 时的可操作提示（用户 2026-08-27 报"给了权限还失败"）。
+ (NSString *)unavailableReasonDescription {
    // 探测系统偏好语言是否支持本地识别，给出更具体的原因。
    BOOL anyLocalSupported = NO;
    if (@available(iOS 13.0, *)) {
        for (NSString *code in [NSLocale preferredLanguages]) {
            SFSpeechRecognizer *r = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:code]];
            if (r && r.supportsOnDeviceRecognition) { anyLocalSupported = YES; break; }
        }
    }
    if (anyLocalSupported) {
        // 本地识别支持但 recognizer.available=NO——语言资源包未就绪。iOS 首次使用需联网让系统在后台下载，
        // 完成后杀掉重开也仍旧不会自动"就位"；触发下载的最稳做法是打开系统听写并联网一次。
        // 2026-08-27 更新：用户反馈"杀掉 App 长按转文字仍是这条提示"——就是因为本地包未下载，
        // 光重启 App 帮不了。补上明确操作步骤，避免用户反复重试。
        return @"转文字暂不可用：本机语音识别语言包未就绪。\n"
               @"解决方式（任选其一，需联网一次）：\n"
               @"1）打开「设置 → 通用 → 键盘 → 启用听写」并联网等几分钟，iOS 会在后台下载中文识别包；\n"
               @"2）保持联网状态再点一次「转文字」触发首次识别；\n"
               @"下载完成后即可长期离线使用，无需重复操作。";
    }
    // 无本地支持 = 依赖云端 → 大概率无网。
    return @"转文字需要网络：当前语言不支持本机离线识别。请连网后再试。";
}

- (void)runRecognitionForID:(NSString *)mid convID:(NSString *)convID owner:(NSString *)ownerUID audioURL:(NSURL *)audioURL {
    // 挑最靠谱的 recognizer：先看系统偏好里第一个可用（且优先本地识别支持）的；否则退到 default en_US。
    // 用户 2026-08-27 报"给了权限但仍暂不可用"——多半是 recognizer.available=NO（无网 + 中文无本地引擎）。
    SFSpeechRecognizer *recognizer = nil;
    for (NSString *code in [NSLocale preferredLanguages]) {
        SFSpeechRecognizer *r = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:code]];
        if (r.isAvailable) {
            // 优先支持本地识别的 recognizer——即使系统偏好语言不同，中文机型上如果 zh-CN 不本地支持
            // 但 en-US 本地支持，宁可用 en-US 至少能离线跑；否则再用系统偏好第一可用。
            if (@available(iOS 13.0, *)) {
                if (r.supportsOnDeviceRecognition) { recognizer = r; break; }
            }
            if (!recognizer) { recognizer = r; } // 记住第一个 available 作为兜底
        }
    }
    if (!recognizer) { recognizer = [SFSpeechRecognizer new]; }
    if (!recognizer.isAvailable) {
        // 权限已给（能走到这），但识别器不可用——极大概率是网络断（云端识别需在线）+ 语言不支持本地。
        // 详情由 IMVoiceTranscriber.unavailableReasonDescription 给出可操作提示。
        [self setStatus:IMVoiceTranscribeStatusUnavailable forID:mid text:nil convID:convID];
        return;
    }

    SFSpeechURLRecognitionRequest *req = [[SFSpeechURLRecognitionRequest alloc] initWithURL:audioURL];
    req.shouldReportPartialResults = YES;
    // 只在既支持本地又 available 时才强制本地识别——**否则让系统走云端**，避免 supportsOnDeviceRecognition
    // 返回 YES 但本地包未下载/语言不匹配的场景下 requiresOnDeviceRecognition=YES 立即失败（Apple 曾有该组合）。
    if (@available(iOS 13.0, *)) {
        if (recognizer.supportsOnDeviceRecognition) { req.requiresOnDeviceRecognition = YES; }
    }
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
                    NSString *k = IMVoiceTranscriptKey(ownerUID, convID, mid);
                    [[NSUserDefaults standardUserDefaults] setObject:text forKey:k];
                    self.textCache[k] = text; // 回填内存缓存，避免下次 configure 再触 NSUserDefaults
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
