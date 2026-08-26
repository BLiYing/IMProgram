//
//  IMVoiceMiniPlayerView.h
//  迷你语音播放器（▶ + 波形进度 + 时长）——**不带气泡背景**，供资料页语音 tab、收藏语音行三处复用。
//
//  与 IMVoiceBubbleCell 内部的三件套结构一致（播放键/波形/时长），只是抽成独立 UIView，
//  供非 tableView cell 的容器嵌入使用；订阅 IMVoicePlayer 通知同步播放态/进度，
//  点 ▶ 触发 onPlayTap（宿主决定走 IMVoicePlayer.toggleEnsuringLocal:host:completion:）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class IMMessageModel;

@interface IMVoiceMiniPlayerView : UIView

/// 用消息数据配置。同一实例可复用配不同 message；播放态由 IMVoicePlayer 广播自动同步。
/// 布局：▶ 居左 · 右侧 vertical stack（波形 + 时长·时间·勾一行）——用户 2026-08-27 拍板"时长在波形下方"。
- (void)configureWithMessage:(IMMessageModel *)message;

/// mine + 单聊已读位点（可选）——语音气泡右下角显示 ✓/✓✓。资料页/收藏页对方语音传 mine=NO/peerReadSeq=0。
- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                 peerReadSeq:(int64_t)peerReadSeq
              isGroupContext:(BOOL)isGroupContext;

/// 用户点 ▶ / 波形——宿主拿到后走 IMVoicePlayer.toggleEnsuringLocal:host:completion:。
@property (nonatomic, copy, nullable) void (^onPlayTap)(void);

@end

NS_ASSUME_NONNULL_END
