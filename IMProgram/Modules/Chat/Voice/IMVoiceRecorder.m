//
//  IMVoiceRecorder.m
//

#import "IMVoiceRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h> // CMTimeRange / kCMTimeZero（多段合并用）

/// waveform 采样数：60（每 100ms 一次 tick × 平均 6s 语音 = 60 帧），与设计文档 §1 的
/// 服务端上限 120 字节留一半余量（同一批语音条振幅指纹再上采/下采都不会突破 max）。
static const NSInteger IMVoiceWaveformMaxSamples = 60;
/// 短录阈值 0.6s（<0.6s 提示"说话时间太短"并丢弃，见设计文档 §5.1）。
static const int64_t IMVoiceShortRecordThresholdMillis = 600;
/// 最大时长 5min（超上限自动停录进入待发送态）。
static const int64_t IMVoiceMaxDurationMillis = 5 * 60 * 1000;
/// 采样间隔：100ms（10Hz）——足够呼吸环流畅、又给 5min 满录 60 帧上限留余量。
static const NSTimeInterval IMVoiceSampleInterval = 0.1;

@interface IMVoiceRecorder () <AVAudioRecorderDelegate>
@property (nonatomic, strong, nullable) AVAudioRecorder *recorder;
@property (nonatomic, strong, nullable) NSTimer *sampleTimer;
@property (nonatomic, strong, nullable) NSURL *fileURL; ///< 当前正在写入的段 URL；pause 时 finalize 加入 segmentURLs 后置 nil
@property (nonatomic, assign) int64_t startedAtMillis;
/// 振幅采样累积（每字节 0~100 百分比）；停录时截取或上/下采到 IMVoiceWaveformMaxSamples。
@property (nonatomic, strong) NSMutableData *samples;
@property (nonatomic, assign, readwrite) BOOL recording;
@property (nonatomic, assign, readwrite) BOOL paused;
@property (nonatomic, assign) BOOL sessionActive;
@property (nonatomic, assign) int64_t pausedAtMillis; ///< 暂停时刻（用于 resume 时把停止的时长补回 startedAtMillis）
/// 分段列表（§14 试听/继续录制）：每次 pause 把当前 fileURL 加入；resume 新建 fileURL；
/// stopAndSend 时如 >1 段异步 export 合并为最终文件。cancel 全删。
@property (nonatomic, strong) NSMutableArray<NSURL *> *segmentURLs;
/// providePreviewURL 生成的合并 tmp（多段试听用）——单独跟踪，deleteAllSegments/finalize 时清；曾泄漏（code-review 2026-08-27）。
@property (nonatomic, strong, nullable) NSURL *previewCacheURL;
/// 主动 pause 前置 YES：让 audioRecorderDidFinishRecording: 早退不误判为 ReachedMax。
@property (nonatomic, assign) BOOL manualStopForPause;
/// 已通知过上限：sampleTimer 里到点后置 YES，避免重复触发 delegate。
@property (nonatomic, assign) BOOL maxNotified;
@end

@implementation IMVoiceRecorder

+ (void)requestMicrophonePermission:(void (^)(BOOL))completion {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    // iOS 17+: AVAudioApplication.requestRecordPermissionWithCompletionHandler:；老 API 仍可用。
    [session requestRecordPermission:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) { completion(granted); }
        });
    }];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _samples = [NSMutableData dataWithCapacity:IMVoiceWaveformMaxSamples];
        _maxDurationMillis = IMVoiceMaxDurationMillis;
        _segmentURLs = [NSMutableArray array];
    }
    return self;
}

/// 生成 tmp/voice/<uuid>.m4a URL——start/resume 各 new 一段（每次暂停 = 一段收尾）。
- (NSURL *)newSegmentURL {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"voice"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *file = [NSString stringWithFormat:@"%@.m4a", NSUUID.UUID.UUIDString];
    return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:file]];
}

/// 用当前 fileURL 起一个新的 AVAudioRecorder（start / resume 共用）。成功返回 YES。
- (BOOL)armNewRecorderAtURL:(NSURL *)url {
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatMPEG4AAC),
        AVSampleRateKey: @16000.0,
        AVNumberOfChannelsKey: @1,
        AVEncoderAudioQualityKey: @(AVAudioQualityMedium),
        AVEncoderBitRateKey: @24000,
    };
    NSError *err = nil;
    AVAudioRecorder *r = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&err];
    if (!r || err) { return NO; }
    r.delegate = self;
    r.meteringEnabled = YES;
    // recordForDuration 走当前"剩余上限"（不是每段满 5min，累计到 5min 停）。
    NSTimeInterval remain = (NSTimeInterval)MAX((int64_t)1000, IMVoiceMaxDurationMillis - self.elapsedMillis) / 1000.0;
    if (![r recordForDuration:remain]) { return NO; }
    self.recorder = r;
    return YES;
}

- (void)start {
    if (self.recording) { return; }
    [self.samples setLength:0];
    [self.segmentURLs removeAllObjects];
    self.maxNotified = NO;
    NSError *sessionErr = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    AVAudioSessionCategoryOptions opts = AVAudioSessionCategoryOptionDefaultToSpeaker;
    if (@available(iOS 8.0, *)) { opts |= AVAudioSessionCategoryOptionAllowBluetoothHFP; }
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
                    mode:AVAudioSessionModeSpokenAudio
                 options:opts
                   error:&sessionErr];
    if (sessionErr) {
        [self finishWithReason:IMVoiceRecorderStopReasonError durationMillis:0];
        return;
    }
    [session setActive:YES error:&sessionErr];
    if (sessionErr) {
        [self finishWithReason:IMVoiceRecorderStopReasonError durationMillis:0];
        return;
    }
    self.sessionActive = YES;
    // 每段一个 tmp URL（发送成功/取消清理；App 杀死随 tmp 清）。多段暂停时 stopAndSend 合并（§14）。
    self.fileURL = [self newSegmentURL];
    self.startedAtMillis = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    if (![self armNewRecorderAtURL:self.fileURL]) {
        [self finishWithReason:IMVoiceRecorderStopReasonError durationMillis:0];
        return;
    }
    self.recording = YES;
    __weak typeof(self) weakSelf = self;
    self.sampleTimer = [NSTimer scheduledTimerWithTimeInterval:IMVoiceSampleInterval repeats:YES block:^(NSTimer *_) {
        [weakSelf onSample];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.sampleTimer forMode:NSRunLoopCommonModes];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterruption:)
                                                 name:AVAudioSessionInterruptionNotification object:session];

    if ([self.delegate respondsToSelector:@selector(voiceRecorderDidStart:)]) {
        [self.delegate voiceRecorderDidStart:self];
    }
}

- (void)stopAndSend {
    if (!self.recording && !self.paused) { return; }
    int64_t dur = [self elapsedMillis];
    // 收当前段：正在录 → stop finalize + 加进 segments；已暂停 → 段已在 segments 里。
    if (self.recording && self.recorder) {
        self.manualStopForPause = YES; // 让 didFinish 早退不误报 ReachedMax
        [self.recorder stop];
        if (self.fileURL) { [self.segmentURLs addObject:self.fileURL]; }
        self.fileURL = nil;
    }
    self.recording = NO;
    self.paused = NO;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    if (dur < IMVoiceShortRecordThresholdMillis) {
        [self deleteAllSegments];
        [self finishWithReason:IMVoiceRecorderStopReasonTooShort durationMillis:dur];
        return;
    }
    [self finalizeAndDeliverWithReason:IMVoiceRecorderStopReasonUserSend durationMillis:dur];
}

- (void)cancel {
    if (!self.recording && !self.paused) { return; }
    if (self.recording && self.recorder) {
        self.manualStopForPause = YES;
        [self.recorder stop];
    }
    self.recording = NO;
    self.paused = NO;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    [self deleteAllSegments];
    [self finishWithReason:IMVoiceRecorderStopReasonUserCancel durationMillis:0];
}

#pragma mark - Pause / Resume（§14：多段模型——每次 pause 收尾一段，resume 新起一段）

- (void)pause {
    if (!self.recording || self.paused) { return; }
    // 关键：真 stop finalize 当前段（AAC .m4a 完整可播），加入 segmentURLs 供试听/合并。
    // 曾用 AVAudioRecorder.pause（不 finalize），暂停期间文件 moov 未写、AVAudioPlayer 打不开——
    // §14 试听走 IMVoicePlayer 就必须 finalize（2026-08-27 改多段模型）。
    self.manualStopForPause = YES;
    [self.recorder stop];
    if (self.fileURL) { [self.segmentURLs addObject:self.fileURL]; self.fileURL = nil; }
    self.recorder = nil;
    self.paused = YES;
    self.recording = NO; // 与 sample 内 recorder.isRecording 保持一致
    self.pausedAtMillis = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
}

- (void)resume {
    if (!self.paused) { return; }
    // 新起一段（每次 pause/resume 都是新 m4a），发送时合并；startedAtMillis 补回暂停差值让 elapsed 只算真实录音。
    int64_t nowMs = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    int64_t pauseDur = MAX((int64_t)0, nowMs - self.pausedAtMillis);
    self.startedAtMillis += pauseDur;
    // 中断（来电）会让系统停用 session——record 前重新激活。
    AVAudioSession *session = [AVAudioSession sharedInstance];
    AVAudioSessionCategoryOptions opts = AVAudioSessionCategoryOptionDefaultToSpeaker;
    if (@available(iOS 8.0, *)) { opts |= AVAudioSessionCategoryOptionAllowBluetoothHFP; }
    [session setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeSpokenAudio options:opts error:NULL];
    [session setActive:YES error:NULL];
    self.sessionActive = YES;
    self.fileURL = [self newSegmentURL];
    if (![self armNewRecorderAtURL:self.fileURL]) {
        // 新段起不来 → 回暂停态（不静默丢，用户仍可发送已录段/删除；下次 resume 再试）。
        self.fileURL = nil;
        return;
    }
    self.paused = NO;
    self.recording = YES;
    __weak typeof(self) weakSelf = self;
    self.sampleTimer = [NSTimer scheduledTimerWithTimeInterval:IMVoiceSampleInterval repeats:YES block:^(NSTimer *_) {
        [weakSelf onSample];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.sampleTimer forMode:NSRunLoopCommonModes];
}

#pragma mark - Preview（§14 试听：合并所有段成一个可播 URL）

- (void)providePreviewURL:(void (^)(NSURL *_Nullable, NSError *_Nullable))completion {
    if (!completion) { return; }
    if (self.recording) {
        completion(nil, [NSError errorWithDomain:@"IMVoiceRecorder" code:-11
                                        userInfo:@{NSLocalizedDescriptionKey: @"录制中不能试听"}]);
        return;
    }
    if (self.segmentURLs.count == 0) {
        completion(nil, [NSError errorWithDomain:@"IMVoiceRecorder" code:-12
                                        userInfo:@{NSLocalizedDescriptionKey: @"暂无可试听内容"}]);
        return;
    }
    if (self.segmentURLs.count == 1) {
        // 单段直接返回，省去 export（用户暂停一次即试听是常见路径）。
        completion(self.segmentURLs.firstObject, nil);
        return;
    }
    // 多段合并：如已有 previewCacheURL 且 segments 未变（简化版：只在 caller 未 resume 时才生效），
    // 保守起见每次仍新导出——但**旧的 previewCacheURL 必先删**（曾未清理导致每次试听残留 tmp）。
    if (self.previewCacheURL) {
        [[NSFileManager defaultManager] removeItemAtURL:self.previewCacheURL error:NULL];
        self.previewCacheURL = nil;
    }
    NSURL *out = [self newSegmentURL];
    [self exportMergedURL:[self.segmentURLs copy] toURL:out completion:^(NSError *err) {
        if (!err) { self.previewCacheURL = out; } // 跟踪：cancel/finalize 时会清（deleteAllSegments 已覆盖）
        completion(err ? nil : out, err);
    }];
}

/// 用 AVMutableComposition + AVAssetExportSession 把 segments 逐段 append 合并到 outURL（AAC passthrough）。
- (void)exportMergedURL:(NSArray<NSURL *> *)segments toURL:(NSURL *)outURL completion:(void (^)(NSError *))completion {
    AVMutableComposition *comp = [AVMutableComposition composition];
    AVMutableCompositionTrack *audioTrack = [comp addMutableTrackWithMediaType:AVMediaTypeAudio
                                                             preferredTrackID:kCMPersistentTrackID_Invalid];
    CMTime cursor = kCMTimeZero;
    NSError *insertErr = nil;
    for (NSURL *segURL in segments) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:segURL options:nil];
        AVAssetTrack *at = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
        if (!at) { continue; }
        CMTimeRange range = CMTimeRangeMake(kCMTimeZero, asset.duration);
        if (![audioTrack insertTimeRange:range ofTrack:at atTime:cursor error:&insertErr]) {
            completion(insertErr ?: [NSError errorWithDomain:@"IMVoiceRecorder" code:-13
                                                    userInfo:@{NSLocalizedDescriptionKey: @"合并音频段失败"}]);
            return;
        }
        cursor = CMTimeAdd(cursor, asset.duration);
    }
    [[NSFileManager defaultManager] removeItemAtURL:outURL error:NULL];
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:comp
                                                                    presetName:AVAssetExportPresetAppleM4A];
    export.outputURL = outURL;
    export.outputFileType = AVFileTypeAppleM4A;
    [export exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (export.status != AVAssetExportSessionStatusCompleted) {
                completion(export.error ?: [NSError errorWithDomain:@"IMVoiceRecorder" code:-14
                                                            userInfo:@{NSLocalizedDescriptionKey: @"导出合并音频失败"}]);
                return;
            }
            completion(nil);
        });
    }];
}

- (NSArray<NSNumber *> *)currentAmplitudes {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:self.samples.length];
    const uint8_t *bytes = self.samples.bytes;
    for (NSUInteger i = 0; i < self.samples.length; i++) {
        [out addObject:@((float)MIN((uint8_t)100, bytes[i]) / 100.f)];
    }
    return out;
}

#pragma mark - Sampling

- (int64_t)elapsedMillis {
    // 暂停期间以 pausedAtMillis 为基准——否则暂停中的 stopAndSend/删除判定会把暂停时长算进 duration
    //（表现为：暂停 1 分钟再发送，气泡时长凭空多 1 分钟，2026-08-26 修）。
    int64_t ref = self.paused ? self.pausedAtMillis
                              : (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    return MAX(0, ref - self.startedAtMillis);
}

- (void)onSample {
    if (!self.recorder.isRecording) { return; }
    [self.recorder updateMeters];
    float db = [self.recorder averagePowerForChannel:0]; // -160..0 dB
    // 归一化：-50dB 视作静音，0dB 视作满幅（线性映射；语音功率典型 -30~-5dB）。
    float normalized = powf(10.0f, db / 20.0f); // 0..1
    normalized = MAX(0, MIN(1, normalized));
    // 采样存 0~100 的百分比，跟服务端 waveform 校验一致（每字节 0~100）。
    if (self.samples.length < 4096) { // 硬防跑飞
        uint8_t sample = (uint8_t)MIN(100.f, normalized * 100.f);
        [self.samples appendBytes:&sample length:1];
    }
    int64_t elapsed = [self elapsedMillis];
    if ([self.delegate respondsToSelector:@selector(voiceRecorder:didSampleAmplitude:elapsedMillis:)]) {
        [self.delegate voiceRecorder:self didSampleAmplitude:normalized elapsedMillis:elapsed];
    }
    // §12 UI 硬闸：到点通知上层决定（锁定态自动 stopAndSend；按住态转锁定+pause）——只通知一次，
    // 上层收到即会改变状态；避免每 tick 重复触发。曾只靠 recordForDuration: 系统闸，实测 5:21（2026-08-27）。
    if (!self.maxNotified && elapsed >= self.maxDurationMillis) {
        self.maxNotified = YES;
        if ([self.delegate respondsToSelector:@selector(voiceRecorderDidReachMaxDuration:)]) {
            [self.delegate voiceRecorderDidReachMaxDuration:self];
        }
    }
}

#pragma mark - AVAudioRecorderDelegate

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    // 主动 stop（pause/stopAndSend/cancel）→ 早退：调用点已处理段落归档与最终 finish。
    if (self.manualStopForPause) { self.manualStopForPause = NO; return; }
    if (!self.recording) { return; }
    // 系统层 recordForDuration: 到点自动 stop（双保险；§12 UI 硬闸已在 sampleTimer 通知过 delegate）。
    int64_t dur = [self elapsedMillis];
    self.recording = NO;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    if (self.fileURL) { [self.segmentURLs addObject:self.fileURL]; self.fileURL = nil; }
    if (flag && dur >= IMVoiceShortRecordThresholdMillis) {
        [self finalizeAndDeliverWithReason:IMVoiceRecorderStopReasonReachedMax durationMillis:dur];
    } else {
        [self deleteAllSegments];
        [self finishWithReason:IMVoiceRecorderStopReasonTooShort durationMillis:dur];
    }
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error {
    if (!self.recording) { return; }
    self.recording = NO;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    [self deleteAllSegments];
    [self finishWithReason:IMVoiceRecorderStopReasonError durationMillis:[self elapsedMillis]];
}

- (void)handleInterruption:(NSNotification *)note {
    // AVAudioSession 通知由系统内部线程投递（observer 未指定 queue）；本方法会 invalidate 主 runloop
    // 定时器并经 delegate 驱动 UIKit（HUD/LockedBar/toast），必须回主线程执行。
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self handleInterruption:note]; });
        return;
    }
    NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
    if (type.unsignedIntegerValue != AVAudioSessionInterruptionTypeBegan) { return; }
    if (!self.recording || self.paused) { return; }
    int64_t dur = [self elapsedMillis];
    if (dur < IMVoiceShortRecordThresholdMillis) {
        self.manualStopForPause = YES;
        [self.recorder stop];
        self.recording = NO;
        [self.sampleTimer invalidate];
        self.sampleTimer = nil;
        [self deleteAllSegments];
        [self finishWithReason:IMVoiceRecorderStopReasonTooShort durationMillis:dur];
        return;
    }
    // 设计 §5.4（2026-08-26 补齐）：中断自动转**锁定暂停态**——录音暂停、文件保留，
    // 上层把 UI 切到锁定行（发送/删除/继续），不再是 P0 的"直接自动发送"。
    [self pause];
    if ([self.delegate respondsToSelector:@selector(voiceRecorderWasInterrupted:)]) {
        [self.delegate voiceRecorderWasInterrupted:self];
    }
}

#pragma mark - Finalize

- (void)finishWithReason:(IMVoiceRecorderStopReason)reason durationMillis:(int64_t)dur {
    if (self.sessionActive) {
        NSError *e = nil;
        [[AVAudioSession sharedInstance] setActive:NO
                                       withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                             error:&e];
        // 出错也不 log：常见于中断路径 session 已由系统抢占；重激活失败会 next start 修复。
        self.sessionActive = NO;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // 非成功分支（Cancel/TooShort/Error）—— 段列表已清（deleteAllSegments），直接回 delegate 无 fileURL。
    if ([self.delegate respondsToSelector:@selector(voiceRecorder:didStopWithReason:fileURL:waveform:duration:)]) {
        [self.delegate voiceRecorder:self didStopWithReason:reason fileURL:nil waveform:nil duration:dur];
    }
    self.fileURL = nil;
    self.recorder = nil;
}

/// 成功送出分支（UserSend/ReachedMax）：合并 segments 后再回 delegate；单段无需 export。
- (void)finalizeAndDeliverWithReason:(IMVoiceRecorderStopReason)reason durationMillis:(int64_t)dur {
    NSString *waveBase64 = [self encodedWaveform];
    void (^deliver)(NSURL *) = ^(NSURL *finalURL) {
        // 归还 session 给别的 app。
        if (self.sessionActive) {
            [[AVAudioSession sharedInstance] setActive:NO
                                           withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:NULL];
            self.sessionActive = NO;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        if ([self.delegate respondsToSelector:@selector(voiceRecorder:didStopWithReason:fileURL:waveform:duration:)]) {
            [self.delegate voiceRecorder:self didStopWithReason:reason fileURL:finalURL waveform:waveBase64 duration:dur];
        }
        self.fileURL = nil;
        self.recorder = nil;
        [self.segmentURLs removeAllObjects];
    };
    if (self.segmentURLs.count == 0) { deliver(nil); return; }
    if (self.segmentURLs.count == 1) { deliver(self.segmentURLs.firstObject); return; }
    NSURL *out = [self newSegmentURL];
    NSArray *segs = [self.segmentURLs copy];
    [self exportMergedURL:segs toURL:out completion:^(NSError *err) {
        if (err) {
            // 合并失败 → 报错让 UI toast 提示用户重试。之前用 segs.lastObject 兜底 = 只发最后一段音频
            // 但 duration/waveform 是全段——播放条满格却只听得到 1/N，且前段音频永久丢失且用户无知。
            // code-review 2026-08-27 确认改硬失败：finalURL=nil 触发 didStop error toast，用户可重录/重发。
            deliver(nil);
            return;
        }
        // 清掉源段文件（final URL 已经是新的完整合并文件）。
        for (NSURL *u in segs) { [[NSFileManager defaultManager] removeItemAtURL:u error:NULL]; }
        // preview 缓存已被 final 取代，一并清（final 是新 URL，与 previewCacheURL 不同）。
        if (self.previewCacheURL) { [[NSFileManager defaultManager] removeItemAtURL:self.previewCacheURL error:NULL]; self.previewCacheURL = nil; }
        deliver(out);
    }];
}

- (void)deleteAllSegments {
    for (NSURL *u in self.segmentURLs) { [[NSFileManager defaultManager] removeItemAtURL:u error:NULL]; }
    [self.segmentURLs removeAllObjects];
    if (self.fileURL) { [[NSFileManager defaultManager] removeItemAtURL:self.fileURL error:NULL]; }
    if (self.previewCacheURL) { [[NSFileManager defaultManager] removeItemAtURL:self.previewCacheURL error:NULL]; self.previewCacheURL = nil; }
}

/// 把采样数组下采到 IMVoiceWaveformMaxSamples 长度并 base64 编码。
/// 采样过少（<8）直接 base64 原样，回退等高条纹交给收端。
- (nullable NSString *)encodedWaveform {
    NSUInteger n = self.samples.length;
    if (n == 0) { return nil; }
    NSData *raw;
    if (n <= (NSUInteger)IMVoiceWaveformMaxSamples) {
        raw = [self.samples copy];
    } else {
        // 下采：分 bucket 取最大值（保峰形，与设计文档 §1 的收端下采策略一致）。
        const uint8_t *src = self.samples.bytes;
        uint8_t out[IMVoiceWaveformMaxSamples] = {0};
        double stride = (double)n / (double)IMVoiceWaveformMaxSamples;
        for (NSInteger i = 0; i < IMVoiceWaveformMaxSamples; i++) {
            NSUInteger lo = (NSUInteger)(i * stride);
            NSUInteger hi = MIN(n, (NSUInteger)((i + 1) * stride));
            uint8_t m = 0;
            for (NSUInteger j = lo; j < hi; j++) { if (src[j] > m) { m = src[j]; } }
            out[i] = m;
        }
        raw = [NSData dataWithBytes:out length:IMVoiceWaveformMaxSamples];
    }
    return [raw base64EncodedStringWithOptions:0];
}

@end
