//  IMBlockedListViewController.h
//  黑名单：列出我拉黑的用户（GET /api/v1/friends?status=blocked），可逐个解除（unblock）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMBlockedListViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
