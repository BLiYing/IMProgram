//  IMChatPresence.h
//  「用户此刻是否正看着某个会话」的进程内单一来源，供 IMAlertDecision 的 ctx.viewingConv 使用
//  （NOTIFICATIONS_DESIGN §3.1：移动端 viewingConv = App 前台且在该会话页）。
//
//  故意独立成 Common 小类而不是让 Network 层直接 import IMChatViewController：
//  Network → Modules/Chat 会反转既有分层（ARCHITECTURE.md：VC 不写业务逻辑、Network 不认识 UI），
//  这里换成 Modules/Chat → Common（正常方向）+ Network → Common（同样正常）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 「正在看的会话」变化时广播（object=nil，userInfo[IMChatPresenceConvIDKey]=新的 convID，可能为 nil）。
/// 供应用内横幅（Common/IMInAppBannerView）订阅：横幅展示的会话一旦被打开（不论是否点了横幅本身），
/// 立即收起（NOTIFICATIONS_P1_DESIGN §1.2「进入该会话 → 若横幅显示的正是当前打开的会话，立即收起」）。
extern NSNotificationName const IMChatPresenceDidChangeNotification;
extern NSString * const IMChatPresenceConvIDKey;

@interface IMChatPresence : NSObject

/// 聊天页出现在屏幕上时调用（viewDidAppear）。
+ (void)noteViewingConvID:(NSString *)convID;

/// 聊天页即将离开时调用（viewWillDisappear）。只在「当前记录的正是这个会话」时才清空——
/// push/pop 转场期间新旧页的生命周期回调会交叉，避免后触发的旧页 disappear 把刚设好的新页覆盖掉。
+ (void)clearViewingConvIDIfCurrent:(NSString *)convID;

/// 当前正在看的会话 id；没有聊天页在前台时为 nil。
+ (nullable NSString *)currentViewingConvID;

@end

NS_ASSUME_NONNULL_END
