#import "IMSocketManager.h"

NS_ASSUME_NONNULL_BEGIN

/// 握手 401 之后该做什么（与 Android `ws/WakeAction.kt#unauthorizedActionFor` 同一口径）。
typedef NS_ENUM(NSInteger, IMSocketUnauthorizedAction) {
    IMSocketUnauthorizedActionRefresh = 0, ///< 让 token 缓存过期、续期一次再连
    IMSocketUnauthorizedActionRevoked,     ///< 按被踢处理：停重连、回登录页
};

/// 握手 401 → 先续期，**只有续期被服务端明确拒绝才算被踢**。
///
/// gateway 对「token 无效 / 过期」与「sid 已吊销」都回 401（正文 `unauthorized` / `session revoked`），
/// 单看 401 分不出来；续期接口会拒绝吊销的 sid，所以拿续期结果来判。
/// 2026-10-08 实测：服务端换签名密钥重启后，本端拿 10 分钟缓存里的旧 token 重连撞 401，被直接送回登录页——
/// 续期其实能成功。
///
/// 按被踢处理的两种情况：
///  · 本机没有续期凭据（`hasRefreshCredential` = NO）：续不了。此时若照常重连，换票会退回空密码 POST /login——
///    生产环境失败但不发被踢通知、无限重试；开发环境（-dev-login）直接登上，把吊销的设备「复活」（/code-review 2026-10-08）；
///  · 撞 401 的正是**续期之后开的那条连接**（`failedGeneration == refreshRetryGeneration`）：防死循环。
///    记代次而不记布尔——之后的重连 / 重新登录都会开新代次，照样能续，不必在各入口清零。
FOUNDATION_EXPORT IMSocketUnauthorizedAction IMSocketUnauthorizedActionFor(BOOL hasRefreshCredential,
                                                                          NSUInteger failedGeneration,
                                                                          NSUInteger refreshRetryGeneration);

@interface IMSocketManager (AuthRecovery)

/// 握手 401 的处理入口（仅在 queue 调用）。返回 YES = 已转去续期重连，调用方不必再做什么；
/// NO = 应按被踢处理（停重连、发 `IMSocketDidRevokeSessionNotification`）。
- (BOOL)recoverFromAuthRejection;

@end

NS_ASSUME_NONNULL_END
