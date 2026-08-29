//  IMAccountIdentity.h
//  账号身份的全端共享常量与判定（对应后端 docs/ACCOUNT_IDENTITY_REDESIGN.md）。
//
//  三个概念别混：
//    - **内部 ID**（`user_id`）：服务端分配的 10 位随机数字，用户不可见不可改。
//      一切业务接口参数、conv_id 推导、消息 sender 都用它。
//    - **username**：用户自己起的公开句柄（`^[a-z0-9_]{5,32}$`），可改，**只用于登录**与 UI 上的 `@xxx`。
//    - **nickname**：显示名，必填，任意字符。全端显示名回退链**止于它**。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 系统通知账号的内部 ID（Telegram 777000 同款取值）。
///
/// ⚠️ 别与消息类型 `content_type == "system"` 混淆——两者过去字面相同（都是 "system"），
/// 账号侧已改为 "777000"，消息类型侧**保持不变**。凡是判断"这条会话/这个人是不是系统账号"
/// 一律用本常量，不要再写字面量。
FOUNDATION_EXPORT NSString * const IMSystemUserID;

/// 判定某 uid 是否系统账号。
static inline BOOL IMIsSystemUserID(NSString *_Nullable uid) {
    return uid.length > 0 && [uid isEqualToString:IMSystemUserID];
}

/// 显示名兜底的**唯一口径**：昵称 → @username → 「未命名用户」。
///
/// **绝不回退到内部 ID**——那是 10 位随机数字，对用户毫无意义，露在界面上就是 bug
/// （见 IMServer/docs/ACCOUNT_IDENTITY_REDESIGN.md §5.2）。nickname 在服务端是必填字段，
/// 所以本函数的后两级只是防御性兜底（脏数据/老数据），正常不会走到。
/// username 多数调用点拿不到（好友/成员列表刻意不下发它），传 nil 即可。
FOUNDATION_EXPORT NSString *IMDisplayName(NSString *_Nullable nickname, NSString *_Nullable username);

NS_ASSUME_NONNULL_END
