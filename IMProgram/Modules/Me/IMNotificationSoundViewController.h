//  IMNotificationSoundViewController.h
//  设置 ▸ 通知与提示音 ▸ 私聊/群聊 ▸ 提示音选择页（NOTIFICATIONS_DESIGN §2.4）。
//  点一下即选中并试听一次，没有「完成」按钮；返回时停止试听。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMNotificationSoundViewController : UIViewController

/// isGroup=YES 编辑群聊提示音，NO 编辑私聊提示音。
- (instancetype)initForGroup:(BOOL)isGroup;

@end

NS_ASSUME_NONNULL_END
