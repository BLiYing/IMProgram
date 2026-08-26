//
//  IMVoiceTranscriber.h
//  语音转文字（**服务端识别**，见 IMServer docs/VOICE_TRANSCRIBE_DESIGN.md）：
//    - 收方长按气泡 →「转文字」→ POST /api/v1/voice/transcripts（只传消息坐标）
//    - 命中服务端缓存 → 立即回文本；未命中 → 回 pending，结果经 WS voice_transcript 帧到达
//    - 本地按**音频路径**缓存一份（与服务端同口径），避免重复请求；再次展开零延迟
//
//  2026-08-26 从端上 SFSpeechRecognizer 改为服务端识别：iOS 本地语言包长期不可控，
//  Web 端原理上做不到（浏览器 SpeechRecognition 只吃实时麦克风流），端上方案已证伪。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMVoiceTranscribeStatus) {
    IMVoiceTranscribeStatusIdle = 0,
    IMVoiceTranscribeStatusRecognizing, ///< 已入队，等服务端推结果
    IMVoiceTranscribeStatusDone,
    IMVoiceTranscribeStatusUnavailable, ///< 未启用 / 识别失败 / 队列满 / 限流（文案由 errorText 给）
};

extern NSNotificationName const IMVoiceTranscriberDidChangeNotification;
/// userInfo: @"messageID", @"convID", @"status" @(IMVoiceTranscribeStatus), @"text" (可空)

@interface IMVoiceTranscriber : NSObject

+ (instancetype)sharedTranscriber;

/// 把服务端业务错误码映射成给用户看的文案（CONVENTIONS §2.3：端按 code 做映射，不展示服务端原文）。
+ (NSString *)messageForErrorCode:(NSInteger)code fallback:(nullable NSString *)fallback;

/// 本地是否已有缓存的转写文本。缓存 key = **音频路径**（与服务端按 content 去重同口径：
/// 同一条语音转发多次、被收藏，指向同一个音频对象，只该有一份文本）。
- (nullable NSString *)cachedTextForContent:(NSString *)content;

/// 发起转写。命中本地缓存直接回 Done；否则走 REST，结果经通知推送。
/// convID/convSeq 是消息坐标；content 仅用于本地缓存 key，**不发给服务端**。
- (void)transcribeConvID:(NSString *)convID
                 convSeq:(int64_t)convSeq
                 content:(NSString *)content
              messageID:(NSString *)messageID
                   token:(NSString *)token;

/// 收到 WS voice_transcript 帧时由 socket 观察者转交，落本地缓存并广播。
- (void)applyRemoteStatus:(NSString *)status
                     text:(nullable NSString *)text
                  content:(NSString *)content
                   convID:(NSString *)convID
                messageID:(NSString *)messageID;

/// 查询当前状态（cell 复用时决定是否显 loading）。
- (IMVoiceTranscribeStatus)statusForMessageID:(NSString *)mid;

/// 折叠某条的转写面板（长按菜单「取消转文字」）。
///
/// **只清本地展开状态，不删服务端结果**——服务端缓存是会话共享的，
/// 一个人"取消"不该把别人也能看到的结果删掉。下次再点「转文字」会秒出（命中缓存）。
- (void)collapseMessageID:(NSString *)mid;

/// 该条是否被本地折叠过（+Menu.m 据此决定菜单显「转文字」还是「取消转文字」）。
- (BOOL)isCollapsedMessageID:(NSString *)mid;

@end

NS_ASSUME_NONNULL_END
