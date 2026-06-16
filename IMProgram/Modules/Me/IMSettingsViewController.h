//  IMSettingsViewController.h
//  "我"页：当前 uid + 编辑资料入口 + 退出登录。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSettingsViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
