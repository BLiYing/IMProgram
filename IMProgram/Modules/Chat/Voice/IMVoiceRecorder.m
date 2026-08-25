//
//  IMVoiceRecorder.m
//

#import "IMVoiceRecorder.h"
#import <AVFoundation/AVFoundation.h>

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
@property (nonatomic, strong, nullable) NSURL *fileURL;
@property (nonatomic, assign) int64_t startedAtMillis;
/// 振幅采样累积（每字节 0~100 百分比）；停录时截取或上/下采到 IMVoiceWaveformMaxSamples。
@property (nonatomic, strong) NSMutableData *samples;
@property (nonatomic, assign, readwrite) BOOL recording;
@property (nonatomic, assign, readwrite) BOOL paused;
@property (nonatomic, assign) BOOL sessionActive;
@property (nonatomic, assign) int64_t pausedAtMillis; ///< 暂停时刻（用于 resume 时把停止的时长补回 startedAtMillis）
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
    }
    return self;
}

- (void)start {
    if (self.recording) { return; }
    [self.samples setLength:0];
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
    // 存到 tmp/voice/<uuid>.m4a（发送成功或取消后清理；App 杀死会随 tmp 一并清）。
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"voice"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *file = [NSString stringWithFormat:@"%@.m4a", NSUUID.UUID.UUIDString];
    self.fileURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:file]];

    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatMPEG4AAC),
        AVSampleRateKey: @16000.0,
        AVNumberOfChannelsKey: @1,
        AVEncoderAudioQualityKey: @(AVAudioQualityMedium),
        AVEncoderBitRateKey: @24000, // 24kbps：5min ≈ 0.9MB，符合 voice 16MB 兜底上限
    };
    NSError *recErr = nil;
    self.recorder = [[AVAudioRecorder alloc] initWithURL:self.fileURL settings:settings error:&recErr];
    if (!self.recorder || recErr) {
        [self finishWithReason:IMVoiceRecorderStopReasonError durationMillis:0];
        return;
    }
    self.recorder.delegate = self;
    self.recorder.meteringEnabled = YES;
    if (![self.recorder recordForDuration:(NSTimeInterval)(IMVoiceMaxDurationMillis / 1000)]) {
        [self finishWithReason:IMVoiceRecorderStopReasonError durationMillis:0];
        return;
    }
    self.startedAtMillis = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
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
    [self.recorder stop];
    self.recording = NO;
    self.paused = NO;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    if (dur < IMVoiceShortRecordThresholdMillis) {
        [self deleteTempFile];
        [self finishWithReason:IMVoiceRecorderStopReasonTooShort durationMillis:dur];
        return;
    }
    [self finishWithReason:IMVoiceRecorderStopReasonUserSend durationMillis:dur];
}

- (void)cancel {
    if (!self.recording && !self.paused) { return; }
    [self.recorder stop];
    self.recording = NO;
    self.paused = NO;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    [self deleteTempFile];
    [self finishWithReason:IMVoiceRecorderStopReasonUserCancel durationMillis:0];
}

#pragma mark - Pause / Resume（锁定态 P1）

- (void)pause {
    if (!self.recording || self.paused) { return; }
    [self.recorder pause];
    self.paused = YES;
    self.pausedAtMillis = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
}

- (void)resume {
    if (!self.paused) { return; }
    // AVAudioRecorder.record 继续追加同一文件。startedAtMillis 补回暂停期间的差值——
    // 这样 elapsedMillis 计算仍是"已录音的实际时长"（跳过暂停）。
    int64_t nowMs = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    int64_t pauseDur = MAX((int64_t)0, nowMs - self.pausedAtMillis);
    self.startedAtMillis += pauseDur;
    self.paused = NO;
    if (![self.recorder record]) {
        // 恢复失败 → 直接以已录时长发送/丢弃（走 finish 分支）。
        int64_t dur = [self elapsedMillis];
        [self finishWithReason:(dur >= IMVoiceShortRecordThresholdMillis)
                                 ? IMVoiceRecorderStopReasonUserSend
                                 : IMVoiceRecorderStopReasonTooShort
              durationMillis:dur];
        return;
    }
    // 恢复采样定时器
    __weak typeof(self) weakSelf = self;
    self.sampleTimer = [NSTimer scheduledTimerWithTimeInterval:IMVoiceSampleInterval repeats:YES block:^(NSTimer *_) {
        [weakSelf onSample];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.sampleTimer forMode:NSRunLoopCommonModes];
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
    if ([self.delegate respondsToSelector:@selector(voiceRecorder:didSampleAmplitude:elapsedMillis:)]) {
        [self.delegate voiceRecorder:self didSampleAmplitude:normalized elapsedMillis:[self elapsedMillis]];
    }
}

#pragma mark - AVAudioRecorderDelegate

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    if (!self.recording) { return; }
    // 达 5min 上限自动停：走 ReachedMax 分支。
    int64_t dur = [self elapsedMillis];
    self.recording = NO;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    if (flag && dur >= IMVoiceShortRecordThresholdMillis) {
        [self finishWithReason:IMVoiceRecorderStopReasonReachedMax durationMillis:dur];
    } else {
        [self deleteTempFile];
        [self finishWithReason:IMVoiceRecorderStopReasonTooShort durationMillis:dur];
    }
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error {
    if (!self.recording) { return; }
    self.recording = NO;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    [self deleteTempFile];
    [self finishWithReason:IMVoiceRecorderStopReasonError durationMillis:[self elapsedMillis]];
}

- (void)handleInterruption:(NSNotification *)note {
    NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
    if (type.unsignedIntegerValue != AVAudioSessionInterruptionTypeBegan) { return; }
    if (!self.recording || self.paused) { return; }
    int64_t dur = [self elapsedMillis];
    if (dur < IMVoiceShortRecordThresholdMillis) {
        [self.recorder stop];
        self.recording = NO;
        [self.sampleTimer invalidate];
        self.sampleTimer = nil;
        [self deleteTempFile];
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

    NSURL *fileURL = nil;
    NSString *waveBase64 = nil;
    if (reason == IMVoiceRecorderStopReasonUserSend
        || reason == IMVoiceRecorderStopReasonReachedMax
        || reason == IMVoiceRecorderStopReasonInterrupted) {
        fileURL = self.fileURL;
        waveBase64 = [self encodedWaveform];
    }
    if ([self.delegate respondsToSelector:@selector(voiceRecorder:didStopWithReason:fileURL:waveform:duration:)]) {
        [self.delegate voiceRecorder:self didStopWithReason:reason fileURL:fileURL waveform:waveBase64 duration:dur];
    }
    self.fileURL = nil;
    self.recorder = nil;
}

- (void)deleteTempFile {
    if (self.fileURL) {
        [[NSFileManager defaultManager] removeItemAtURL:self.fileURL error:NULL];
    }
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
