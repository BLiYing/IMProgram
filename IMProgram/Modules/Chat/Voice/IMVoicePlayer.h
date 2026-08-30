//
//  IMVoicePlayer.h
//  语音播放器（voice P0）：单例，一次只播一条；跟踪本机"已播过"红点集合（不跨端，见设计文档 §7）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const IMVoicePlayerDidChangeStateNotification;
extern NSNotificationName const IMVoicePlayerDidMarkPlayedNotification;
/// 一条语音**自然播完**（≠ 主动 stop）时广播。接力连播据此触发下一条。
/// userInfo: @"messageID"（刚播完的那条）, @"convID"
extern NSNotificationName const IMVoicePlayerDidFinishNotification;
/// userInfo:
///   @"messageID"     — 触发变更的消息 clientMsgID/serverMsgID（IMVoicePlayerPlayableIDForMessage）
///   @"convID"        — 所在会话
///   @"state"         — @(IMVoicePlayerState)（仅 DidChangeState 有）
///   @"progress"      — @(double, 0..1)  播放进度（仅 playing/paused 有）

typedef NS_ENUM(NSInteger, IMVoicePlayerState) {
    IMVoicePlayerStateIdle = 0,   ///< 未播放该条
    IMVoicePlayerStatePlaying,    ///< 正在播放该条
    IMVoicePlayerStatePaused,     ///< 播放中被暂停（气泡显示中间位置）
};

/// 标识一条语音消息在本机的稳定 key（优先 serverMsgID，回退 clientMsgID）。
@class IMMessageModel;
extern NSString *_Nullable IMVoicePlayerPlayableIDForMessage(IMMessageModel *m);

/// 本地音频文件能否交给 `AVAudioPlayer` 播；顺带回一个探测到的时长（毫秒，探不到给 0，可传 NULL 不要）。
///
/// **这不是可选的健壮性点缀**：`AVAudioPlayer` 用「总帧数 ÷ 每包帧数」算时长与播放位点，
/// 遇到 `framesPerPacket == 0` 的流会在 AVFAudio 内部**除零**（EXC_ARITHMETIC / SIGFPE），
/// `@try` 拦不住、整个 App 当场没。真实案例（2026-08-30）：Chrome 录的 **MP4/Opus**
/// （`audio/mp4` 容器里塞 Opus）三个 packet 字段全 0，iOS 也解不了 Opus，点开即崩。
/// 所以任何"拿到本地文件就播"的路径都必须先过这一关。
extern BOOL IMVoiceFileIsPlayable(NSURL *_Nullable fileURL, int64_t *_Nullable outDurationMillis);

@interface IMVoicePlayer : NSObject

+ (instancetype)sharedPlayer;

/// 播放/暂停切换。fileURL 为本地已下载音频；缺失时先下再播（P0 简化：语音恒自动下载，caller 传远程 URL 由 caller 先下）。
- (void)togglePlayback:(IMMessageModel *)message localFileURL:(NSURL *)localFileURL;

/// 确保音频在本地后再播放/暂停切换：缓存命中直接 toggle；未缓存先直连下载（voice <1MB）。
/// completion 主线程回调：nil=已切换；非 nil=失败（caller 负责提示，勿吞错——CODING_STYLE §5）。
/// 聊天页/详情页/收藏页共用入口（曾三处逐字重复且语义分叉：吞错/丢红点/weak-model 竞态，2026-08-26 收口）。
- (void)toggleEnsuringLocal:(IMMessageModel *)message
                       host:(nullable NSString *)host
                 completion:(void (^_Nullable)(NSError *_Nullable error))completion;

/// 显式暂停/停止。
- (void)stop;

/// 查询某条消息当前状态（未在播放/暂停的返回 Idle）。
- (IMVoicePlayerState)stateForMessageID:(NSString *)messageID;

/// 查询该条播放进度（0..1）；未在播的返回 0。
- (double)progressForMessageID:(NSString *)messageID;

/// 该条是否已在本机播过（红点消失判据；per-uid + per-conv 持久化到 NSUserDefaults）。
- (BOOL)hasPlayed:(NSString *)messageID inConv:(NSString *)convID owner:(NSString *)ownerUID;

/// 手动标记为已播（P0：进入播放态即调用；也可由 UI 长按标记）。
- (void)markPlayed:(NSString *)messageID inConv:(NSString *)convID owner:(NSString *)ownerUID;

/// 拖拽 scrub：把当前播放位点跳到 progress（0..1）。仅在该 messageID 正在播/暂停时生效。
- (void)seek:(double)progress forMessageID:(NSString *)messageID;

/// 会话级倍速（1.0 / 1.5 / 2.0；per convID）。设置立刻应用到当前播放器。
- (float)rateForConvID:(nullable NSString *)convID;
- (void)setRate:(float)rate forConvID:(nullable NSString *)convID;

@end

NS_ASSUME_NONNULL_END
