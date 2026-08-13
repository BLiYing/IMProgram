//  IMQRLoginConfirmViewController.h
//  扫码登录确认页（QR P1，sketch §06 手机确认）：手机扫到网页版登录码后，
//  展示 Web 端 设备 / IP / 大致位置 / 时间，用户「确认登录」或「不是我，拒绝登录」。
//  设备/IP/位置来自 POST /qr/login/scan；确认/拒绝调 /qr/login/confirm · /reject。
//  沿用 IMQRResultRouter 的「语义页 push 进导航栈」约定（复用容器注入的液态标题栏）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMQRLoginConfirmViewController : UIViewController

/// push 进当前导航栈。device/ip/location 由 /qr/login/scan 返回（可空）。
/// 确认/拒绝只用 ticket + 当前登录 token，无需 host/userID。
+ (void)pushFrom:(UIViewController *)from
          ticket:(NSString *)ticket
          device:(nullable NSString *)device
              ip:(nullable NSString *)ip
        location:(nullable NSString *)location;

@end

NS_ASSUME_NONNULL_END
