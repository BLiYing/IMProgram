//  IMUserSearchViewController.h
//  找人：搜索框 + 结果列表；按"我与对端关系"显示 加好友/已申请/同意/发消息。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMUserSearchViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
