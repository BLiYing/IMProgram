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
/// userInfo: @"messageID", @"convID", @"status" @(IMVoiceTranscribeStatus),
///   Done → @"text"（转写内容）；Unavailable → @"errorMessage"（给用户看的中文）。
///   两个字段刻意分开——共用一个 text 曾把「转文字暂未开启」塞进转写面板，下面还挂着
///   「结果可能不完全准确」的尾行；且将来「复制转写文本」菜单会把错误文案一起复制走。

@interface IMVoiceTranscriber : NSObject

+ (instancetype)sharedTranscriber;

/// 本地是否已有缓存的转写文本。缓存 key = **音频路径**（与服务端按 content 去重同口径：
/// 同一条语音转发多次、被收藏，指向同一个音频对象，只该有一份文本）。
- (nullable NSString *)cachedTextForContent:(NSString *)content;

/// 这条**现在该显示什么**：折叠优先于缓存，返回 nil = 面板收起。
/// 「折叠 ? nil : 缓存」这条规则的唯一实现——cell 复用、长按菜单标题两处都从这里取，
/// 各自手拼过一次就会漂移成"取消过的又冒出来"（2026-08-26 实测过的那个 bug）。
- (nullable NSString *)visibleTextForMessageID:(NSString *)mid content:(NSString *)content;

/// 发起转写。命中本地缓存直接回 Done；否则走 REST，结果经通知推送。
/// convID/convSeq 是消息坐标；content 仅用于本地缓存 key，**不发给服务端**。
/// token 内部取（IMHTTPService.currentToken），不由调用方传——它只有"未登录"一种分支。
- (void)transcribeConvID:(NSString *)convID
                 convSeq:(int64_t)convSeq
                 content:(NSString *)content
               messageID:(NSString *)messageID;

/// 收到 WS voice_transcript 帧时由 socket 观察者转交，落本地缓存并广播。
- (void)applyRemoteStatus:(NSString *)status
                     text:(nullable NSString *)text
                  content:(NSString *)content
                   convID:(NSString *)convID
                messageID:(NSString *)messageID;

/// 查询当前状态（内部用于「已入队就别再发一遍」的去重；测试据此断言缓存命中即 Done）。
- (IMVoiceTranscribeStatus)statusForMessageID:(NSString *)mid;

/// 折叠某条的转写面板（长按菜单「取消转文字」）。
///
/// **只清本地展开状态，不删服务端结果**——服务端缓存是会话共享的，
/// 一个人"取消"不该把别人也能看到的结果删掉。下次再点「转文字」会秒出（命中缓存）。
///
/// 折叠名单**落 NSUserDefaults**：转写文本是永久缓存，折叠状态若只在内存，
/// 杀 App 重进会话就会被缓存重新展开（2026-08-26 实测）。
- (void)collapseMessageID:(NSString *)mid;

/// 取消折叠（缓存命中时点「转文字」= 只需重新展开，不必再跑一遍整套 transcribe）。
- (void)expandMessageID:(NSString *)mid;

/// 该条是否被本地折叠过。**展示逻辑请用 visibleTextForMessageID:content:**，别自己拼
/// 「折叠 ? nil : 缓存」；这里公开只为回归测试能直接断言折叠名单的跨启动持久化。
- (BOOL)isCollapsedMessageID:(NSString *)mid;

@end

NS_ASSUME_NONNULL_END
