//  IMFriendRequestListViewController.h
//  「新的朋友」独立页（通讯录入口，群聊下方）。
//
//  为什么独立成页（2026-09-05）：原来它是通讯录里好友列表上方的一段，好友一多就被挤到看不见，
//  而"有人加我"恰恰是需要主动去处理的事。微信也是给它一个固定入口。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 本机主动改变好友关系成功后（同意/拒绝申请、拉黑/解除拉黑、删除好友）在主线程发出。
/// 为什么需要：服务端 Accept 只推给申请方，点同意的这台设备收不到好友事件；
/// 通讯录页切入刷新又有 30 秒节流 → 角标/入口行计数不减。通讯录页监听它并立即重拉（绕过节流）。
extern NSString * const IMFriendRelationDidChangeLocallyNotification;

/// 发出上面的通知（不在主线程调用时自动切回主线程）。
extern void IMPostFriendRelationDidChangeLocally(void);

@interface IMFriendRequestListViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
