//  IMPendingNotificationRoute.h
//  通知点击 → 进会话的收口（M5）：冷启动时主界面/本地数据库账号命名空间可能还没就绪，
//  先记下 conv_id，待 IMMainTabBarController 建好（每次登录/启动主界面创建后）再尝试打开
//  （PUSH_M5_DESIGN §3.2、PROTOCOL §6.14 APNs payload 的 conv_id，走与会话列表同一入口 IMConversationRouter）。

#import <Foundation/Foundation.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

/// 纯函数：从通知 userInfo 取 conv_id（缺失/非字符串/空串一律回 nil）。
/// AppDelegate 的 `didReceiveNotificationResponse:` 与单测共用同一份解析口径。
FOUNDATION_EXPORT NSString *_Nullable IMPushConvIDFromUserInfo(NSDictionary *_Nullable userInfo);

/// 纯函数：本地库里还没有这个会话时（冷启动点开陌生人/新群的第一条消息），只凭 conv_id + 通知标题
/// 拼一个「够打开聊天页」的占位会话——与从资料页「发消息」进一个没聊过的会话同理：聊天页进去后
/// 消息、头像都照常从服务端拉。单聊 `u_A_u_B` 取不是自己的那一方为对端；群聊 `g_` 前缀。
/// 解析不出（格式不认识 / 单聊里两端都不是自己）回 nil，调用方退回「等会话列表同步」。
FOUNDATION_EXPORT IMConversation *_Nullable IMPlaceholderConversationForPush(NSString *_Nullable convID,
                                                                              NSString *_Nullable selfUID,
                                                                              NSString *_Nullable title);

@interface IMPendingNotificationRoute : NSObject

+ (instancetype)shared;

/// 通知被点击时调用：记下待打开的会话 id 与通知标题（覆盖式——只关心最后一次点击）。
/// 标题 = 对方名字 / 群名（PROTOCOL §6.14），本地没有该会话时用来给占位会话起名。
- (void)setPendingConvID:(NSString *)convID title:(nullable NSString *)title;

/// 主界面就绪时调用（IMMainTabBarController `viewDidAppear:`）：若有待路由的 conv_id 尝试打开；
/// 本地库查不到该会话时直接用占位会话打开（IMPlaceholderConversationForPush）；连占位都拼不出
/// 才短暂重试几次等会话列表同步，之后放弃，不无限占着。
- (void)tryRouteWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
