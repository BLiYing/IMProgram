//  IMDownloadSettingsStore.m

#import "IMDownloadSettingsStore.h"
#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMLog.h"

NSString * const IMDownloadSettingsDidChangeNotification = @"IMDownloadSettingsDidChangeNotification";

@implementation IMDownloadSettingsStore {
    BOOL _started;
}

+ (instancetype)shared {
    static IMDownloadSettingsStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMDownloadSettingsStore new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) { _settings = [IMDownloadSettings defaultSettings]; }
    return self;
}

- (void)start {
    if (_started) { return; }
    _started = YES;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    // capabilities_update：账号策略变更，重拉最新做多端同步。
    [nc addObserver:self selector:@selector(refresh) name:IMSocketDidReceiveCapabilitiesUpdateNotification object:nil];
    // 连接状态变化：**仅在真正连上时**补拉一次（登录/重连后 token 就绪）。connecting/disconnected 不发无谓请求
    // （弱网频繁重连会一秒几发 GET）——只认 Connected 那一帧。
    [nc addObserver:self selector:@selector(onSocketStateChanged:) name:IMSocketDidChangeStateNotification object:nil];
    [self refresh];
}

- (void)onSocketStateChanged:(NSNotification *)note {
    if ([note.userInfo[@"state"] integerValue] == IMSocketStateConnected) { [self refresh]; }
}

- (void)refresh {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; } // 未登录：留默认，登录后再拉
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService downloadSettingsWithToken:token completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self || error || !data) {
            if (error) { IMLogWarnWithTag(IMLogTagMedia, @"download_settings_fetch_failed error=%@", error.localizedDescription ?: @"-"); }
            return; // 失败保留旧值（默认或上次拉到的）
        }
        [self applySettings:[IMDownloadSettings fromJSON:data]];
    }];
}

- (void)applySettings:(IMDownloadSettings *)settings {
    if (!settings) { return; }
    _settings = settings;
    // 策略是**所有门控判定的输入**：不记就无法回答"我明明设了 Wi-Fi 高档，为什么还在门控"。
    // version 与服务端 download_settings_saved 的 version 对账，即可确认多端同步是否真的到了这一端。
    IMLogWithTag(IMLogTagMedia, @"download_settings_applied version=%lld wifi_enabled=%d cellular_enabled=%d "
                 "wifi_video_max=%lld wifi_file_max=%lld cellular_video_max=%lld cellular_file_max=%lld",
                 settings.version, settings.wifi.enabled, settings.cellular.enabled,
                 settings.wifi.video.maxBytes, settings.wifi.file.maxBytes,
                 settings.cellular.video.maxBytes, settings.cellular.file.maxBytes);
    [NSNotificationCenter.defaultCenter postNotificationName:IMDownloadSettingsDidChangeNotification object:self];
}

- (void)saveSettings:(IMDownloadSettings *)settings {
    if (!settings) { return; }
    [self applySettings:settings]; // 乐观：UI 立即反映
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; } // 未登录：仅本地（登录后由 refresh 覆盖）
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService updateDownloadSettingsWithToken:token settings:[settings toSettingsDictionary]
                                                     completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || !data) {
            IMLogWarnWithTag(IMLogTagMedia, @"download_settings_save_failed error=%@ rollback=1",
                             error.localizedDescription ?: @"-");
            [self refresh]; return;                            // 失败：以服务端为准重拉（回滚乐观值）
        }
        [self applySettings:[IMDownloadSettings fromJSON:data]]; // 成功：用服务端规整后的权威值
    }];
}

- (void)resetToDefaults {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { [self applySettings:[IMDownloadSettings defaultSettings]]; return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService resetDownloadSettingsWithToken:token completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error || !data) {
            IMLogWarnWithTag(IMLogTagMedia, @"download_settings_reset_failed error=%@", error.localizedDescription ?: @"-");
            [self refresh]; return;
        }
        [self applySettings:[IMDownloadSettings fromJSON:data]];
    }];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
