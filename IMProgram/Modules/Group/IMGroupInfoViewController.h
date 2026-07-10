//  IMGroupInfoViewController.h
//  群资料页（M3）：群名/成员数 + 邀请成员/退出群聊 + 成员列表（角色徽章）。
//  按 my_role 显隐管理操作：群主可 设/撤管理员·转让群主·移出任何人；管理员可移出普通成员；
//  改群名 = 群主/管理员（右上编辑）。所有权限服务端二次校验。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMGroupInfoViewController : UIViewController

- (instancetype)initWithHost:(NSString *)host
                      userID:(NSString *)userID
                      convID:(NSString *)convID NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
