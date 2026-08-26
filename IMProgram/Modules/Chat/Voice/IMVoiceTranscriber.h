//
//  IMVoiceTranscriber.h
//  语音转文字（P1，收端本地按需，见 IMServer docs/VOICE_MESSAGE_DESIGN.md §6.3）：
//    - 收方长按气泡 →「转文字」→ 本机 SFSpeechRecognizer 端上识别
//    - 结果只存本地 NSUserDefaults per uid+conv+mid（不上行、不落服务端、不跨端）
//    - 再次展开零延迟；识别不可用时降级"转文字暂不可用"
//    - 权限：NSSpeechRecognitionUsageDescription（Info.plist）+ 首次 SFSpeechRecognizer.requestAuthorization
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMVoiceTranscribeStatus) {
    IMVoiceTranscribeStatusIdle = 0,
    IMVoiceTranscribeStatusRecognizing,
    IMVoiceTranscribeStatusDone,
    IMVoiceTranscribeStatusUnavailable, ///< 无权限 / recognizer 不支持当前 locale / 引擎错误
};

extern NSNotificationName const IMVoiceTranscriberDidChangeNotification;
/// userInfo: @"messageID", @"convID", @"status" @(IMVoiceTranscribeStatus), @"text" (可空)

@interface IMVoiceTranscriber : NSObject

/// 语音识别授权是否被拒/受限（供上层判定文案是"去设置开启"还是"识别不可用"）。
+ (BOOL)isAuthorizationDeniedOrRestricted;

/// 内存缓存查询（滚动列表 configure 热路径专用，不走 NSUserDefaults 读盘）。miss 返回 nil，
/// 首次落盘时按需从 NSUserDefaults 懒加载并回填 mem cache。

+ (instancetype)sharedTranscriber;

/// 本地是否已有缓存的转写文本。缓存 key = per-uid + per-conv + per-mid。
- (nullable NSString *)cachedTextForMessageID:(NSString *)mid
                                       convID:(nullable NSString *)convID
                                        owner:(nullable NSString *)ownerUID;

/// 启动一次识别；本地已有缓存 → 直接回 status Done。识别过程通过通知推 status/text。
/// audioURL 需为已下载到本地的音频（voice 恒自动下载策略见设计文档 §7）。
- (void)transcribeMessageID:(NSString *)mid
                     convID:(nullable NSString *)convID
                      owner:(nullable NSString *)ownerUID
                   audioURL:(NSURL *)audioURL;

/// 查询当前状态（用于 cell 复用时决定是否显 loading）。
- (IMVoiceTranscribeStatus)statusForMessageID:(NSString *)mid;

@end

NS_ASSUME_NONNULL_END
