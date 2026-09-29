//  IMNotificationTypeViewController.h
//  设置 ▸ 通知与提示音 ▸ 私聊/群聊 子页（NOTIFICATIONS_DESIGN §2.3，两页同构，private/group 共用一个类）。
//  显示通知 / 消息预览 / 提示音 三行 + 「例外」= 该类型下本机免打扰的会话列表（查看 + 取消，不提供新增）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMNotificationTypeViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID isGroup:(BOOL)isGroup;

@end

NS_ASSUME_NONNULL_END
