//  IMMediaExpiryRegistry.h
//  「曾可用、被服务端清理」媒体的失效登记表（对齐 Web im-web 的 expiredSet + docs/design/sketches/MEDIA_EXPIRED_UX_SKETCH.html）。
//
//  三条**被动展示**路径（曾可用图/视频气泡 IMImageCell·IMAlbumCell / 会话媒体库宫格 IMConversationMediaViewController /
//  大图查看器 IMMediaViewerViewController）此前对 404 一律留空白 —— 与"加载中"分不清。本表把命中 404/410 的 URL
//  统一登记为**永久失效**：命中即画失效占位、不再回源（掐 404 风暴）。
//
//  与「下载协调器」路径（IMMediaDownloadCoordinator，用户主动点下载才判失效）互补：本表管的是**不经协调器的被动展示**。
//  说明：本表为**进程内内存态**（与协调器 `_states` 同philosophy）；原件下载后本就落沙盒磁盘持久，故非删除媒体重启照显，
//  失效标记不持久化只会在重启后按需重新复验一次——不会像 Web 那样"刷新变透明"。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 某 URL 刚被登记为失效时广播（userInfo[@"url"] = 失效的 fullURL），可见 cell/VC 据此就地刷新为失效占位。
extern NSString * const IMMediaExpiryDidChangeNotification;

@interface IMMediaExpiryRegistry : NSObject

+ (instancetype)shared;

/// 该 URL 是否已知永久失效（不发起网络）。
- (BOOL)isExpiredURL:(nullable NSString *)url;

/// 直接登记失效（幂等）：新登记会广播 IMMediaExpiryDidChangeNotification。
- (void)markExpiredURL:(nullable NSString *)url;

/// 被动展示原件加载失败时的**失效复验**：`<img>/<video>` onError 分不清「404 已清理」与「解码/瞬时抖动」，
/// 这里发一次轻量 ranged GET（`Range: bytes=0-0`，服务端 /uploads 支持 Range）读状态码——404/410 才登记失效。
/// 已知失效 / 非 http(s) → 立即回调、不重复联网。completion 恒在**主线程**回调。
- (void)verifyExpiredForURL:(nullable NSString *)url completion:(void (^)(BOOL expired))completion;

/// 清空（设置页「清除缓存」/ 退出登录）。
- (void)clear;

@end

NS_ASSUME_NONNULL_END
