//  IMSessionStore.h
//  登录态持久化：保持登录（App 重启/崩溃后直接进主界面，不再重登）。
//  host/userID/password 存 NSUserDefaults（开发骨架；未签名装机 Keychain 无 entitlement 会失效，生产签名后再迁 Keychain）。
//  启动时用这三者静默重登拿新 token（socket 重连也需 password），避免仅存 token 过期后失效。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSessionStore : NSObject

/// 登录/注册/免密登录成功后调用，落盘会话（password 可为空串=免密登录）。
///
/// **userID 与 username 必须都存**，是两个不同的东西（服务端账号体系重构后，见
/// IMServer/docs/ACCOUNT_IDENTITY_REDESIGN.md）：
///   - userID：服务端分配的 10 位数字**内部 ID**，一切业务接口的用户参数、conv_id 推导都用它；
///   - username：用户自己起的公开句柄，**只用于重新登录**（登录接口不认内部 ID）。
/// 只存 userID 会导致冷启动静默重登失败（拿内部 ID 去登录，后端按 username 查必然找不到）。
+ (void)saveHost:(NSString *)host
          userID:(NSString *)userID
        username:(nullable NSString *)username
        password:(nullable NSString *)password;

/// 是否有可恢复的会话（有已保存的 userID）。
+ (BOOL)hasSession;

+ (nullable NSString *)host;
/// 上次使用的协议（`http` / `https`）。冷启动时用它恢复 IMServerEndpoint；
/// 从未存过 → nil，调用方按默认 http 处理（老版本升上来即此情形）。
+ (nullable NSString *)scheme;
/// 单独保存协议：saveHost:... 覆盖的是"这次登录用的账号"，而协议是"连哪台服务器"的一部分，
/// 登出后仍应保留（与 host 同待遇，下次登录默认回填）。
+ (void)saveScheme:(nullable NSString *)scheme;
+ (nullable NSString *)userID;
/// 登录凭据（公开句柄）。冷启动静默重登必须用它，不能用 userID。
+ (nullable NSString *)username;
+ (nullable NSString *)password;

/// 退出登录 / 鉴权失效时清除（password 从 Keychain 删除）。
+ (void)clear;

@end

NS_ASSUME_NONNULL_END
