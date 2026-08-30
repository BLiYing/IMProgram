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
/// peerReadSeq：单聊对端已读位点（群聊上层传 0 即可，语音气泡群聊只显 ✓ 不显 ✓✓，与文本/图片一致）。
- (void)configureWithMessage:(IMMessageModel *)message
                        mine:(BOOL)mine
                   dayHeader:(nullable NSString *)dayHeader
          showsUnreadDivider:(BOOL)showsDivider
                  senderName:(nullable NSString *)senderName
                  senderRole:(IMGroupRole)senderRole
                    hasPlayed:(BOOL)hasPlayed
                 peerReadSeq:(int64_t)peerReadSeq
              isGroupContext:(BOOL)isGroupContext;

/// 用户点播放/暂停触发（本地 URL 已由宿主自动下载好；voice 恒自动下载）。
@property (nonatomic, copy, nullable) void (^onPlayTap)(void);

/// 发送失败红❗（§5.5：不重录）：视图与 `onRetryTap` 均继承自 IMMessageCell，与其它消息 cell 同一款。

/// 显示转写文本（P1）：宿主收到长按菜单「转文字」→ 触发识别 →
/// 通过 IMVoiceTranscriberDidChangeNotification 回来后调本方法把当前文本展开在气泡下方。
/// text 空 → 收起面板；status=Recognizing 时可传 nil 与 loading=YES 组合显"识别中…"。
- (void)applyTranscriptText:(nullable NSString *)text loading:(BOOL)loading;

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
