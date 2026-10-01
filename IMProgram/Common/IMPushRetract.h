//  IMPushRetract.h
//  把通知中心里已经没用的通知拿掉（M5）。两种情形：
//   · 消息被撤回 / 为所有人删除（PUSH_M5_DESIGN §3.4）：拿掉指向那条消息的通知；
//   · 本人在别的设备上读过了（PUSH_M5_DESIGN §3.5）：拿掉该会话里 seq ≤ 已读位点的通知。
//
//  撤回有两条路，本文件是 **App 活着** 的那一条：
//   · App 没在跑 / 挂起：系统不给执行机会，服务端用同一个 apns-collapse-id 再推一条，把原通知的
//     文字原地换成「对方撤回了一条消息」（PROTOCOL §6.14，本端不需要任何代码）；
//   · App 活着（前台、或后台连接还没断、或之后重连 sync 补到这条 msg_op）：直接从通知中心删掉——
//     包括上面那条替换后的撤回提示，人已经回到 App 里了，它没有留着的必要。
//
//  已读清通知也有两条路：连接还在时收到本人其它端的 receipt 帧（IMSocketManager handleReceipt）；
//  连接已断但 App 还在内存里时，服务端那条只带角标的推送带 content-available 把 App 唤醒
//  （AppDelegate didReceiveRemoteNotification）。被用户划掉进程时苹果文档不保证唤醒
//  （2026-10-01 iPhone 14 Pro 实测仍清掉了）；没清掉的话角标照样已更新，通知等下次打开 App 时整体清掉（SceneDelegate）。
//
//  按通知 userInfo 里的 conv_id + conv_seq 认，不依赖通知 identifier 的取值规则。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 纯函数：这条通知的 userInfo 指的是不是 (convID, convSeq) 这条消息。
/// 字段缺失 / 类型不对 / convSeq<=0 一律 NO——认不准就不删。
FOUNDATION_EXPORT BOOL IMPushUserInfoMatchesMessage(NSDictionary *_Nullable userInfo,
                                                    NSString *_Nullable convID, int64_t convSeq);

/// 纯函数：这条通知的 userInfo 是不是 convID 里 seq ≤ upTo 的消息（已读过了）。规则同上，认不准就不删。
FOUNDATION_EXPORT BOOL IMPushUserInfoReadThrough(NSDictionary *_Nullable userInfo,
                                                 NSString *_Nullable convID, int64_t upTo);

/// 纯函数：这条通知的 userInfo 指的消息，seq 在不在 convSeqs 这个集合里（多选批量撤回/删除用）。
FOUNDATION_EXPORT BOOL IMPushUserInfoMatchesAnyMessage(NSDictionary *_Nullable userInfo,
                                                       NSString *_Nullable convID,
                                                       NSSet<NSNumber *> *_Nullable convSeqs);

/// 纯函数：解析服务端「已读清通知」推送（`conv_id` + `clear_up_to`，PROTOCOL §6.14）。不是这类推送返回 NO。
FOUNDATION_EXPORT BOOL IMPushReadClearFromPayload(NSDictionary *_Nullable userInfo,
                                                  NSString *_Nullable *_Nonnull convID, int64_t *upTo);

/// 从通知中心移除指向这条消息的已展示通知（异步，任意线程可调；没有匹配的就是空操作）。
FOUNDATION_EXPORT void IMPushRetractDeliveredNotification(NSString *convID, int64_t convSeq);

/// 批量版：一次扫描通知中心移除指向 convSeqs 里任意一条消息的已展示通知（多选批量撤回/删除用）——
/// 不要循环调 [IMPushRetractDeliveredNotification]，那是逐条各发一次
/// `getDeliveredNotificationsWithCompletionHandler:`，选 100 条就是 100 次全量异步扫描。
FOUNDATION_EXPORT void IMPushRetractDeliveredNotifications(NSString *convID, NSArray<NSNumber *> *convSeqs);

/// 从通知中心移除 convID 里 seq ≤ upTo 的已展示通知（异步，任意线程可调）。
/// completion 在移除请求发出后调（后台唤醒时据此结束 fetchCompletionHandler），可为 nil。
FOUNDATION_EXPORT void IMPushClearDeliveredNotificationsReadThrough(NSString *convID, int64_t upTo,
                                                                   void (^_Nullable completion)(void));

NS_ASSUME_NONNULL_END
