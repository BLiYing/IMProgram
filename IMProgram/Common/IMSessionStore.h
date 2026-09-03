//  IMSessionStore.h
//  登录态持久化：保持登录（App 重启/崩溃后直接进主界面，不再重登）。
//
//  **2026-09-03 起不再存账号明文密码**（安全整改第 5 步）。改存后端签发的 `refresh_token`：
//  它绑定这台设备的会话（sid），因此「设备管理里注销这台」「改密码后下线其它设备」「封号」
//  三条既有通路对它都生效。存密码时这三条对"保持登录"**完全无效**——注销掉的只是会话，
//  拿着密码立刻就能重登，App 自己那套设备管理形同虚设。
//
//  仍然落 NSUserDefaults 而非 Keychain：未签名装机（CODE_SIGNING_ALLOWED=NO）下 Keychain
//  无 entitlement 会静默失败、导致保持登录不可用。所以这里换的是**凭据的性质**（可吊销、
//  作用域限本设备、不是账号密码），不是存储位置；迁 Keychain 是签名之后的另一件事。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSessionStore : NSObject

/// 登录/注册/免密登录成功后调用，落盘会话。
///
/// **不收密码**：续期凭据由 IMHTTPService 在收到登录响应时自行落盘（见 saveRefreshToken:），
/// 因为触发登录的入口不止登录页（socket 换 token、冷启动静默重登都会走到），
/// 交给调用方各自保存必然漏。
///
/// **userID 与 username 必须都存**，是两个不同的东西（服务端账号体系重构后，见
/// IMServer/docs/ACCOUNT_IDENTITY_REDESIGN.md）：
///   - userID：服务端分配的 10 位数字**内部 ID**，一切业务接口的用户参数、conv_id 推导都用它；
///   - username：用户自己起的公开句柄，**只用于重新登录**（登录接口不认内部 ID）。
/// 只存 userID 会导致冷启动静默重登失败（拿内部 ID 去登录，后端按 username 查必然找不到）。
+ (void)saveHost:(NSString *)host
          userID:(NSString *)userID
        username:(nullable NSString *)username;

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

/// 续期凭据：冷启动免密换取新 access token 用（POST /api/v1/token/refresh）。
/// 从未存过 → nil（老版本升上来、或后端未下发时即此情形，见 legacyPassword）。
+ (nullable NSString *)refreshToken;
/// 保存续期凭据；传空/nil = 删除（登录失效时要能擦掉）。
+ (void)saveRefreshToken:(nullable NSString *)token;

/// **迁移垫片**：老版本把账号明文密码存在这里。只读、且**用完即删**——
/// 冷启动时若没有 refreshToken 但有它，就用它做最后一次密码登录换回 refreshToken，
/// 好处是老安装升级后不必被迫重新登录一次。
/// 可以删除本方法的条件：不再需要照顾从 2026-09-03 之前版本升级上来的安装。
+ (nullable NSString *)legacyPassword;
/// 擦掉迁移垫片里的明文密码（换到 refreshToken 之后立即调用）。
+ (void)clearLegacyPassword;

/// 退出登录 / 鉴权失效时清除（userID / username / refreshToken / 遗留明文密码；host 与 scheme 保留）。
+ (void)clear;

@end

NS_ASSUME_NONNULL_END
