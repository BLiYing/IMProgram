//  IMNotificationSettings.h
//  设置 ▸ 通知与提示音：每设备本地偏好（NSUserDefaults `im.notif.<字段>`）。
//  设计：IMServer/docs/design/NOTIFICATIONS_DESIGN.md §6/§7/§9-1——每设备本地、退出登录不清
//  （与 IMAppearance 同一处理，见其 .h 注释）。P0 iOS 只存移动端相关字段（私聊/群聊/应用内/角标），
//  不存 desktop.*（那是 Web/桌面端的本地偏好）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const IMNotificationSettingsDidChangeNotification;

/// 提示音 id：none=无，default=默认，其余 4 个备选。未知 id 一律回落 default（IMNotificationSoundIDNormalize）。
extern NSString * const IMNotificationSoundIDNone;
extern NSString * const IMNotificationSoundIDDefault;
extern NSString * const IMNotificationSoundIDChord;
extern NSString * const IMNotificationSoundIDChime;
extern NSString * const IMNotificationSoundIDRise;
extern NSString * const IMNotificationSoundIDDrop;

/// 合法性校验 + 回落：非法/未知 id → default；nil/空 → default。"none" 本身合法（显式无提示音）。
FOUNDATION_EXPORT NSString *IMNotificationSoundIDNormalize(NSString *_Nullable soundID);
/// 提示音 id → 本地化显示名（三个设置页共用，唯一一份映射；未知 id 按 default 显示）。
FOUNDATION_EXPORT NSString *IMNotificationSoundDisplayName(NSString *_Nullable soundID);

@class IMAlertSettingsSnapshot;

/// 私聊/群聊两类会话共用的一组开关（显示通知 / 消息预览 / 提示音）。
@interface IMNotificationTypeSettings : NSObject
@property (nonatomic, assign) BOOL enabled;   // 显示通知（关=该类型全部不响不振不弹，未读照计）
@property (nonatomic, assign) BOOL preview;   // 消息预览（P0 iOS 无落地 UI，为 P1/P2 系统通知正文预留存储）
@property (nonatomic, copy) NSString *sound;  // 提示音 id
@end

@interface IMNotificationSettings : NSObject

@property (class, nonatomic, readonly) IMNotificationSettings *shared;

@property (nonatomic, strong, readonly) IMNotificationTypeSettings *privateType; // im.notif.private.*
@property (nonatomic, strong, readonly) IMNotificationTypeSettings *groupType;   // im.notif.group.*

@property (nonatomic, assign) BOOL inAppSound;    // im.notif.inApp.sound，默认开
@property (nonatomic, assign) BOOL inAppVibrate;  // im.notif.inApp.vibrate，默认开
@property (nonatomic, assign) BOOL inAppPreview;  // im.notif.inApp.preview，默认开（P1 应用内横幅用，P0 无落地 UI）

@property (nonatomic, assign) BOOL badgeIncludeMuted; // im.notif.badge.includeMuted，默认关

/// 就地改私聊/群聊某一类的三个字段并持久化 + 广播（供子页统一走一个入口，不用分别调三个 setter）。
- (void)setEnabled:(BOOL)enabled preview:(BOOL)preview sound:(NSString *)sound forGroup:(BOOL)isGroup;

/// 恢复本页全部字段为默认值（§3.6：不取消任何会话的免打扰——那是会话表的字段，本类不碰）。
- (void)resetToDefaults;

/// 供 IMAlertDecision 使用的只读快照（mobile 端不需要 desktop.* 字段，填安全占位值）。
- (IMAlertSettingsSnapshot *)alertSnapshot;

@end

NS_ASSUME_NONNULL_END
