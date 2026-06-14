//  IMMainTabBarController.h
//  登录后的主界面骨架：底部 Tab（会话 / 我）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMainTabBarController : UITabBarController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
