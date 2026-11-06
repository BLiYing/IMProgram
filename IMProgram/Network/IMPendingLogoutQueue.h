//  IMPendingLogoutQueue.h
//  退出登录的服务端吊销：持久化待吊销的续期凭据，失败后自动重试，直到送达（LOGOUT_REVOKE_RETRY_DESIGN）。
//
//  为什么要有它：退出时吊销请求若没成功（断网 / 超时 / access token 已过期），本地凭据已清，
//  服务端会话和推送令牌却还在。iOS 的通知由系统直接展示，App 拦不住，于是这台已退出的设备会一直
//  收到带内容预览的离线通知，且再也没有办法自己补救。
//
//  存储用 Keychain，不用存在用凭据的 NSUserDefaults（IMSessionStore）：退出后这枚凭据不该留在
//  容器的明文 plist 里。IMSessionStore 不用 Keychain 是因为未签名装机时它会静默失败、连累保持登录；
//  这里不受影响——收得到推送的包一定已签名；写入失败时退回内存队列，进程活着就继续重试。
//
//  对端：im-android `sdk/session/PendingLogoutQueue.kt`。主线程使用。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 这次失败值不值得再试：网络 / 非 JSON 响应 / 限流 / 服务端内部错误才试；服务端明确拒绝（如参数错误）不试。
/// `error` 为 nil（成功）时返回 NO。纯函数，便于单测。
FOUNDATION_EXPORT BOOL IMPendingLogoutShouldRetry(NSError *_Nullable error);

/// 队列的持久化。读失败（设备尚未首次解锁等）必须返回 NO，不能当成空，否则下一次写会覆盖掉已存的凭据。
@protocol IMPendingLogoutStorage <NSObject>
- (BOOL)readData:(NSData *_Nullable *_Nonnull)data;
/// data 为 nil = 删除。
- (BOOL)writeData:(nullable NSData *)data;
@end

/// Keychain 实现：本机专用，不进备份、不随 iCloud 钥匙串同步。
@interface IMPendingLogoutKeychainStorage : NSObject <IMPendingLogoutStorage>
- (instancetype)initWithService:(NSString *)service NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

/// 发一次吊销请求。completion 回调须在主线程。
typedef void (^IMPendingLogoutSender)(NSString *refreshToken, NSURL *url, void (^completion)(NSError *_Nullable error));

@interface IMPendingLogoutQueue : NSObject

+ (instancetype)shared;

/// 测试注入用。
- (instancetype)initWithStorage:(id<IMPendingLogoutStorage>)storage
                         sender:(IMPendingLogoutSender)sender NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 补发失败后隔多久再试（App 活着时）。默认 60 秒。
@property (nonatomic, assign) NSTimeInterval retryInterval;
/// 当前时间。测试注入，用来验证过期清理。
@property (nonatomic, copy) NSDate *(^now)(void);
/// 还没吊销成功的凭据数。
@property (nonatomic, readonly) NSUInteger pendingCount;

/// App 启动时调一次：立刻补发，并在网络恢复、回前台时再试。
- (void)start;

/// 退出登录时调：先落盘再发送。**必须在清本地会话之前调**。
/// url 是发起退出时那台服务器的吊销地址，随凭据一起存：之后换了服务器地址，凭据也不会发给别的服务器。
- (void)enqueueRefreshToken:(NSString *)refreshToken url:(NSURL *)url;

/// 把所有待吊销的凭据各发一次。已有一轮在跑时只做标记，结束后再跑一轮。
- (void)flush;

@end

NS_ASSUME_NONNULL_END
