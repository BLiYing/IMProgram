//  IMChangePasswordViewController.h
//  隐私与安全 · 修改密码（设计见 IMServer/docs/PRIVACY_SECURITY_DESIGN.md §4.2）。
//  三输入框（旧/新/确认）+ 本地校验 + POST /api/v1/users/me/password + 成功 Toast+pop / 失败就地红字。
//  成功后服务端会自动下线其它全部设备（只保留当前设备），无需用户手动逐台下线。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMChangePasswordViewController : UIViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
@end

NS_ASSUME_NONNULL_END
