//  IMNotificationSettingsViewController.h
//  设置 ▸ 通知与提示音：主页（NOTIFICATIONS_DESIGN §2.2）。
//  消息通知（私聊/群聊子页入口）/ 应用内通知 / 角标计数 / 锁屏与后台通知（P2 占位）/ 重置。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMNotificationSettingsViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
