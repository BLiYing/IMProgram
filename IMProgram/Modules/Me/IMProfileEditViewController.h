//  IMProfileEditViewController.h
//  编辑我的资料：昵称/头像 URL/手机号/标签。GET /users/me 回填，PUT /users/me 保存。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMProfileEditViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
