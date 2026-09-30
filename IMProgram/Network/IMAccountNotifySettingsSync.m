//  IMAccountNotifySettingsSync.m

#import "IMAccountNotifySettingsSync.h"
#import "IMNotifySettingsMigration.h"
#import "IMNotificationSettings.h"
#import "IMHTTPService.h"
#import "IMHTTPService+Push.h"
#import "IMSocketManager.h"
#import "IMSocketManager+Push.h"
#import "IMLog.h"

static NSString * const kIMNotifySyncVersionKey = @"im.notify.sync.version";
static NSString * const kIMNotifySyncDirtyKey   = @"im.notify.sync.dirty";
/// 上面两项（以及本地的私聊/群聊/角标三项现值）属于哪个账号；空 = 升级前的老数据，归第一个登录的账号。
static NSString * const kIMNotifySyncOwnerKey   = @"im.notify.sync.owner";

@implementation IMAccountNotifySettingsSync {
    BOOL _started;
    BOOL _applyingServer; // 服务端下发触发的本地写回期间置 YES，避免回环再 PUT 一次
    int64_t _version;
}

+ (instancetype)shared {
    static IMAccountNotifySettingsSync *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMAccountNotifySettingsSync new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _version = [NSUserDefaults.standardUserDefaults integerForKey:kIMNotifySyncVersionKey];
    }
    return self;
}

- (void)start {
    if (_started) { return; }
    _started = YES;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(onSocketStateChanged:) name:IMSocketDidChangeStateNotification object:nil];
    [nc addObserver:self selector:@selector(onNotifySettingsUpdate:) name:IMSocketDidReceiveNotifySettingsUpdateNotification object:nil];
    [nc addObserver:self selector:@selector(onLocalSettingsChanged) name:IMNotificationSettingsDidChangeNotification object:nil];
    [self refresh];
}

- (void)onSocketStateChanged:(NSNotification *)note {
    if ([note.userInfo[@"state"] integerValue] == IMSocketStateConnected) { [self refresh]; }
}

- (void)onNotifySettingsUpdate:(NSNotification *)note {
    int64_t incoming = [note.userInfo[@"version"] longLongValue];
    if (IMNotifySettingsShouldRefetchForVersion(_version, incoming)) { [self refresh]; }
}

/// 本地任一处改了通知设置（含与本类无关的应用内三项）就会广播这条；只要不是我们自己应用服务端值
/// 触发的，就把当前私聊/群聊/角标三项现值推上去——多余的 PUT（如只改了应用内振动）是幂等的，代价可接受。
- (void)onLocalSettingsChanged {
    if (_applyingServer) { return; }
    [self pushLocalToServer];
}

- (void)refresh {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; } // 未登录：留本地，登录后 socket 连上会触发 refresh
    [self adoptOwner:IMSocketManager.sharedManager.userID];

    BOOL dirty = [NSUserDefaults.standardUserDefaults boolForKey:kIMNotifySyncDirtyKey];
    if (dirty) {
        // 上一轮本地修改还没确认同步成功（IMNotifySettingsSyncDecideAction(dirty=YES, *) 恒为 Push）：
        // 优先重推，不去 GET（避免被服务端旧值覆盖掉这次修改）。
        [self pushLocalToServer];
        return;
    }

    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService notifySettingsWithToken:token completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || !data) {
            if (error) { IMLogWarnWithTag(IMLogTagPush, @"notify_settings_fetch_failed error=%@", error.localizedDescription ?: @"-"); }
            return; // 失败保留本地，下次登录/重连再试
        }
        BOOL exists = [data[@"exists"] boolValue];
        switch (IMNotifySettingsSyncDecideAction(NO, exists)) {
            case IMNotifySettingsSyncActionApplyServer: {
                NSDictionary *settingsJSON = [data[@"settings"] isKindOfClass:NSDictionary.class] ? data[@"settings"] : @{};
                IMNotifySettingsValues *values = IMNotifySettingsValuesFromServerJSON(settingsJSON);
                [self applyServerValues:values];
                [self setVersion:[data[@"version"] longLongValue]];
                IMLogWithTag(IMLogTagPush, @"notify_settings_applied_from_server version=%lld", self->_version);
                break;
            }
            case IMNotifySettingsSyncActionPush:
                // 服务端还没有这份设置：一次性迁移，把本地现值传上去。
                [self pushLocalToServer];
                break;
        }
    }];
}

/// 换了账号：本地三项与「待补推」标记都是上一个账号的——既不能补推到新账号，也不能在新账号
/// exists=false 时当成它的值迁移上去。先恢复默认、清掉同步状态（与 Web useAccountNotifySettings、
/// Android AccountNotifySettingsStore.forget() 同口径）。
- (void)adoptOwner:(nullable NSString *)uid {
    if (uid.length == 0) { return; }
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *owner = [d stringForKey:kIMNotifySyncOwnerKey];
    if (IMNotifySettingsOwnerSwitched(owner, uid)) {
        IMNotifySettingsValues *defaults = IMNotifySettingsValuesFromServerJSON(@{});
        [self applyServerValues:defaults]; // 复用：写回本地 + 不回环 PUT + 清 dirty
        [self setVersion:0];
        IMLogWithTag(IMLogTagPush, @"notify_settings_owner_switched reset_to_defaults=1");
    }
    if (![owner isEqualToString:uid]) { [d setObject:uid forKey:kIMNotifySyncOwnerKey]; }
}

- (void)applyServerValues:(IMNotifySettingsValues *)values {
    _applyingServer = YES;
    [IMNotificationSettings.shared setEnabled:values.privateEnabled preview:values.privatePreview sound:values.privateSound forGroup:NO];
    [IMNotificationSettings.shared setEnabled:values.groupEnabled preview:values.groupPreview sound:values.groupSound forGroup:YES];
    IMNotificationSettings.shared.badgeIncludeMuted = values.badgeIncludeMuted;
    _applyingServer = NO;
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:kIMNotifySyncDirtyKey];
}

- (IMNotifySettingsValues *)currentLocalValues {
    IMNotifySettingsValues *v = [IMNotifySettingsValues new];
    IMNotificationSettings *s = IMNotificationSettings.shared;
    v.privateEnabled = s.privateType.enabled; v.privatePreview = s.privateType.preview; v.privateSound = s.privateType.sound;
    v.groupEnabled = s.groupType.enabled; v.groupPreview = s.groupType.preview; v.groupSound = s.groupType.sound;
    v.badgeIncludeMuted = s.badgeIncludeMuted;
    return v;
}

- (void)pushLocalToServer {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:kIMNotifySyncDirtyKey];
        return;
    }
    NSDictionary *json = IMNotifySettingsValuesToServerJSON([self currentLocalValues]);
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService updateNotifySettingsWithToken:token settings:json completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || !data) {
            IMLogWarnWithTag(IMLogTagPush, @"notify_settings_push_failed error=%@ dirty=1", error.localizedDescription ?: @"-");
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:kIMNotifySyncDirtyKey];
            return;
        }
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:kIMNotifySyncDirtyKey];
        [self setVersion:[data[@"version"] longLongValue]];
        IMLogWithTag(IMLogTagPush, @"notify_settings_pushed version=%lld", self->_version);
    }];
}

- (void)setVersion:(int64_t)version {
    _version = version;
    [NSUserDefaults.standardUserDefaults setInteger:version forKey:kIMNotifySyncVersionKey];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
