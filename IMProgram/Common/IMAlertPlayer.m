//  IMAlertPlayer.m

#import "IMAlertPlayer.h"
#import <AudioToolbox/AudioToolbox.h>
#import <UIKit/UIKit.h>
#import "IMNotificationSettings.h"
#import "IMTimeUtil.h"
#import "IMLog.h"

@interface IMAlertPlayer ()
@property (nonatomic, assign, readwrite) int64_t lastSoundAtMs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *systemSoundIDs; // soundId → SystemSoundID（缓存，避免每次播放都重建）
@property (nonatomic, strong) UIImpactFeedbackGenerator *impactGenerator;
@end

@implementation IMAlertPlayer

+ (instancetype)shared {
    static IMAlertPlayer *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [IMAlertPlayer new]; });
    return value;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _systemSoundIDs = [NSMutableDictionary dictionary];
        _impactGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    }
    return self;
}

/// 解析 soundId → bundle 内 notif_<id>.caf 的 SystemSoundID（找不到文件时返回 0 并记警告日志，
/// 调用方据此不播——这是资源缺失场景，属"IO 失败必须有明确恢复分支"，此处的恢复即静默跳过不崩）。
- (SystemSoundID)systemSoundIDFor:(NSString *)soundID {
    NSNumber *cached = self.systemSoundIDs[soundID];
    if (cached) { return (SystemSoundID)cached.unsignedIntValue; }

    NSString *resourceName = [NSString stringWithFormat:@"notif_%@", soundID];
    // file-system-synchronized 组会把 Resources/Sounds/ 拍平到 bundle 根，但保险起见两种路径都试一次。
    NSURL *url = [NSBundle.mainBundle URLForResource:resourceName withExtension:@"caf"];
    if (!url) { url = [NSBundle.mainBundle URLForResource:resourceName withExtension:@"caf" subdirectory:@"Sounds"]; }
    if (!url) {
        IMLogWarnWithTag(IMLogTagApp, @"alert_sound_missing id=%@ (bundle 内找不到 %@.caf)", soundID, resourceName);
        return 0;
    }
    SystemSoundID systemSoundID = 0;
    OSStatus status = AudioServicesCreateSystemSoundID((__bridge CFURLRef)url, &systemSoundID);
    if (status != kAudioServicesNoError || systemSoundID == 0) {
        IMLogWarnWithTag(IMLogTagApp, @"alert_sound_create_failed id=%@ status=%d", soundID, (int)status);
        return 0;
    }
    self.systemSoundIDs[soundID] = @(systemSoundID);
    return systemSoundID;
}

- (void)playSoundNamed:(NSString *)soundID {
    NSString *normalized = IMNotificationSoundIDNormalize(soundID);
    if ([normalized isEqualToString:IMNotificationSoundIDNone]) { return; }
    SystemSoundID systemSoundID = [self systemSoundIDFor:normalized];
    if (systemSoundID == 0) { return; } // 资源缺失：静默跳过，不影响振动分支
    AudioServicesPlaySystemSound(systemSoundID); // 天然遵守静音键，不碰 AVAudioSession
    self.lastSoundAtMs = IMNowMillis();
}

- (void)vibrate {
    [self.impactGenerator prepare]; // 提前唤醒触感引擎，减小首次调用延迟
    [self.impactGenerator impactOccurred];
}

- (void)previewSoundNamed:(NSString *)soundID {
    NSString *normalized = IMNotificationSoundIDNormalize(soundID);
    if ([normalized isEqualToString:IMNotificationSoundIDNone]) { return; }
    SystemSoundID systemSoundID = [self systemSoundIDFor:normalized];
    if (systemSoundID == 0) { return; }
    AudioServicesPlaySystemSound(systemSoundID); // 试听不刷新 lastSoundAtMs：不占用实时消息的节流窗口
}

- (void)stopPreview {
    // 见 .h 注释：系统音效无停止 API，此方法为接口完整性与未来扩展预留，当前为 no-op。
}

@end
