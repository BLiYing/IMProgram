//
//  IMVoicePlayer.h
//  语音播放器（voice P0）：单例，一次只播一条；跟踪本机"已播过"红点集合（不跨端，见设计文档 §7）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const IMVoicePlayerDidChangeStateNotification;
extern NSNotificationName const IMVoicePlayerDidMarkPlayedNotification;
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

@interface IMVoicePlayer : NSObject

+ (instancetype)sharedPlayer;

/// 播放/暂停切换。fileURL 为本地已下载音频；缺失时先下再播（P0 简化：语音恒自动下载，caller 传远程 URL 由 caller 先下）。
- (void)togglePlayback:(IMMessageModel *)message localFileURL:(NSURL *)localFileURL;

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

@end

NS_ASSUME_NONNULL_END
