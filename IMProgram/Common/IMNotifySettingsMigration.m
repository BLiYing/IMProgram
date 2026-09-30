//  IMNotifySettingsMigration.m

#import "IMNotifySettingsMigration.h"
#import "IMNotificationSettings.h" // 复用同一份提示音枚举校验/回落口径（IMNotificationSoundIDNormalize）

@implementation IMNotifySettingsValues
@end

IMNotifySettingsSyncAction IMNotifySettingsSyncDecideAction(BOOL dirty, BOOL serverExists) {
    if (dirty) { return IMNotifySettingsSyncActionPush; }
    return serverExists ? IMNotifySettingsSyncActionApplyServer : IMNotifySettingsSyncActionPush;
}

BOOL IMNotifySettingsOwnerSwitched(NSString *owner, NSString *uid) {
    return owner.length > 0 && uid.length > 0 && ![owner isEqualToString:uid];
}

BOOL IMNotifySettingsShouldRefetchForVersion(int64_t localVersion, int64_t incomingVersion) {
    return incomingVersion > localVersion;
}

/// 私聊/群聊两类共用的子字典解析：{enabled,preview,sound}，容错取值。
static void IMApplyTypeFields(NSDictionary *dict, BOOL *enabled, BOOL *preview, NSString **sound) {
    *enabled = [dict isKindOfClass:NSDictionary.class] && dict[@"enabled"] != nil ? [dict[@"enabled"] boolValue] : YES;
    *preview = [dict isKindOfClass:NSDictionary.class] && dict[@"preview"] != nil ? [dict[@"preview"] boolValue] : YES;
    NSString *rawSound = [dict isKindOfClass:NSDictionary.class] && [dict[@"sound"] isKindOfClass:NSString.class] ? dict[@"sound"] : nil;
    *sound = IMNotificationSoundIDNormalize(rawSound);
}

IMNotifySettingsValues *IMNotifySettingsValuesFromServerJSON(NSDictionary *json) {
    IMNotifySettingsValues *v = [IMNotifySettingsValues new];
    NSDictionary *priv = [json[@"private"] isKindOfClass:NSDictionary.class] ? json[@"private"] : @{};
    NSDictionary *group = [json[@"group"] isKindOfClass:NSDictionary.class] ? json[@"group"] : @{};
    NSDictionary *badge = [json[@"badge"] isKindOfClass:NSDictionary.class] ? json[@"badge"] : @{};

    BOOL enabled, preview; NSString *sound;
    IMApplyTypeFields(priv, &enabled, &preview, &sound);
    v.privateEnabled = enabled; v.privatePreview = preview; v.privateSound = sound;

    IMApplyTypeFields(group, &enabled, &preview, &sound);
    v.groupEnabled = enabled; v.groupPreview = preview; v.groupSound = sound;

    v.badgeIncludeMuted = badge[@"include_muted"] != nil ? [badge[@"include_muted"] boolValue] : NO;
    return v;
}

NSDictionary *IMNotifySettingsValuesToServerJSON(IMNotifySettingsValues *values) {
    if (!values) { return @{}; }
    return @{
        @"private": @{
            @"enabled": @(values.privateEnabled),
            @"preview": @(values.privatePreview),
            @"sound":   IMNotificationSoundIDNormalize(values.privateSound),
        },
        @"group": @{
            @"enabled": @(values.groupEnabled),
            @"preview": @(values.groupPreview),
            @"sound":   IMNotificationSoundIDNormalize(values.groupSound),
        },
        @"badge": @{
            @"include_muted": @(values.badgeIncludeMuted),
        },
    };
}
