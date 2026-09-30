//  IMPushSettings.h
//  「接收离线推送」开关：每设备本地偏好（NSUserDefaults `im.push.receiveOffline`），默认开（M5，
//  PUSH_M5_DESIGN §5）。与 IMNotificationSettings（私聊/群聊/角标，账号级/每设备）是两类不同的东西——
//  这个开关控制的是"这台设备要不要注册 APNs 令牌"，本身从不上传到服务端，只影响本机是否
//  调用 registerForRemoteNotifications / 是否保留服务端的令牌行。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 开关变化时广播（设置页据此刷新；IMPushTokenManager 据此决定注册还是删除令牌）。
extern NSNotificationName const IMPushSettingsDidChangeNotification;

@interface IMPushSettings : NSObject

@property (class, nonatomic, readonly) IMPushSettings *shared;

/// 接收离线推送（本设备）。默认 YES；关闭时 IMPushTokenManager 会删除本机已登记的令牌，
/// 且此后不再重新注册，直到再次打开。
@property (nonatomic, assign) BOOL receiveOfflinePush;

@end

NS_ASSUME_NONNULL_END
