//  IMDeviceDetailViewController.h
//  设备详情（多设备管理，QR P2，sketch §02 详情）：某台登录设备的 状态/类型/登录时间/最近活跃/IP/位置，
//  底部危险按钮「退出登录该设备」（系统 alert 二次确认后吊销该 sid + 断其活连接）。

#import <UIKit/UIKit.h>
@class IMDeviceSession;

NS_ASSUME_NONNULL_BEGIN

@interface IMDeviceDetailViewController : UIViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID device:(IMDeviceSession *)device;
@end

NS_ASSUME_NONNULL_END
