//  IMAlertDecision.h
//  统一判据 alertDecision（纯函数，可测）：一条实时到达的入站消息该不该响/振/弹横幅/弹系统通知。
//  三端同名判据，共用向量 IMServer/docs/conformance/alert_decision.json（30 条，改规则先改向量）。
//  设计：IMServer/docs/design/NOTIFICATIONS_DESIGN.md §3.1/§3.2。
//
//  iOS 运行时只会构造 platform=mobile 的 ctx（桌面/浏览器分支只为通过共用向量、供设计对齐核对，
//  不在本端被任何调用点触发）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// ctx.platform 取值。
extern NSString * const IMAlertPlatformMobile;
extern NSString * const IMAlertPlatformDesktop;
extern NSString * const IMAlertPlatformBrowser;

/// ctx.convType 取值。
extern NSString * const IMAlertConvTypePrivate;
extern NSString * const IMAlertConvTypeGroup;

@interface IMAlertTypeSettings : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL preview;
@property (nonatomic, copy) NSString *sound; // 原始 id（未校验，判据内部走 IMNotificationSoundIDNormalize 口径）
@end

@interface IMAlertInAppSettings : NSObject
@property (nonatomic, assign) BOOL sound;
@property (nonatomic, assign) BOOL vibrate;
@property (nonatomic, assign) BOOL preview;
@end

@interface IMAlertBadgeSettings : NSObject
@property (nonatomic, assign) BOOL includeMuted;
@end

@interface IMAlertDesktopSettings : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL sound;
@property (nonatomic, assign) NSInteger volume;
@end

/// 判据要读的全部设置值（对应向量 JSON 的 `settings`）。
@interface IMAlertSettingsSnapshot : NSObject
@property (nonatomic, strong) IMAlertTypeSettings *privateType;
@property (nonatomic, strong) IMAlertTypeSettings *groupType;
@property (nonatomic, strong) IMAlertInAppSettings *inApp;
@property (nonatomic, strong) IMAlertBadgeSettings *badge;
@property (nonatomic, strong) IMAlertDesktopSettings *desktop;
@end

/// 一条实时消息的判定上下文（对应向量 JSON 的 `ctx`）。
@interface IMAlertContext : NSObject
@property (nonatomic, copy) NSString *platform; // mobile|desktop|browser
@property (nonatomic, assign) BOOL isLive;
@property (nonatomic, assign) BOOL isSelf;
@property (nonatomic, assign) BOOL isSystem;
@property (nonatomic, assign) BOOL isRecalled;
@property (nonatomic, assign) BOOL isCallRecord;
@property (nonatomic, assign) BOOL missedCallForMe;
@property (nonatomic, copy) NSString *convType; // private|group
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) BOOL mentionsMe;
@property (nonatomic, assign) BOOL appActive;
@property (nonatomic, assign) BOOL windowFocused;
@property (nonatomic, assign) BOOL viewingConv;
@property (nonatomic, assign) BOOL inCall;
@property (nonatomic, assign) int64_t nowMs;
@property (nonatomic, assign) int64_t lastSoundAtMs;
@property (nonatomic, strong) IMAlertSettingsSnapshot *settings;
@end

/// 判定结果（对应向量 JSON 的 `expect`）。soundId 仅在 sound=YES 时非空。
@interface IMAlertResult : NSObject
@property (nonatomic, assign) BOOL sound;
@property (nonatomic, assign) BOOL vibrate;
@property (nonatomic, assign) BOOL banner;   // P1 §1.1：eligible && platform==mobile && settings.inApp.preview（不受节流）
@property (nonatomic, assign) BOOL osNotify; // 仅 desktop 且窗口不在焦点
@property (nonatomic, copy, nullable) NSString *soundId;
@end

/// 纯函数：不读任何全局态，入参之外零依赖，可离线单测。
FOUNDATION_EXPORT IMAlertResult *IMAlertDecide(IMAlertContext *ctx);

NS_ASSUME_NONNULL_END
