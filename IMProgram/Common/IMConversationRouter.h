//  IMConversationRouter.h
//  「打开某个会话」的统一入口，供 Common/Network 层调用而不反向 import Modules/Chat
//  （与 IMChatPresence.h 顶部注释同一思路：Network → Modules/Chat 会反转既有分层，
//  换成 Modules/Chat → Common 注册 opener + Common/Network → Common 调用，两个方向都正常）。
//
//  由 IMChatViewController 在 +load 里注册实现（Modules/Chat → Common，正常方向）；
//  应用内横幅（Common/IMInAppBannerView）点击时经这里跳转，不直接 import IMChatViewController.h。

#import <Foundation/Foundation.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

@interface IMConversationRouter : NSObject

/// 打开会话的实现（由 Modules/Chat 注册）：返回是否真的导航成功了（比如这一刻还没有可用的
/// 导航控制器——冷启动早期、窗口还没建好——就该报 NO，让调用方知道"没生效"而不是当成已完成）。
/// 未注册时 openConversation:… 静默返回 NO，不崩溃。
@property (class, nonatomic, copy, nullable) BOOL (^opener)(NSString *host, NSString *userID, IMConversation *conversation);

/// 在当前可见的顶层控制器上打开这个会话（与点会话列表行同一路径）。返回是否真的打开了——
/// **调用方若要据此决定"要不要重试"，必须检查返回值，不能假定调用即生效**
/// （IMPendingNotificationRoute 冷启动早期调用它就会拿到 NO，随后走已有的退避重试）。
+ (BOOL)openConversation:(IMConversation *)conversation host:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
