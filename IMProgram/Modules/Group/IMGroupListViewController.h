//  IMGroupListViewController.h
//  我的群列表（通讯录 ▸ 群聊）：列出我加入的群（点击进群聊），右上 + 创建群聊。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMGroupListViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
