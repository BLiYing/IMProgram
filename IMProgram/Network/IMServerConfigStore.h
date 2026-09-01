//
//  IMServerConfigStore.h
//  **部署级**能力/配额的客户端缓存：GET /api/v1/server-config。
//
//  与 IMDownloadSettingsStore（账号级、随账号走、多端同步、有 capabilities_update 回环）不是一回事：
//  这里是**部署级**——同一部署下所有账号一致、本次会话内不会变，登录后拉一次即可，没有推送回环。
//
//  为什么必须有它：客户端**不得硬编码群成员上限**。上限是部署配置（后端 `-max-group-members`），
//  端上写死会与服务端实际拒绝的口径对不上——Web 端就出过这个（端上 500、后端已放到 2000，
//  用户选到第 501 个人被端上误拦）。iOS 此前压根没接这个接口。
//
//  `supergroupEnabled` 决定「升级为大群」这类入口显不显示：本部署没开的话，
//  提示用户去联系管理员也办不成（后端直接拒 upgrade-super），那个入口就是死的。
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMServerConfigStore : NSObject

+ (instancetype)shared;

/// 是否已成功拉到过。**为 NO 时上面几个值全无意义**——调用方应按"未知"处理，
/// 而不是套用某个默认值：宁可少显示一个提示，也不要按猜测的上限误报"群已满"。
@property (nonatomic, assign, readonly) BOOL loaded;

/// 标准群成员上限（部署配置）。
@property (nonatomic, assign, readonly) NSInteger maxGroupMembers;
/// 本部署是否提供超级群。
@property (nonatomic, assign, readonly) BOOL supergroupEnabled;
/// 超级群成员上限；supergroupEnabled=NO 时无意义。
@property (nonatomic, assign, readonly) NSInteger maxSupergroupMembers;

/// 开始观察连接状态并首次拉取（App 启动时调一次，幂等）。
/// 与 IMDownloadSettingsStore 同套路：**只认 Connected 那一帧**——弱网频繁重连时
/// connecting/disconnected 都发请求会一秒几发。
- (void)start;

/// 拉一次（登录后/进前台调用，幂等）。无 token 时静默跳过；失败保持 loaded=NO，不写入猜测值。
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
