//  IMMediaDownloadCoordinator.m

#import "IMMediaDownloadCoordinator.h"
#import "IMMessageModel.h"
#import "IMMediaUtil.h"             // IMMediaFullURL
#import "IMMediaDownloader.h"
#import "IMOriginalVideoCache.h"
#import "IMImageLoader.h"
#import "IMPendingMediaStore.h"
#import "IMDownloadProgress.h"
#import "IMDownloadPolicy.h"        // IMShouldAutoDownload / IMNetworkType
#import "IMDownloadSettingsStore.h"
#import "IMNetworkMonitor.h"
#import "IMLog.h"

@implementation IMMediaDownloadCoordinator {
    NSString *_host;
    NSString *_myUserID;
    BOOL _isGroup;
    /// key=content。仅存**下载器管不到**的态：失败（任务已注销）与刚点下的乐观下载中。
    NSMutableDictionary<NSString *, IMDownloadProgress *> *_states;
    NSMutableSet<NSString *> *_autoTried;  ///< 已自动试过的 content（每条只自动预取一次）
    NSMutableSet<NSString *> *_requested;  ///< 用户已点 ↓ 的图片 content（解除门控，铁律③手动优先）
}

- (instancetype)initWithHost:(NSString *)host myUserID:(NSString *)myUserID isGroup:(BOOL)isGroup {
    self = [super init];
    if (self) {
        _host = [host copy];
        _myUserID = [myUserID copy];
        _isGroup = isGroup;
        _states = [NSMutableDictionary dictionary];
        _autoTried = [NSMutableSet set];
        _requested = [NSMutableSet set];
        _autoPrefetchEnabled = YES;
    }
    return self;
}

#pragma mark - 分类

/// key 用 content（形如 `/uploads/<uuid>__name`，uuid 保证唯一）：下载器任务与本地状态表共用同一把键，
/// 因此**同一份文件在多张卡片（转发/重复）之间天然共享一个下载态与进度**（草图 §08-04 去重）。
- (NSString *)keyForMessage:(IMMessageModel *)m { return m.content ?: @""; }

- (NSString *)fullURLForMessage:(IMMessageModel *)m { return IMMediaFullURL(m.content, _host); }

/// 走分片下载器的类型（视频/文件）；图片走 IMImageLoader。
- (BOOL)usesDownloaderForMessage:(IMMessageModel *)m {
    return [m.contentType isEqualToString:@"video"] || [m.contentType isEqualToString:@"file"];
}

/// 这条消息是否**根本不进入**下载体系（自己发的 / 本地待发 / 撤回 / 非媒体类型 / 无地址）。
- (BOOL)isOutOfScope:(IMMessageModel *)m {
    if (!m || m.content.length == 0 || m.recalledAt > 0) { return YES; }
    if (_myUserID.length > 0 && [m.from isEqualToString:_myUserID]) { return YES; } // 自己发的：本地就有原件
    if ([IMPendingMediaStore isLocalRef:m.content]) { return YES; }                 // 本地待发引用，不是网络地址
    NSString *t = m.contentType;
    return !([t isEqualToString:@"image"] || [t isEqualToString:@"video"] || [t isEqualToString:@"file"]);
}

/// 日志用的会话上下文（跨端对账靠 conv_id/conv_seq，见 docs/LOGGING.md §2/§3）。
/// key 用 content（含服务端 uuid + 原文件名）——属 §5 允许的“文件名等元数据”，不含正文字节。
- (NSString *)logContextForMessage:(IMMessageModel *)m {
    return [NSString stringWithFormat:@"key=%@ conv_id=%@ conv_seq=%lld kind=%@ size_bytes=%lld",
            m.content ?: @"-", m.convID ?: @"-", m.convSeq, m.contentType ?: @"-", m.fileSize];
}

#pragma mark - 落地位置 / 是否已在本机

- (nullable NSURL *)destinationForMessage:(IMMessageModel *)m {
    if ([m.contentType isEqualToString:@"video"]) {
        NSString *full = [self fullURLForMessage:m];
        return full.length > 0 ? [IMOriginalVideoCache cacheURLForFullURL:full] : nil;
    }
    return [IMMediaDownloader cachedFileURLForContent:m.content];
}

- (nullable NSURL *)localFileForMessage:(IMMessageModel *)m {
    if ([m.contentType isEqualToString:@"image"]) { return nil; } // 图片由 IMImageLoader 自管缓存，无外部文件语义
    NSURL *url = [self destinationForMessage:m];
    if (!url || ![NSFileManager.defaultManager fileExistsAtPath:url.path]) { return nil; }
    return url;
}

/// 本机是否已有原件。清缓存删掉文件后此处即回 NO，卡片自动退回"未下载"（草图 §08-03）。
- (BOOL)isCached:(IMMessageModel *)m {
    if ([m.contentType isEqualToString:@"image"]) {
        return [[IMImageLoader shared] hasCachedImageForURL:[self fullURLForMessage:m]];
    }
    return [self localFileForMessage:m] != nil;
}

#pragma mark - 门控态

- (nullable IMDownloadProgress *)stateForMessage:(IMMessageModel *)m {
    if ([self isOutOfScope:m]) { return nil; }
    if ([self isCached:m]) { return nil; }
    NSString *key = [self keyForMessage:m];

    if (![self usesDownloaderForMessage:m]) {           // 图片：只有"未下载 / 就绪"两档
        if ([_requested containsObject:key]) { return nil; }
        if ([self shouldAutoDownload:m]) { return nil; } // 策略放行 → 直接由 cell 正常加载
        return [IMDownloadProgress notStartedWithTotalBytes:m.fileSize];
    }

    // 界面重建后仍在跑的下载：重新接管（补挂回调）+ 反映任务真实态，
    // 否则会误显"未下载"、用户点一下反而把活跃下载暂停了。
    IMMediaDownloadTask *task = [[IMMediaDownloader shared] taskForKey:key];
    if (task) {
        [self attachHandlersToTask:task message:m];
        int64_t total = task.totalBytes > 0 ? task.totalBytes : m.fileSize;
        IMDownloadProgress *live = task.paused
            ? [IMDownloadProgress pausedWithReceived:task.receivedBytes total:total]
            : [IMDownloadProgress downloadingWithReceived:task.receivedBytes total:total pausable:YES];
        _states[key] = live;
        return live;
    }
    IMDownloadProgress *kept = _states[key]; // 失败态（任务已注销，但要留 ↻ 给用户）
    if (kept) { return kept; }
    // 未下载：按策略**异步**自动预取（每条只试一次；异步是为了不在 cellForRow 里递归 reload）。
    if (_autoPrefetchEnabled && ![_autoTried containsObject:key] && [self shouldAutoDownload:m]) {
        [_autoTried addObject:key];
        // **只在真正触发的那一次记**：stateForMessage: 每次 cellForRow 都会走，滚动时打日志会刷屏。
        IMLogWithTag(IMLogTagMedia, @"download_auto_prefetch %@ network=%ld is_group=%d",
                     [self logContextForMessage:m], (long)[IMNetworkMonitor shared].currentType, _isGroup);
        __weak typeof(self) ws = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [ws startDownloadForMessage:m]; });
    }
    return [IMDownloadProgress notStartedWithTotalBytes:m.fileSize];
}

- (BOOL)shouldAutoDownload:(IMMessageModel *)m {
    return IMShouldAutoDownload([IMDownloadSettingsStore shared].settings, m.contentType, m.fileSize,
                                _isGroup, [IMNetworkMonitor shared].currentType);
}

#pragma mark - 点击路由

- (void)handleTapForMessage:(IMMessageModel *)m {
    if ([self isOutOfScope:m]) { return; }
    NSString *key = [self keyForMessage:m];
    if (![self usesDownloaderForMessage:m]) { // 图片：记为已请求 → 解除门控，宿主重载该行即加载原图
        if (![_requested containsObject:key]) {
            IMLogDebugWithTag(IMLogTagMedia, @"download_image_gate_released %@", [self logContextForMessage:m]);
        }
        [_requested addObject:key];
        [self notifyChanged:m];
        return;
    }
    if (_states[key].expired) {
        IMLogDebugWithTag(IMLogTagMedia, @"download_tap_ignored_expired %@", [self logContextForMessage:m]);
        return; // 服务端已清理：重试没有意义，点了也不动
    }
    IMMediaDownloadTask *task = [[IMMediaDownloader shared] taskForKey:key];
    if (task) {
        int64_t total = task.totalBytes > 0 ? task.totalBytes : m.fileSize;
        if (task.paused) {
            [task resume];
            _states[key] = [IMDownloadProgress downloadingWithReceived:task.receivedBytes total:total pausable:YES];
        } else {
            [task pause];
            _states[key] = [IMDownloadProgress pausedWithReceived:task.receivedBytes total:total];
        }
        [self notifyProgress:m]; // 暂停/继续只切换环+图标，就地更新即可，不必 reload
        return;
    }
    [self startDownloadForMessage:m];
}

- (void)cancelDownloadForMessage:(IMMessageModel *)m {
    if ([self isOutOfScope:m]) { return; }
    NSString *key = [self keyForMessage:m];
    IMMediaDownloadTask *task = [[IMMediaDownloader shared] taskForKey:key];
    if (!task) { return; }
    IMLogWarnWithTag(IMLogTagMedia, @"download_cancelled_by_user %@ received=%lld",
                     [self logContextForMessage:m], task.receivedBytes);
    [task cancel];                          // 丢弃 .part、注销任务、不再回调
    [_states removeObjectForKey:key];       // 回到"未下载"
    [_autoTried addObject:key];             // 用户主动取消过 → 别再被策略自动拉起来（铁律③手动优先）
    // 取消是「下载中→未下载」的整条状态切换（不是同态进度更新）：**必须 reload** 让 cellForRow 重跑
    // stateForMessage 重新合成 notStarted。若走 notifyProgress，_states 已删空 → onProgress 收到 nil，
    // 文件行会把 nil 当「已下载」渲染（渲染出文件图标 + "已下载"），错得离谱。
    [self notifyChanged:m];
}

/// 启动/重试：置乐观"下载中"态 + 挂回调。
- (void)startDownloadForMessage:(IMMessageModel *)m {
    NSString *key = [self keyForMessage:m];
    NSURL *remote = [NSURL URLWithString:[self fullURLForMessage:m]];
    NSURL *dest = [self destinationForMessage:m];
    if (key.length == 0 || !remote || !dest) {
        IMLogWarnWithTag(IMLogTagMedia, @"download_start_skipped_bad_target %@", [self logContextForMessage:m]);
        return;
    }
    // reason 区分自动预取与用户手点：排查"没自动下"与"点了没反应"是两条完全不同的线。
    IMLogWithTag(IMLogTagMedia, @"download_start %@ reason=%@ retry=%d", [self logContextForMessage:m],
                 [_autoTried containsObject:key] ? @"auto" : @"manual", _states[key].phase == IMDownloadPhaseFailed);
    _states[key] = [IMDownloadProgress downloadingWithReceived:0 total:m.fileSize pausable:YES];
    // 首次点下载：未下载→下载中只是 ↓ 换成进度环（门控态不变、行高不变）→ 就地更新，**不 reload**。
    // 这是「第一次点下载最明显的跳变/卡死」的根因修复：原先每次都 reloadRows。
    [self notifyProgress:m];
    IMMediaDownloadTask *task = [[IMMediaDownloader shared] downloadURL:remote toDestination:dest key:key];
    [self attachHandlersToTask:task message:m];
}

/// 挂进度/完成回调（弱引用 self：宿主销毁后回调自动作废）。界面重建重新接管时也用它。
- (void)attachHandlersToTask:(IMMediaDownloadTask *)task message:(IMMessageModel *)m {
    NSString *key = [self keyForMessage:m];
    int64_t declared = m.fileSize;
    __weak typeof(self) ws = self;
    task.progressHandler = ^(int64_t received, int64_t total) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self->_states[key] = [IMDownloadProgress downloadingWithReceived:received
                                                                  total:(total > 0 ? total : declared)
                                                               pausable:YES];
        [self notifyProgress:m]; // **高频**：每片一次，务必就地更新（reload 会卡死主线程 + 图片行跳变）
    };
    task.completionHandler = ^(NSURL *localURL, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        if (error) {
            // 失败分因（草图 §08-05）：服务端已清理（404/410）= 终态"文件已失效"、不给重试；其余=网络错，可 ↻。
            BOOL expired = [error.domain isEqualToString:@"IMMediaDownloaderErrorDomain"]
                && (error.code == 404 || error.code == 410);
            // 只记**业务分类**（可重试 vs 终态失效）；传输层事实（字节/耗时/HTTP 码）由 IMMediaDownloader 记，不重复。
            IMLogWarnWithTag(IMLogTagMedia, @"download_result_failed %@ expired=%d error_code=%ld",
                             [self logContextForMessage:m], expired, (long)error.code);
            self->_states[key] = expired
                ? [IMDownloadProgress expiredWithTotalBytes:declared]
                : [IMDownloadProgress failedWithReceived:0 total:declared];
            [self notifyProgress:m]; // 失败：环消失、图标变 ↻，门控态仍在 → 就地更新
        } else {
            [self->_states removeObjectForKey:key]; // 已落地 → 下次查询 isCached 即"就绪"
            [self notifyChanged:m]; // 就绪：cell 内容整体切换（清晰图/▶/文件图标）→ 必须 reload 重配
        }
    };
}

/// 高频/门控内更新：优先就地（onProgress），未接则回落 reload（onStateChanged）。
- (void)notifyProgress:(IMMessageModel *)m {
    if (self.onProgress) { self.onProgress(m, _states[[self keyForMessage:m]]); return; }
    if (self.onStateChanged) { self.onStateChanged(m); }
}

/// 低频整条重配：图片解除门控 / 下载完成。
- (void)notifyChanged:(IMMessageModel *)m {
    if (self.onStateChanged) { self.onStateChanged(m); }
}

@end
