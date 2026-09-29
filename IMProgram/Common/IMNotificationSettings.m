//  IMNotificationSettings.m

#import "IMNotificationSettings.h"
#import "IMAlertDecision.h"
#import "IMLocalization.h"

NSNotificationName const IMNotificationSettingsDidChangeNotification = @"IMNotificationSettingsDidChangeNotification";

NSString * const IMNotificationSoundIDNone = @"none";
NSString * const IMNotificationSoundIDDefault = @"default";
NSString * const IMNotificationSoundIDChord = @"chord";
NSString * const IMNotificationSoundIDChime = @"chime";
NSString * const IMNotificationSoundIDRise = @"rise";
NSString * const IMNotificationSoundIDDrop = @"drop";

static NSArray<NSString *> *IMAllSoundIDs(void) {
    return @[IMNotificationSoundIDNone, IMNotificationSoundIDDefault, IMNotificationSoundIDChord,
              IMNotificationSoundIDChime, IMNotificationSoundIDRise, IMNotificationSoundIDDrop];
}

NSString *IMNotificationSoundIDNormalize(NSString *soundID) {
    if (soundID.length > 0 && [IMAllSoundIDs() containsObject:soundID]) { return soundID; }
    return IMNotificationSoundIDDefault;
}

NSString *IMNotificationSoundDisplayName(NSString *soundID) {
    NSString *sid = [soundID isEqualToString:IMNotificationSoundIDNone] ? soundID : IMNotificationSoundIDNormalize(soundID);
    NSDictionary<NSString *, NSString *> *keys = @{
        IMNotificationSoundIDNone: @"notif.sound.none",
        IMNotificationSoundIDDefault: @"notif.sound.default",
        IMNotificationSoundIDChord: @"notif.sound.chord",
        IMNotificationSoundIDChime: @"notif.sound.chime",
        IMNotificationSoundIDRise: @"notif.sound.rise",
        IMNotificationSoundIDDrop: @"notif.sound.drop",
    };
    return IMLocalized(keys[sid] ?: @"notif.sound.default");
}

static NSString * const kIMNotifPrivateEnabledKey = @"im.notif.private.enabled";
static NSString * const kIMNotifPrivatePreviewKey = @"im.notif.private.preview";
static NSString * const kIMNotifPrivateSoundKey   = @"im.notif.private.sound";
static NSString * const kIMNotifGroupEnabledKey   = @"im.notif.group.enabled";
static NSString * const kIMNotifGroupPreviewKey   = @"im.notif.group.preview";
static NSString * const kIMNotifGroupSoundKey     = @"im.notif.group.sound";
static NSString * const kIMNotifInAppSoundKey     = @"im.notif.inApp.sound";
static NSString * const kIMNotifInAppVibrateKey   = @"im.notif.inApp.vibrate";
static NSString * const kIMNotifInAppPreviewKey   = @"im.notif.inApp.preview";
static NSString * const kIMNotifBadgeIncludeMutedKey = @"im.notif.badge.includeMuted";

@implementation IMNotificationTypeSettings
@end

@interface IMNotificationSettings ()
@property (nonatomic, strong, readwrite) IMNotificationTypeSettings *privateType;
@property (nonatomic, strong, readwrite) IMNotificationTypeSettings *groupType;
@end

@implementation IMNotificationSettings

+ (instancetype)shared {
    static IMNotificationSettings *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [IMNotificationSettings new]; });
    return value;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;

        IMNotificationTypeSettings *priv = [IMNotificationTypeSettings new];
        priv.enabled = [d objectForKey:kIMNotifPrivateEnabledKey] ? [d boolForKey:kIMNotifPrivateEnabledKey] : YES;
        priv.preview = [d objectForKey:kIMNotifPrivatePreviewKey] ? [d boolForKey:kIMNotifPrivatePreviewKey] : YES;
        priv.sound = IMNotificationSoundIDNormalize([d stringForKey:kIMNotifPrivateSoundKey] ?: IMNotificationSoundIDDefault);
        _privateType = priv;

        IMNotificationTypeSettings *group = [IMNotificationTypeSettings new];
        group.enabled = [d objectForKey:kIMNotifGroupEnabledKey] ? [d boolForKey:kIMNotifGroupEnabledKey] : YES;
        group.preview = [d objectForKey:kIMNotifGroupPreviewKey] ? [d boolForKey:kIMNotifGroupPreviewKey] : YES;
        group.sound = IMNotificationSoundIDNormalize([d stringForKey:kIMNotifGroupSoundKey] ?: IMNotificationSoundIDDefault);
        _groupType = group;

        _inAppSound = [d objectForKey:kIMNotifInAppSoundKey] ? [d boolForKey:kIMNotifInAppSoundKey] : NO;
        _inAppVibrate = [d objectForKey:kIMNotifInAppVibrateKey] ? [d boolForKey:kIMNotifInAppVibrateKey] : NO;
        _inAppPreview = [d objectForKey:kIMNotifInAppPreviewKey] ? [d boolForKey:kIMNotifInAppPreviewKey] : NO;
        _badgeIncludeMuted = [d objectForKey:kIMNotifBadgeIncludeMutedKey] ? [d boolForKey:kIMNotifBadgeIncludeMutedKey] : NO;
    }
    return self;
}

- (void)persistAndNotify {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:self.privateType.enabled forKey:kIMNotifPrivateEnabledKey];
    [d setBool:self.privateType.preview forKey:kIMNotifPrivatePreviewKey];
    [d setObject:self.privateType.sound forKey:kIMNotifPrivateSoundKey];
    [d setBool:self.groupType.enabled forKey:kIMNotifGroupEnabledKey];
    [d setBool:self.groupType.preview forKey:kIMNotifGroupPreviewKey];
    [d setObject:self.groupType.sound forKey:kIMNotifGroupSoundKey];
    [d setBool:self.inAppSound forKey:kIMNotifInAppSoundKey];
    [d setBool:self.inAppVibrate forKey:kIMNotifInAppVibrateKey];
    [d setBool:self.inAppPreview forKey:kIMNotifInAppPreviewKey];
    [d setBool:self.badgeIncludeMuted forKey:kIMNotifBadgeIncludeMutedKey];
    [NSNotificationCenter.defaultCenter postNotificationName:IMNotificationSettingsDidChangeNotification object:self];
}

- (void)setEnabled:(BOOL)enabled preview:(BOOL)preview sound:(NSString *)sound forGroup:(BOOL)isGroup {
    IMNotificationTypeSettings *target = isGroup ? self.groupType : self.privateType;
    target.enabled = enabled;
    target.preview = preview;
    target.sound = IMNotificationSoundIDNormalize(sound);
    [self persistAndNotify];
}

- (void)setInAppSound:(BOOL)inAppSound {
    _inAppSound = inAppSound;
    [self persistAndNotify];
}

- (void)setInAppVibrate:(BOOL)inAppVibrate {
    _inAppVibrate = inAppVibrate;
    [self persistAndNotify];
}

- (void)setInAppPreview:(BOOL)inAppPreview {
    _inAppPreview = inAppPreview;
    [self persistAndNotify];
}

- (void)setBadgeIncludeMuted:(BOOL)badgeIncludeMuted {
    _badgeIncludeMuted = badgeIncludeMuted;
    [self persistAndNotify];
}

- (void)resetToDefaults {
    IMNotificationTypeSettings *priv = [IMNotificationTypeSettings new];
    priv.enabled = YES; priv.preview = YES; priv.sound = IMNotificationSoundIDDefault;
    self.privateType = priv;
    IMNotificationTypeSettings *group = [IMNotificationTypeSettings new];
    group.enabled = YES; group.preview = YES; group.sound = IMNotificationSoundIDDefault;
    self.groupType = group;
    // 应用内三项默认关（2026-09-29 用户：App 开着时没必要响/振/弹；提醒留给后台时的系统通知）
    _inAppSound = NO;
    _inAppVibrate = NO;
    _inAppPreview = NO;
    _badgeIncludeMuted = NO;
    [self persistAndNotify];
}

- (IMAlertSettingsSnapshot *)alertSnapshot {
    IMAlertSettingsSnapshot *snapshot = [IMAlertSettingsSnapshot new];

    IMAlertTypeSettings *priv = [IMAlertTypeSettings new];
    priv.enabled = self.privateType.enabled; priv.preview = self.privateType.preview; priv.sound = self.privateType.sound;
    snapshot.privateType = priv;

    IMAlertTypeSettings *group = [IMAlertTypeSettings new];
    group.enabled = self.groupType.enabled; group.preview = self.groupType.preview; group.sound = self.groupType.sound;
    snapshot.groupType = group;

    IMAlertInAppSettings *inApp = [IMAlertInAppSettings new];
    inApp.sound = self.inAppSound; inApp.vibrate = self.inAppVibrate; inApp.preview = self.inAppPreview;
    snapshot.inApp = inApp;

    IMAlertBadgeSettings *badge = [IMAlertBadgeSettings new];
    badge.includeMuted = self.badgeIncludeMuted;
    snapshot.badge = badge;

    // iOS 本端不存 desktop.* 偏好（那是 Web/桌面端的本地偏好）；判据 iOS 只会构造 platform=mobile，
    // 这两个字段永不被读到，填安全占位值即可。
    IMAlertDesktopSettings *desktop = [IMAlertDesktopSettings new];
    desktop.enabled = NO; desktop.sound = NO; desktop.volume = 0;
    snapshot.desktop = desktop;

    return snapshot;
}

@end
