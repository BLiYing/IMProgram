//
//  IMVoiceBubbleCell.h
//  语音气泡（voice P0）：▶ 播放键 | 波形 | m:ss 时长 | ● 未播红点（仅对端消息）。
//
//  静息态只有 3 件事（不带常驻倍速/转写按钮，见 VOICE_MESSAGE_DESIGN §6.1）。
//  播放中订阅 IMVoicePlayerDidChangeStateNotification 实时刷 waveform.progress + 显剩余时间。
//

#import <UIKit/UIKit.h>
#import "IMMessageCell.h"

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMVoiceBubbleCell : IMMessageCell

/// 用消息数据配置气泡。senderName/senderRole 与其他 cell 同套群头逻辑。
- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                   dayHeader:(nullable NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider
                  senderName:(nullable NSString *)senderName
                  senderRole:(IMGroupRole)senderRole
                    hasPlayed:(BOOL)hasPlayed;

/// 用户点播放/暂停触发（本地 URL 已由宿主自动下载好；voice 恒自动下载）。
@property (nonatomic, copy, nullable) void (^onPlayTap)(void);

/// 长按气泡的目标（IMChatVC contextMenu 依赖）。
@property (nonatomic, strong, readonly) UIView *previewTargetView;

/// 群头绑定（与其他 cell 一致的调用方式）。
- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;

@end

NS_ASSUME_NONNULL_END
