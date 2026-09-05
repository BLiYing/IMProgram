//  IMFriendRequestListViewController.h
//  「新的朋友」独立页（通讯录入口，群聊下方）。
//
//  为什么独立成页（2026-09-05）：原来它是通讯录里好友列表上方的一段，好友一多就被挤到看不见，
//  而"有人加我"恰恰是需要主动去处理的事。微信也是给它一个固定入口。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMFriendRequestListViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
