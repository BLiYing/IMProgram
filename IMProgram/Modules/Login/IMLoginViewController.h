//  IMLoginViewController.h
//  极简登录页：输入服务器地址、我的 uid、对方 uid，进入聊天页。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMLoginViewController : UIViewController

/// 进页即显示的提示条（非红色，用 accent）。注销账号成功后回登录页显示 delete_account.done_hint。
/// 用户开始操作（再次点登录/注册）时随错误行一并清掉。
@property (nonatomic, copy, nullable) NSString *initialNotice;

@end

NS_ASSUME_NONNULL_END
