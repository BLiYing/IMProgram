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

/// 打开会话的实现（由 Modules/Chat 注册）；未注册时 openConversation:… 静默返回，不崩溃。
@property (class, nonatomic, copy, nullable) void (^opener)(NSString *host, NSString *userID, IMConversation *conversation);

/// 在当前可见的顶层控制器上打开这个会话（与点会话列表行同一路径）。
+ (void)openConversation:(IMConversation *)conversation host:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
