//  IMAlertDecision.m
//  见 .h 顶部注释。逐条对齐 IMServer/docs/conformance/alert_decision.json 的 30 条向量
//  （IMAlertDecisionTests 直接读该文件跑）。

#import "IMAlertDecision.h"
#import "IMNotificationSettings.h" // IMNotificationSoundIDNormalize/None

NSString * const IMAlertPlatformMobile = @"mobile";
NSString * const IMAlertPlatformDesktop = @"desktop";
NSString * const IMAlertPlatformBrowser = @"browser";

NSString * const IMAlertConvTypePrivate = @"private";
NSString * const IMAlertConvTypeGroup = @"group";

@implementation IMAlertTypeSettings
@end

@implementation IMAlertInAppSettings
@end

@implementation IMAlertBadgeSettings
@end

@implementation IMAlertDesktopSettings
@end

@implementation IMAlertSettingsSnapshot
@end

@implementation IMAlertContext
@end

@implementation IMAlertResult
@end

/// 1.5 秒节流窗口（NOTIFICATIONS_DESIGN §3.1：连发十条只响一声）。>= 视为不节流（含边界，向量「刚好 1.5 秒」）。
static int64_t const kIMAlertThrottleMs = 1500;

IMAlertResult *IMAlertDecide(IMAlertContext *ctx) {
    IMAlertResult *result = [IMAlertResult new];

    BOOL isMobile = [ctx.platform isEqualToString:IMAlertPlatformMobile];
    BOOL isDesktop = [ctx.platform isEqualToString:IMAlertPlatformDesktop];

    BOOL isPrivate = [ctx.convType isEqualToString:IMAlertConvTypePrivate];
    IMAlertTypeSettings *typeSettings = isPrivate ? ctx.settings.privateType : ctx.settings.groupType;

    // 内容级：自己发的 / 系统消息 / 撤回 / 非实时 / 通话记录里我方未错过的一律不提醒（§3.1 表）。
    BOOL blockedByContent = !ctx.isLive || ctx.isSelf || ctx.isSystem || ctx.isRecalled
        || (ctx.isCallRecord && !ctx.missedCallForMe);
    // 正在看这个会话 / 通话中：什么都不做（对齐 Telegram，且通话中会抢通话音频）。
    BOOL blockedByPresence = ctx.viewingConv || ctx.inCall;
    // 移动端要求 App 在前台（P0 无推送，后台完全静默）；桌面/浏览器不看 appActive，看 windowFocused（只影响 osNotify）。
    BOOL platformGate = isMobile ? ctx.appActive : YES;
    BOOL typeEnabled = typeSettings.enabled;
    BOOL muteBlocks = ctx.muted && !ctx.mentionsMe; // @我（含@全体）穿透免打扰

    BOOL eligible = !blockedByContent && !blockedByPresence && platformGate && typeEnabled && !muteBlocks;

    // 差值为负 = 系统时钟往回拨过：当没响过，否则回拨多久就静音多久（/code-review 2026-09-29，三端同改）
    int64_t sinceLast = ctx.nowMs - ctx.lastSoundAtMs;
    BOOL throttled = sinceLast >= 0 && sinceLast < kIMAlertThrottleMs;

    NSString *resolvedSoundId = [typeSettings.sound isEqualToString:IMNotificationSoundIDNone]
        ? nil : IMNotificationSoundIDNormalize(typeSettings.sound);

    // 移动端响/振读 inApp.*；桌面/浏览器「响」读 desktop.sound（inApp.* 不管桌面，向量已验证）；
    // 振动是移动端专属能力，桌面/浏览器恒不振。
    BOOL soundEnabledFlag = isMobile ? ctx.settings.inApp.sound : ctx.settings.desktop.sound;
    BOOL vibrateEnabledFlag = isMobile ? ctx.settings.inApp.vibrate : NO;

    result.sound = eligible && soundEnabledFlag && resolvedSoundId != nil && !throttled;
    result.vibrate = eligible && vibrateEnabledFlag && !throttled;
    result.banner = NO; // P0 恒不出横幅（P1 才做应用内预览横幅）
    // 系统通知仅桌面：桌面通知开 且 窗口不在焦点（在焦点时只响一声，§3.1「桌面端窗口在焦点」段）。
    result.osNotify = eligible && isDesktop && ctx.settings.desktop.enabled && !ctx.windowFocused;
    result.soundId = result.sound ? resolvedSoundId : nil;

    return result;
}
