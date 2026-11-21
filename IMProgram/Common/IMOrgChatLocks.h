//  IMOrgChatLocks.h
//  集团单聊的「只读」原因（TENANT_DESIGN v2 §4.2 / §4.3，交互稿 TENANT_CLIENT_UX_SKETCH I-14）。
//
//  原因由服务端按**当前**状态给出（GET /conversations 每个单聊的 peer_chat_lock），客户端只负责显示：
//   · org_left       「你们已不在同一集团」
//   · service_ended  「对方已不再为你提供服务」
//  会话列表还没刷新前的两个即时信号也记成 org_left：好友事件 org_exit（from = 对端）、发消息被拒 400120；
//  下一次会话列表以服务端为准覆盖。资料页拿到 direct_chat=true 时解除。
//  只在内存里（服务端是权威，冷启动等会话列表回来即可）；换号清空。

#import <Foundation/Foundation.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

/// 标记变化时在主线程发出（object = nil）；聊天页据此重算输入栏锁。
FOUNDATION_EXPORT NSNotificationName const IMOrgChatLocksDidChangeNotification;

FOUNDATION_EXPORT NSString * const IMOrgChatLockOrgLeft;       ///< "org_left"
FOUNDATION_EXPORT NSString * const IMOrgChatLockServiceEnded;  ///< "service_ended"

/// 纯函数：服务端原因 → 输入栏提示文案键（nil = 不锁；未知原因也不锁，老客户端遇到新原因不误锁）。
FOUNDATION_EXPORT NSString *_Nullable IMOrgChatLockTextKey(NSString *_Nullable reason);

@interface IMOrgChatLocks : NSObject

+ (instancetype)shared;

/// 当前账号对 peer 的输入栏提示文案键；nil = 不锁。主线程调用。
- (nullable NSString *)lockTextKeyForPeer:(nullable NSString *)peerID;

/// 发消息被拒 400120：标记 org_left（直到下一次会话列表）。
- (void)markOrgLeftForPeer:(nullable NSString *)peerID;

/// 资料页拿到 direct_chat=true：解除（免好友直聊恢复了）。
- (void)noteDirectChatForPeer:(nullable NSString *)peerID;

/// 用 GET /conversations 的整表覆盖列表里出现的单聊对端（服务端权威）。
- (void)ingestConversations:(NSArray<IMConversation *> *)conversations;

@end

NS_ASSUME_NONNULL_END
