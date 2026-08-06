//  IMDownloadSettingsStore.h
//  账号级自动下载策略的客户端缓存（M4-7）：拉取 GET /api/v1/download-settings，
//  收到 capabilities_update 帧后重拉，做多端同步。settings 始终有值（未拉到时为出厂默认）。

#import <Foundation/Foundation.h>
#import "IMDownloadSettings.h"

NS_ASSUME_NONNULL_BEGIN

/// 策略更新后广播（设置页/聊天页可据此刷新决策）。
extern NSString * const IMDownloadSettingsDidChangeNotification;

@interface IMDownloadSettingsStore : NSObject

+ (instancetype)shared;

/// 当前生效策略（拉到前为默认，绝不为 nil）。仅主线程读。
@property (nonatomic, strong, readonly) IMDownloadSettings *settings;

/// 开始观察 capabilities_update 并首次拉取（App 启动/登录后调一次，幂等）。
- (void)start;

/// 手动重拉（进前台/设置页打开时）。无 token 时静默跳过。
- (void)refresh;

/// 设置页 PUT/reset 成功后即时应用新值（不必等 capabilities_update 回环），并广播变更。
- (void)applySettings:(IMDownloadSettings *)settings;

/// 保存（乐观本地应用 + PUT；失败以服务端为准重拉回滚）。设置页改任一控件即调。
- (void)saveSettings:(IMDownloadSettings *)settings;

/// 恢复出厂默认（POST reset；失败回滚重拉）。
- (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
