//  IMDeviceModels.h
//  已登录设备（多设备管理，QR P2）：GET /api/v1/devices 返回的一条登录会话。
//  登录设备(session)持久、可逐台吊销；"在线"是其当前有活 WS 连接的展示子态（online 字段）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMDeviceSession : NSObject
@property (nonatomic, copy) NSString *sessionID;    ///< sid：踢下线的目标
@property (nonatomic, copy) NSString *platform;     ///< ios | android | web | desktop | unknown
@property (nonatomic, copy) NSString *deviceName;   ///< "李默的 iPhone" / "Chrome · macOS"
@property (nonatomic, copy) NSString *appVersion;
@property (nonatomic, copy) NSString *loginIP;
@property (nonatomic, copy) NSString *loginLoc;     ///< 大致位置（IP 反查，仅展示，可空）
@property (nonatomic, assign) int64_t createdAt;    ///< 登录时间（毫秒）
@property (nonatomic, assign) int64_t lastActiveAt; ///< 最近活跃（毫秒）
@property (nonatomic, assign) BOOL online;          ///< 当前有活 WS 连接
@property (nonatomic, assign) BOOL current;         ///< 是否本机（本次请求的 sid）

+ (nullable instancetype)fromDictionary:(nullable NSDictionary *)dict;
+ (NSArray<IMDeviceSession *> *)fromArray:(nullable NSArray *)arr;

/// 平台图标（emoji，与交互草图一致）。
- (NSString *)platformEmoji;
/// 平台展示名："iOS / Android / 网页版 / 桌面端 / 未知设备"。
- (NSString *)platformLabel;
/// 副标题（列表行）："在线 · iOS · 深圳 · 113.88.xx.xx" / "3 天前活跃 · 广州"（不含 ●，圆点由 cell 上色绘制）。
- (NSString *)statusLine;
/// 最近活跃（相对文案）："刚刚活跃 / X 分钟前活跃 / X 天前活跃"。
- (NSString *)lastActiveText;
/// 登录时间（绝对文案）："2026-08-13 09:12" / 空时回 "—"。
- (NSString *)loginTimeText;
@end

NS_ASSUME_NONNULL_END
