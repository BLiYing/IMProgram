//  UIViewController+IMFriendRequest.h
//  「发好友申请」的统一入口：弹一个填**验证消息**（申请理由）的输入框，确认后发出。
//
//  为什么收成一个 category（2026-09-05）：加好友在 App 里有四个入口——找人结果、单聊资料页、
//  群成员长按菜单、聊天页拒收系统行的恢复入口。各自直接调 `requestFriendWithToken:` 的话，
//  加一个入口就漏一次理由，收件人那边又变回"只有一个名字"。Web 侧同理收在 `askFriendRequest`。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (IMFriendRequest)

/// 弹「添加好友」输入框（预填「我是<我的昵称>」）→ 发申请 → 吐司。
///
/// - name：对方显示名，只用于弹框文案「发送给 X」。
/// - onSent：发送成功后回调（主线程）。becameFriend=YES 表示**已直接成为好友**
///   （对方先申请过我 / 我曾单向删除对方而对方仍视我为好友）——调用方据此刷新界面；
///   吐司本方法已经打过，调用方不要再打一遍。失败不回调（已吐司）。
- (void)im_askFriendRequestForUID:(NSString *)uid
                             name:(nullable NSString *)name
                           onSent:(nullable void (^)(BOOL becameFriend))onSent;

@end

NS_ASSUME_NONNULL_END
