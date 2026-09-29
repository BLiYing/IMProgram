//  IMInAppBannerView.h
//  应用内横幅（NOTIFICATIONS_P1_DESIGN §1.2）：App 前台时，别的会话来新消息在顶部滑入一条卡片，
//  4 秒自动收起、点击进会话、上滑收起。全局至多一条（新消息原地换内容重新计时，不叠加/不排队）。
//
//  放 Common/ 而不是 Modules/Chat：触发点在 Network 层（IMSocketManager+Alerts.m），若本类反向
//  import Modules/Chat 会颠倒既有分层（同 IMChatPresence.h 顶部注释的理由）。点击后的跳转经
//  IMConversationRouter（同样在 Common/）转发给已在 Modules/Chat 注册好 opener 的 IMChatViewController。

#import <UIKit/UIKit.h>

@class IMConversation, IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMInAppBannerView : NSObject

/// 展示/刷新横幅。已有横幅在显示时**原地换内容并重新计时**，不新开一条。只应在主线程调用。
/// host/userID 用于点击后打开会话（同 IMChatViewController 统一入口签名）。
+ (void)showForConversation:(IMConversation *)conversation
                     message:(IMMessageModel *)message
                        host:(NSString *)host
                      userID:(NSString *)userID;

/// 立即收起当前横幅（若有）。供测试/宿主在需要时主动调用；正常生命周期由内部计时器/手势驱动。
+ (void)dismiss;

@end

NS_ASSUME_NONNULL_END
