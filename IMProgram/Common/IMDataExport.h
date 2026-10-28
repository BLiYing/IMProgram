//  IMDataExport.h
//  「导出我的数据」纯逻辑（IMServer/docs/design/DATA_EXPORT_DESIGN.md §1 §2 §5）：任务对象解析、
//  页面状态映射、按钮可用性、冷却小时数、下载地址拼接。无 UI、无网络，配 IMDataExportTests。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 服务端任务状态（status 字符串）。未知字符串归 Unknown，页面按配置态处理。
typedef NS_ENUM(NSInteger, IMExportStatus) {
    IMExportStatusUnknown = 0,
    IMExportStatusQueued,
    IMExportStatusRunning,
    IMExportStatusDone,
    IMExportStatusFailed,
    IMExportStatusCanceled,
    IMExportStatusExpired,
};

/// 页面状态（设计 §1 的 4 态；第 4 态「冷却 / 失败」拆成两个枚举值，各自对应草图 ⑤ 的上 / 下半）。
typedef NS_ENUM(NSInteger, IMExportViewState) {
    IMExportViewStateConfig = 0,
    IMExportViewStateRunning,
    IMExportViewStateDone,
    IMExportViewStateCooldown,
    IMExportViewStateFailed,
};

/// 业务码：已有进行中任务 / 24 小时冷却内（errcode 表登记值，与 strings.json 的 err.200010 / err.200011 对应）。
FOUNDATION_EXPORT NSInteger const IMErrCodeExportBusy;
FOUNDATION_EXPORT NSInteger const IMErrCodeExportCooldown;
/// NSError.userInfo 键：200011 回包里的 retry_after_sec（NSNumber，秒）。
FOUNDATION_EXPORT NSString * const IMErrorRetryAfterSecKey;

@interface IMExportJob : NSObject
@property (nonatomic, copy, readonly) NSString *jobID;
@property (nonatomic, assign, readonly) IMExportStatus status;
@property (nonatomic, assign, readonly) NSInteger doneConvs;
@property (nonatomic, assign, readonly) NSInteger totalConvs;
@property (nonatomic, assign, readonly) int64_t sizeBytes;
@property (nonatomic, assign, readonly) NSInteger convCount;
@property (nonatomic, assign, readonly) NSInteger msgCount;
@property (nonatomic, strong, readonly, nullable) NSDate *finishedAt;
@property (nonatomic, strong, readonly, nullable) NSDate *expiresAt;

/// 解析任务对象；缺 id（含 `data:null` 回成的空字典）返回 nil。字段缺失 / 类型脏一律取零值，不崩。
+ (nullable instancetype)jobFromJSON:(nullable id)json;
@end

/// status 字符串 → 枚举。
FOUNDATION_EXPORT IMExportStatus IMExportStatusFromString(id _Nullable raw);

/// 任务（可为 nil = 从没导出过）→ 页面状态。queued/running → 进行中；done 且未过期 → 完成；failed → 失败；
/// 其余（无任务 / canceled / expired / 未知 / done 但已过 expiresAt）→ 配置态。冷却不由任务推出，见 IMExportViewStateCooldown。
FOUNDATION_EXPORT IMExportViewState IMExportViewStateForJob(IMExportJob *_Nullable job, NSDate *now);

/// 综合页面状态：任务状态优先（进行中 / 完成 / 未确认的失败）；任务态是配置态且冷却未到点 → 冷却态。
/// ackFailedID = 用户已点「重试」确认过的失败任务 id（该任务不再显示失败态，回配置态）。
FOUNDATION_EXPORT IMExportViewState IMExportResolveViewState(IMExportJob *_Nullable job, NSString *_Nullable ackFailedID,
                                                             NSDate *_Nullable cooldownUntil, NSDate *now);

/// 成功导出后的冷却时长（对齐 Web exportState.ts 的 EXPORT_COOLDOWN_MS）。
FOUNDATION_EXPORT NSTimeInterval const IMExportCooldownSec;

/// 有效冷却截止：本地冷却（200011 回包得来，未到点才算）与「done / expired 任务的 finished_at + 24h」取较晚者；
/// 都没有（或已到点）返回 nil。failed / canceled / 无 finished_at 不推冷却。重启 App 后靠它从 latest 任务还原冷却态。
FOUNDATION_EXPORT NSDate *_Nullable IMExportCooldownUntil(IMExportJob *_Nullable job, NSDate *_Nullable localUntil, NSDate *now);

/// 「开始导出」按钮可用：密码非空 + 至少勾一种格式 + 不在请求中 + 不在冷却。
FOUNDATION_EXPORT BOOL IMExportCanStart(NSString *_Nullable password, BOOL html, BOOL json, BOOL busy, BOOL cooling);

/// 冷却剩余秒数 → 展示小时数：向上取整，最少 1（不会显示「0 小时后」）。
FOUNDATION_EXPORT NSInteger IMExportCooldownHours(NSTimeInterval remainingSec);

/// 进度条比例 0..1；total <= 0 → 0；done 超出 total 夹到 1。
FOUNDATION_EXPORT float IMExportProgressFraction(NSInteger done, NSInteger total);

/// 下载地址：download_url 回的是相对路径（含 ?t=），客户端按当前服务器基址（含 http/https 方案）拼接；
/// 绝对地址只接受本服务器主机（IMServerEndpoint isOwnHost:forAbsoluteURL:），外域一律返回 nil；空串 / 非法返回 nil。
FOUNDATION_EXPORT NSURL *_Nullable IMExportDownloadURL(NSString *_Nullable raw, NSString *_Nullable host);

/// 下载 HTTP 失败码是否表示「链接已失效 / 文件已不在」（应提示已过期并刷新任务）。
/// 服务端对 token 无效 / 已用 / 过期 / 文件被清理一律回 TokenInvalid(100101) → HTTP 401（不是 403/404/410），
/// 所以 401 必须算失效；403/404/410 兜底网关或旧版行为。
FOUNDATION_EXPORT BOOL IMExportDownloadFailureIsGone(NSInteger httpStatus);

/// 轮询 / 刷新回包是否还应落地：发起时的 epoch 与当前一致才用。用户本地发起（开始导出）会推进 epoch，
/// 之前已在途的 latest 回包是旧状态，落地会把进行中页闪回配置态并停掉轮询。
FOUNDATION_EXPORT BOOL IMExportShouldApplyLatest(NSUInteger fetchEpoch, NSUInteger currentEpoch);

/// 完成态副标题「128 MB · 12 个会话 · 8431 条消息」。
FOUNDATION_EXPORT NSString *IMExportSummaryText(IMExportJob *job);

/// 「文件将于 10月27日 14:30 删除。」；无 expiresAt 返回 nil。
FOUNDATION_EXPORT NSString *_Nullable IMExportExpiresText(IMExportJob *job);

/// 落到临时目录的文件名 im-export-yyyyMMdd.zip（日期取任务完成时刻，缺省取 now）。
FOUNDATION_EXPORT NSString *IMExportFileName(IMExportJob *_Nullable job, NSDate *now);

NS_ASSUME_NONNULL_END
