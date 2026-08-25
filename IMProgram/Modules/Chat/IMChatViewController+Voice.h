//
//  IMChatViewController+Voice.h
//  语音消息 P0 category —— 只暴露宿主要用的两个入口：安装按住手势、启动播放。
//  实现细节（recorder/HUD/上传/echo）全在 .m，不暴露。
//

#import "IMChatViewController.h"

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMChatViewController (Voice)

/// 装录音按住手势。IMChatViewController 主实现 configureCompose 完成后自动调用一次。
- (void)im_installVoicePressGesture;

/// 播放某条语音消息（DataSource 的 onPlayTap 回调调用）。fullURL = self fullMediaURL:message.content。
- (void)im_playVoiceMessage:(IMMessageModel *)message fullURL:(NSString *)fullURL;

/// 长按菜单「转文字」触发（+Menu.m 调用）。缓存命中 → 直接展开；否则先下音频再走 SFSpeechRecognizer。
- (void)im_transcribeVoiceMessage:(IMMessageModel *)message;

@end

NS_ASSUME_NONNULL_END
