//  IMConversationListViewController.h
//  会话列表：登录后首页。拉 GET /api/v1/conversations，点进入聊天页。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMConversationListViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
