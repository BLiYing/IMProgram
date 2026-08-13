//  IMDeviceIdentity.h
//  本机设备身份（多设备管理 / 已登录设备）：登录时随 POST /api/v1/login 上报，
//  供后端按 (uid, device_id) 顶替同一台的旧会话（避免每次登录堆一行）并在"已登录设备"里展示。
//
//  device_id 需**稳定持久**：同一台重装/重登复用。生产应存 Keychain；本工程未签名装模拟器
//  （CODE_SIGNING_ALLOWED=NO）Keychain 静默失败，故沿用 IMSessionStore 的 NSUserDefaults 约定。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMDeviceIdentity : NSObject

/// 稳定设备 ID：首次调用生成一枚随机 UUID 并持久化，之后固定返回同一枚。
@property (class, nonatomic, readonly) NSString *deviceID;
/// 平台标识：恒为 @"ios"（对齐后端 store.DevicePlatformIOS）。
@property (class, nonatomic, readonly) NSString *platform;
/// 设备名（"李默的 iPhone"），取自系统设备名；空则回退 @"iPhone"。
@property (class, nonatomic, readonly) NSString *deviceName;
/// App 版本（CFBundleShortVersionString），供设备列表展示；缺失回退 @""。
@property (class, nonatomic, readonly) NSString *appVersion;

@end

NS_ASSUME_NONNULL_END
