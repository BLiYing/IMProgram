//
//  IMVoiceRecorder.h
//  语音录制器（voice P0）：AVAudioRecorder 包装，采样振幅生成 waveform 指纹。
//
//  设计参见 IMServer/docs/VOICE_MESSAGE_DESIGN.md §5：
//    - 录制格式 AAC-LC / 单声道 / 16kHz / 24–32kbps（跨端一致，iOS 原生 .m4a）
//    - 时长上限 5min（超出自动停录并进入待发送态）；<0.6s 提示"说话时间太短"并丢弃
//    - 采样：录制过程按 10Hz 采 averagePower，累积到 waveform 数组（原始字节 0~100）
//    - 中断（来电/切后台）→ 委托 didInterrupt 回调；上层转入锁定暂停态
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMVoiceRecorderStopReason) {
    IMVoiceRecorderStopReasonUserSend = 0,     ///< 用户主动松手/点发送
    IMVoiceRecorderStopReasonUserCancel,       ///< 用户左滑取消（不落草稿）
    IMVoiceRecorderStopReasonTooShort,         ///< <0.6s 松手（提示后丢弃）
    IMVoiceRecorderStopReasonReachedMax,       ///< 达 5min 上限自动停录
    IMVoiceRecorderStopReasonInterrupted,      ///< 系统中断（来电/切后台）；上层可转锁定暂停态
    IMVoiceRecorderStopReasonError,            ///< 底层错误（权限被拒等）
};

@class IMVoiceRecorder;

@protocol IMVoiceRecorderDelegate <NSObject>
@optional
/// 权限检查完毕、录制已开始（每 100ms 一次 tick）。
- (void)voiceRecorderDidStart:(IMVoiceRecorder *)recorder;
/// 振幅（0~1）与已录时长（ms）持续回调，供 HUD/大圆钮呼吸环。UI 线程。
- (void)voiceRecorder:(IMVoiceRecorder *)recorder didSampleAmplitude:(float)amplitude elapsedMillis:(int64_t)elapsedMillis;
/// 录制结束（无论何种原因）。fileURL 仅在 UserSend/ReachedMax/Interrupted 时非空；其余分支已删临时文件。
/// waveform 是 base64 后的振幅指纹（<=160 rune，符合服务端 hub_voice.go 上限），空=录制过短/失败。
- (void)voiceRecorder:(IMVoiceRecorder *)recorder didStopWithReason:(IMVoiceRecorderStopReason)reason
              fileURL:(nullable NSURL *)fileURL
            waveform:(nullable NSString *)waveformBase64
             duration:(int64_t)durationMillis;
/// 系统中断（来电/切后台）且已录 ≥0.6s：recorder 已自动 pause（文件保留）。
/// 上层应转入锁定暂停态（设计 §5.4：回到会话时锁定行还在，可 发送/删除/继续）。<0.6s 的中断仍走 didStop tooShort。
- (void)voiceRecorderWasInterrupted:(IMVoiceRecorder *)recorder;
@end

@interface IMVoiceRecorder : NSObject

@property (nonatomic, weak, nullable) id<IMVoiceRecorderDelegate> delegate;
/// 是否正在录制（未暂停）。
@property (nonatomic, readonly) BOOL recording;
/// 是否已达最大时长（4:50 起 UI 应显倒数）。
@property (nonatomic, readonly) int64_t maxDurationMillis;
/// 已录音时长（ms，不含暂停区间）。供锁定行「删除 >10s 二次确认」等 UI 判定。
@property (nonatomic, readonly) int64_t elapsedMillis;

/// 检查/请求麦克风权限；未授权时立即回调 NO，UI 应引导用户去设置。
+ (void)requestMicrophonePermission:(void (^)(BOOL granted))completion;

/// 开始录制。若权限被拒或 AVAudioSession 配置失败，同步 didStop error。
- (void)start;

/// 用户主动停并"发送"。
- (void)stopAndSend;

/// 用户左滑取消：删临时文件、waveform 置空。
- (void)cancel;

/// 锁定态暂停/继续（P1）：AVAudioRecorder.pause / .record 复用同一文件；
/// paused 时不再累计 elapsed。
- (void)pause;
- (void)resume;

/// 当前是否处于暂停态（recorder 存在但 !isRecording）。
@property (nonatomic, readonly) BOOL paused;

/// 供锁定态 UI 查询：当前波形指纹（0~1 归一化，最长 60 帧）。用于锁定行的迷你波形展示。
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *currentAmplitudes;

@end

NS_ASSUME_NONNULL_END
