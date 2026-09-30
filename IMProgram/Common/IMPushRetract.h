//  IMPushRetract.h
//  消息被撤回 / 为所有人删除后，把通知中心里指向它的那条通知拿掉（M5，PUSH_M5_DESIGN §3.4）。
//
//  收回有两条路，本文件是 **App 活着** 的那一条：
//   · App 没在跑 / 挂起：系统不给执行机会，服务端用同一个 apns-collapse-id 再推一条，把原通知的
//     文字原地换成「对方撤回了一条消息」（PROTOCOL §6.14，本端不需要任何代码）；
//   · App 活着（前台、或后台连接还没断、或之后重连 sync 补到这条 msg_op）：直接从通知中心删掉——
//     包括上面那条替换后的撤回提示，人已经回到 App 里了，它没有留着的必要。
//
//  按通知 userInfo 里的 conv_id + conv_seq 认，不依赖通知 identifier 的取值规则。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 纯函数：这条通知的 userInfo 指的是不是 (convID, convSeq) 这条消息。
/// 字段缺失 / 类型不对 / convSeq<=0 一律 NO——认不准就不删。
FOUNDATION_EXPORT BOOL IMPushUserInfoMatchesMessage(NSDictionary *_Nullable userInfo,
                                                    NSString *_Nullable convID, int64_t convSeq);

/// 从通知中心移除指向这条消息的已展示通知（异步，任意线程可调；没有匹配的就是空操作）。
FOUNDATION_EXPORT void IMPushRetractDeliveredNotification(NSString *convID, int64_t convSeq);

NS_ASSUME_NONNULL_END
