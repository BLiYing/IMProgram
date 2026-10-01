//  IMPushSender.h
//  通知里显示发送人头像（M5，PUSH_M5_DESIGN §3.6）：App 与通知扩展（IMNotificationService）**共用**的部分。
//
//  · App 侧：登录 / 改服务器地址时把「协议 + 主机」写进 App Group，扩展据此把相对头像 URL 补成绝对地址
//    （扩展是独立进程，读不到 App 的 NSUserDefaults）。
//  · 扩展侧：从推送载荷里解出发送人资料，算出要下载的头像地址。
//
//  本文件只依赖 Foundation（扩展不链接 Pods，用不了 IMLog / IMServerEndpoint），纯函数部分有单测。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// App 与扩展共用的 App Group。改它要同时改两边的 .entitlements。
FOUNDATION_EXPORT NSString *const IMAppGroupID;

/// App 侧：记下当前服务器的协议与主机（`http` / `192.168.1.12:8080`），供通知扩展补全头像地址。
/// 任一为空则不写（保留上次的值）。App Group 不可用（未签名装机）时静默失败——扩展退回不带头像的通知。
FOUNDATION_EXPORT void IMPushSharedSaveServer(NSString *_Nullable scheme, NSString *_Nullable host);

/// 纯函数：把载荷里的相对头像路径补成绝对 URL。只认 `/avatars/` 开头、不含 `..` 的路径，
/// 绝对 URL 一律拒绝——扩展只从自家服务器取头像，不按推送内容去拉任意地址。
FOUNDATION_EXPORT NSURL *_Nullable IMPushAvatarURL(NSString *_Nullable path, NSString *_Nullable scheme,
                                                   NSString *_Nullable host);

/// 扩展侧：按 App Group 里记下的服务器补全头像 URL（见上）。
FOUNDATION_EXPORT NSURL *_Nullable IMPushSharedAvatarURL(NSString *_Nullable path);

/// 推送载荷里的发送人资料（服务端 `internal/push` 的 SenderInfo，PROTOCOL §6.14）。
@interface IMPushSender : NSObject
@property (nonatomic, copy, readonly) NSString *convID;
@property (nonatomic, copy, readonly) NSString *senderID;
@property (nonatomic, copy, readonly) NSString *senderName;
@property (nonatomic, copy, readonly, nullable) NSString *avatarPath;
@property (nonatomic, copy, readonly, nullable) NSString *groupAvatarPath;
/// 群聊：去掉「发送人: 」前缀的正文（通信通知把发送人单独显示）；私聊为 nil。
@property (nonatomic, copy, readonly, nullable) NSString *bareBody;
/// 群聊（conv_id 不是 `u_` 开头的单聊）。群名取通知标题。
@property (nonatomic, readonly) BOOL isGroup;

/// 解不出（没有 conv_id / sender_id，比如已读清通知、老服务端）返回 nil——扩展原样展示。
+ (nullable instancetype)senderFromUserInfo:(nullable NSDictionary *)userInfo;
@end

NS_ASSUME_NONNULL_END
