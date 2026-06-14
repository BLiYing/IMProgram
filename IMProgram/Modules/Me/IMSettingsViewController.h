//  IMSettingsViewController.h
//  "我"页占位：显示当前 uid + 退出登录（M1 骨架，后续补个人资料/设置）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSettingsViewController : UIViewController

- (instancetype)initWithUserID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
