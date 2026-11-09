//
//  IMServerConfigStore.h
//  **部署级**能力/配额的客户端缓存：GET /api/v1/server-config。
//
//  与 IMDownloadSettingsStore（账号级、随账号走、多端同步、有 capabilities_update 回环）不是一回事：
//  这里是**部署级**——同一部署下所有账号一致、没有推送回环。
//
//  **运行中会变**（2026-11-08，后台「系统设置」S2）：撤回 / 编辑时间窗、转发上限、群名 / 公告长度
//  由管理员在后台随时改，服务端保存即按新值校验。所以不能「登录后拉一次」——**每次连上（含重连）
//  与回到前台都重拉**（PROTOCOL `GET /api/v1/server-config` 那一行）。两个时机常在同一秒先后到
//  （回前台 → 重连 → Connected），由「在途不重发 + 刚拉到的几秒内不再拉」合并成一次。
//  端上拿的值可能落后一次拉取：服务端仍以自己的当前值为准，超窗照常回 300008/300007，按码提示即可。
//
//  为什么必须有它：客户端**不得硬编码群成员上限**。上限是部署配置（后端 `-max-group-members`），
//  端上写死会与服务端实际拒绝的口径对不上——Web 端就出过这个（端上 500、后端已放到 2000，
//  用户选到第 501 个人被端上误拦）。
//
//  `supergroupEnabled` 决定「升级为大群」这类入口显不显示：本部署没开的话，
//  提示用户去联系管理员也办不成（后端直接拒 upgrade-super），那个入口就是死的。
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 拉到配置且**内容有变化**（含首次拉到）时在主线程发出；依赖它的页面（群资料满员告知）据此重绘。
FOUNDATION_EXPORT NSNotificationName const IMServerConfigDidLoadNotification;

/// 老服务端不下发 S2 六个字段时的内置默认（与 PROTOCOL / 服务端 handlers_serverconfig.go 同值）。
/// **字段缺失 ≠ 0**：缺失走这里；0 只在两个时间窗上表示「不限」。
FOUNDATION_EXPORT const NSInteger IMServerConfigDefaultRecallWindowSec;      ///< 120（2 分钟）
FOUNDATION_EXPORT const NSInteger IMServerConfigDefaultEditWindowSec;        ///< 0（不限）
FOUNDATION_EXPORT const NSInteger IMServerConfigDefaultForwardMaxTargets;    ///< 9
FOUNDATION_EXPORT const NSInteger IMServerConfigDefaultMergeForwardMax;      ///< 100
FOUNDATION_EXPORT const NSInteger IMServerConfigDefaultGroupNameMaxLen;      ///< 30
FOUNDATION_EXPORT const NSInteger IMServerConfigDefaultAnnouncementMaxLen;   ///< 500
/// S3a 上传策略缺失时的默认：单文件上限 2 GiB（图片 / 视频 / 文件；语音另有服务端固定 16 MB，不随它变）。
FOUNDATION_EXPORT const long long IMServerConfigDefaultUploadMaxFileBytes;   ///< 2147483648
/// 多选一次最多勾几条（聊天页多选闸，转发 / 收藏 / 举报共用）。合并转发上限不能超过它。
FOUNDATION_EXPORT const NSInteger IMServerConfigMultiSelectMax;              ///< 100

/// 时间窗判定（纯函数）：windowSec <= 0 = 不限；否则 nowMs - sentAtMs <= windowSec 秒才算窗内。
/// 与原 `kIMRecallWindowMs` 判据同口径（含边界）。
FOUNDATION_EXPORT BOOL IMServerConfigWithinWindow(int64_t sentAtMs, int64_t nowMs, NSInteger windowSec);

@interface IMServerConfigStore : NSObject

+ (instancetype)shared;

/// 是否已成功拉到过。**为 NO 时三个群成员上限值全无意义**——调用方应按"未知"处理，
/// 而不是套用某个默认值：宁可少显示一个提示，也不要按猜测的上限误报"群已满"。
/// （下面 S2 六项不受此约束：没拉到时就是内置默认，恒可直接用。）
@property (nonatomic, assign, readonly) BOOL loaded;

/// 标准群成员上限（部署配置）。
@property (nonatomic, assign, readonly) NSInteger maxGroupMembers;
/// 本部署是否提供超级群。
@property (nonatomic, assign, readonly) BOOL supergroupEnabled;
/// 超级群成员上限；supergroupEnabled=NO 时无意义。
@property (nonatomic, assign, readonly) NSInteger maxSupergroupMembers;

#pragma mark S2（运行中可变；恒有值：缺失 / 非法 → 内置默认）

/// 撤回时间窗（秒），**0 = 不限**。
@property (nonatomic, assign, readonly) NSInteger recallWindowSec;
/// 编辑时间窗（秒），**0 = 不限**。
@property (nonatomic, assign, readonly) NSInteger editWindowSec;
/// 一次转发最多选几个会话（≥1）。
@property (nonatomic, assign, readonly) NSInteger forwardMaxTargets;
/// 一次合并转发最多几条：已按 min(多选上限 100, 下发值) 收口（≥1）。
@property (nonatomic, assign, readonly) NSInteger mergeForwardMax;
/// 群名长度上限（Unicode 码点，≥1）。
@property (nonatomic, assign, readonly) NSInteger groupNameMaxLen;
/// 群公告长度上限（Unicode 码点，≥1）。
@property (nonatomic, assign, readonly) NSInteger groupAnnouncementMaxLen;

#pragma mark S3a 上传策略（运行中可变；恒有值：缺失 → 允许 / 2 GiB / 无禁止）

/// 管理员总开关：NO = 聊天里不许发图片 / 视频 / 文件 / 语音（服务端回 500003）。头像不受影响。
@property (nonatomic, assign, readonly) BOOL uploadEnabled;
/// 图片 / 视频 / 文件单文件上限（字节，恒 > 0；缺失 / <=0 → 2 GiB）。语音不受它约束。
@property (nonatomic, assign, readonly) long long uploadMaxFileBytes;
/// 此刻被禁止的扩展名（小写带点，如 ".exe"；空 = 无禁止）。不作用于语音。
@property (nonatomic, copy, readonly) NSArray<NSString *> *uploadBlockedExtensions;

/// 这条消息（发出时刻 sentAtMs）现在还能不能撤回 / 编辑——只决定菜单显隐，服务端为准。
- (BOOL)canRecallMessageSentAt:(int64_t)sentAtMs nowMs:(int64_t)nowMs;
- (BOOL)canEditMessageSentAt:(int64_t)sentAtMs nowMs:(int64_t)nowMs;

/// 开始观察连接状态与回前台并首次拉取（App 启动时调一次，幂等）。
/// 连接状态**只认 Connected 那一帧**——弱网频繁重连时 connecting/disconnected 都发请求会一秒几发。
- (void)start;

/// 拉一次（幂等）。无 token 时静默跳过；请求在途或刚成功拉过（几秒内）也跳过，
/// 用来合并「回前台」与随后的「Connected」。失败保留上一次的值（首次失败则 loaded=NO、S2 项为默认）。
- (void)refresh;

/// 解析 `data` 并写入（refresh 成功后调用；单测直接喂字典）。返回值是否与写入前不同。
- (BOOL)applyServerConfig:(NSDictionary *)data;

/// refresh 的合并判定（纯函数，便于单测）：在途不发；上次成功距今 < minIntervalMs 不发。
/// lastSuccessMs <= 0 表示从未成功。
+ (BOOL)shouldFetchWithInFlight:(BOOL)inFlight lastSuccessMs:(int64_t)lastSuccessMs
                          nowMs:(int64_t)nowMs minIntervalMs:(int64_t)minIntervalMs;

@end

NS_ASSUME_NONNULL_END
