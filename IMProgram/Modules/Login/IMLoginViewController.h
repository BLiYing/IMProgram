//  IMLoginViewController.h
//  极简登录页：输入服务器地址、我的 uid、对方 uid，进入聊天页。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 键盘顶起时，登录页整列要上移多少（pt，>= 0），才能让输入框下沿落在键盘上沿之上并留 12pt 空隙。
/// `fieldBottom` 是该输入框在**未上移**状态下的下沿（登录页坐标），`keyboardTop` 是键盘上沿（同一坐标系；
/// 键盘未弹出时传页面下沿）。纯函数，便于单测。
FOUNDATION_EXPORT CGFloat IMLoginKeyboardLift(CGFloat fieldBottom, CGFloat keyboardTop);

@interface IMLoginViewController : UIViewController

/// 进页即显示的提示条（非红色，用 accent）。注销账号成功后回登录页显示 delete_account.done_hint。
/// 用户开始操作（再次点登录/注册）时随错误行一并清掉。
@property (nonatomic, copy, nullable) NSString *initialNotice;

@end

NS_ASSUME_NONNULL_END
