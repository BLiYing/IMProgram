//  IMMediaDownloadCoordinator.h
//  收到的媒体/文件的**下载编排**（M4-7）：策略判定 → 门控态 → 点击路由 → 落地位置，一处实现、多处复用
//  （聊天页气泡/相册宫格、会话详情页 媒体/文件 Tab）。设计依据 `docs/design/sketches/DOWNLOAD_UX_SKETCH.html`。
//
//  三条铁律：① 全程不跳页（状态就地变化）；② **完成即止，绝不自动打开/播放**（Done 不给中心按钮，
//  由宿主呈现清晰图 / ▶ / 文件图标，用户主动点才打开）；③ 手动点击永远优先（可越过任何自动策略）。
//
//  两类介质的差异（对宿主透明）：
//   - **视频 / 文件** 走 `IMMediaDownloader`（HTTP Range 断点续传，五态齐全、可暂停续传、真进度）；
//     视频落地到 `IMOriginalVideoCache`——查看器认这份本地原件，下完点开即本地播放，不再流式拉远端。
//   - **图片** 走 `IMImageLoader` 自带的内存 + 磁盘缓存（无分片进度）→ 只有「未下载 / 就绪」两档，
//     点一下即解除门控、由 cell 正常加载。

#import <Foundation/Foundation.h>

@class IMMessageModel;
@class IMDownloadProgress;

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaDownloadCoordinator : NSObject

/// @param host     媒体 host（把 `/uploads/xxx` 拼成完整 URL）
/// @param myUserID 本人 uid（自己发的消息本地就有原件，永不门控）
/// @param isGroup  该会话是否群聊（自动下载策略按 单聊/群聊 分档）
- (instancetype)initWithHost:(NSString *)host myUserID:(NSString *)myUserID isGroup:(BOOL)isGroup;

/// 是否允许**按策略自动预取**（默认 YES）。会话详情页的媒体库设为 NO：
/// 浏览历史媒体不该顺手把几十条视频全拉下来——那里只反映状态，下载一律由用户点。
@property (nonatomic, assign) BOOL autoPrefetchEnabled;

/// **高频**进度/门控态更新（**主线程**）：下载中每片、开始/暂停/继续/失败/取消都走这里。
/// 宿主必须**就地更新可见 cell**（只改进度环/角标，**绝不 reloadRows**）——否则每片一次 reload
/// 会淹没主线程（卡死）并让自适应高度的图片/视频 cell 反复重算行高（列表上下跳变）。`state` 是当前态。
@property (nonatomic, copy, nullable) void (^onProgress)(IMMessageModel *message, IMDownloadProgress *state);

/// **低频**需要整条重配的变化（**主线程**）：仅「下载完成→就绪」与「图片解除门控→加载原图」两种，
/// 此时 cell 呈现的内容整体切换（清晰图 / ▶ / 文件图标），必须 reload 让 `cellForRow` 重跑。
@property (nonatomic, copy, nullable) void (^onStateChanged)(IMMessageModel *message);

/// 该消息当前的下载/门控态：**nil = 就绪**（已在本机，可直接显图/播放/打开）。
/// 非 nil 时宿主应显门控外观（↓ / 环形进度 / ↻），点击交给 `handleTapForMessage:`。
/// 副作用：未下载且策略判"应自动下载"时**异步**发起预取（每条只自动试一次）。
- (nullable IMDownloadProgress *)stateForMessage:(IMMessageModel *)message;

/// 门控态下的点击路由：未下载/失败 → 开始/重试；下载中 ↔ 暂停/继续；图片 → 解除门控（交给 cell 加载）。
- (void)handleTapForMessage:(IMMessageModel *)message;

/// 取消下载（✕）：掐断在飞请求、丢弃已下字节、回到"未下载"。无进行中任务时是空操作。
- (void)cancelDownloadForMessage:(IMMessageModel *)message;

/// 已下载到本机的本地文件（用于 QuickLook 打开 / 本地播放）；未下载返回 nil。
- (nullable NSURL *)localFileForMessage:(IMMessageModel *)message;

/// 页面回到前台（viewWillAppear）时调用：重新接管仍在跑的下载任务并就地刷新进度。
/// 一份共享下载任务只记一个回调对象，会被另一页展示时"抢走"；不在回前台时抢回，本页进度条会停在旧值。
/// 传本页相关的消息集合即可（内部只挑仍有活跃任务的处理，其余忽略）。
- (void)reattachActiveTasksForMessages:(NSArray<IMMessageModel *> *)messages;

@end

NS_ASSUME_NONNULL_END
