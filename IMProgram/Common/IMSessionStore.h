//  IMSessionStore.h
//  登录态持久化：保持登录（App 重启/崩溃后直接进主界面，不再重登）。
//  host/userID/password 存 NSUserDefaults（开发骨架；未签名装机 Keychain 无 entitlement 会失效，生产签名后再迁 Keychain）。
//  启动时用这三者静默重登拿新 token（socket 重连也需 password），避免仅存 token 过期后失效。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSessionStore : NSObject

/// 登录/注册/免密登录成功后调用，落盘会话（password 可为空串=免密登录）。
+ (void)saveHost:(NSString *)host userID:(NSString *)userID password:(nullable NSString *)password;

/// 是否有可恢复的会话（有已保存的 userID）。
+ (BOOL)hasSession;

+ (nullable NSString *)host;
+ (nullable NSString *)userID;
+ (nullable NSString *)password;

/// 退出登录 / 鉴权失效时清除（password 从 Keychain 删除）。
+ (void)clear;

@end

NS_ASSUME_NONNULL_END
