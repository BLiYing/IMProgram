//  IMContactsViewController.h
//  通讯录 Tab：新的朋友（待处理申请，同意/拒绝）+ 好友列表（点击发起会话）。右上角 + 进找人页。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMContactsViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
