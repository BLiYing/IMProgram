//
//  IMServerConfigStore.m
//

#import "IMServerConfigStore.h"

#import <UIKit/UIKit.h>

#import "IMHTTPService.h"
#import "IMSocketManager.h"
#import "IMTimeUtil.h"
#import "IMLog.h"

NSNotificationName const IMServerConfigDidLoadNotification = @"IMServerConfigDidLoadNotification";

const NSInteger IMServerConfigDefaultRecallWindowSec = 120;
const NSInteger IMServerConfigDefaultEditWindowSec = 0;
const NSInteger IMServerConfigDefaultForwardMaxTargets = 9;
const NSInteger IMServerConfigDefaultMergeForwardMax = 100;
const NSInteger IMServerConfigDefaultGroupNameMaxLen = 30;
const NSInteger IMServerConfigDefaultAnnouncementMaxLen = 500;
const NSInteger IMServerConfigMultiSelectMax = 100;
const long long IMServerConfigDefaultUploadMaxFileBytes = 2048LL * 1024 * 1024;

/// 回前台与随后的 Connected 通常在一两秒内先后到；这个窗口内刚成功拉过就不再拉。
static const int64_t kIMServerConfigMinRefreshIntervalMs = 5000;

BOOL IMServerConfigWithinWindow(int64_t sentAtMs, int64_t nowMs, NSInteger windowSec) {
    if (windowSec <= 0) { return YES; } // 0 = 不限
    return (nowMs - sentAtMs) <= (int64_t)windowSec * 1000;
}

/// 取一个整数字段：**缺失 / 非数字 / 小于 minValue → fallback**。
/// 区分「缺失」与「0」就靠这里：缺失走 fallback，0 只有在 minValue<=0 时才被当成有效值。
static NSInteger IMConfigInt(NSDictionary *data, NSString *key, NSInteger minValue, NSInteger fallback) {
    id v = data[key];
    if (![v isKindOfClass:NSNumber.class]) { return fallback; }
    NSInteger n = [v integerValue];
    return n < minValue ? fallback : n;
}

/// 布尔字段：缺失 / null / 非数字 → fallback（upload_enabled 缺失 = 老服务端 = 允许，不能当 NO）。
static BOOL IMConfigBool(NSDictionary *data, NSString *key, BOOL fallback) {
    id v = data[key];
    return [v isKindOfClass:NSNumber.class] ? [v boolValue] : fallback;
}

/// 扩展名列表：只收字符串，统一小写、补前导点、去空去重（保持下发顺序）。缺失 / null / 非数组 → 空。
static NSArray<NSString *> *IMConfigExtList(NSDictionary *data, NSString *key) {
    id v = data[key];
    if (![v isKindOfClass:NSArray.class]) { return @[]; }
    NSMutableOrderedSet<NSString *> *out = [NSMutableOrderedSet orderedSet];
    for (id e in (NSArray *)v) {
        if (![e isKindOfClass:NSString.class]) { continue; }
        NSString *ext = [[(NSString *)e stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lowercaseString];
        if (ext.length == 0 || [ext isEqualToString:@"."]) { continue; }
        if (![ext hasPrefix:@"."]) { ext = [@"." stringByAppendingString:ext]; }
        [out addObject:ext];
    }
    return out.array;
}

@implementation IMServerConfigStore {
    BOOL _started;
    BOOL _inFlight;
    int64_t _lastSuccessMs;
}

+ (instancetype)shared {
    static IMServerConfigStore *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [IMServerConfigStore new]; });
    return inst;
}

- (instancetype)init {
    if ((self = [super init])) {
        _recallWindowSec = IMServerConfigDefaultRecallWindowSec;
        _editWindowSec = IMServerConfigDefaultEditWindowSec;
        _forwardMaxTargets = IMServerConfigDefaultForwardMaxTargets;
        _mergeForwardMax = IMServerConfigDefaultMergeForwardMax;
        _groupNameMaxLen = IMServerConfigDefaultGroupNameMaxLen;
        _groupAnnouncementMaxLen = IMServerConfigDefaultAnnouncementMaxLen;
        _uploadEnabled = YES;
        _uploadMaxFileBytes = IMServerConfigDefaultUploadMaxFileBytes;
        _uploadBlockedExtensions = @[];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)start {
    if (_started) { return; }
    _started = YES;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(onSocketStateChanged:) name:IMSocketDidChangeStateNotification object:nil];
    [nc addObserver:self selector:@selector(onWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [self refresh]; // 冷启动已有会话时 token 可能已就绪
}

- (void)onSocketStateChanged:(NSNotification *)note {
    // 每次连上（含重连）都拉：S2 各项运行中可被管理员改。只认 Connected 这一帧。
    if ([note.userInfo[@"state"] integerValue] == IMSocketStateConnected) { [self refresh]; }
}

- (void)onWillEnterForeground:(NSNotification *)note {
    [self refresh];
}

+ (BOOL)shouldFetchWithInFlight:(BOOL)inFlight lastSuccessMs:(int64_t)lastSuccessMs
                          nowMs:(int64_t)nowMs minIntervalMs:(int64_t)minIntervalMs {
    if (inFlight) { return NO; }
    if (lastSuccessMs > 0 && nowMs - lastSuccessMs >= 0 && nowMs - lastSuccessMs < minIntervalMs) { return NO; }
    return YES;
}

- (void)refresh {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; } // 还没登录，等下次
    if (![IMServerConfigStore shouldFetchWithInFlight:_inFlight lastSuccessMs:_lastSuccessMs
                                                nowMs:IMNowMillis() minIntervalMs:kIMServerConfigMinRefreshIntervalMs]) {
        return;
    }
    _inFlight = YES;
    __weak typeof(self) weakSelf = self;
    [IMHTTPService.sharedService serverConfigWithToken:token completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        self->_inFlight = NO;
        if (error || !data) {
            // **失败不写默认值**：保留上一次的值；从没拉到过则 loaded 保持 NO，依赖群上限的 UI 当"未知"不显示。
            IMLogWarnWithTag(IMLogTagHTTP, @"server_config_fetch_failed error=%@", error.localizedDescription ?: @"");
            return;
        }
        self->_lastSuccessMs = IMNowMillis();
        if ([self applyServerConfig:data]) {
            [NSNotificationCenter.defaultCenter postNotificationName:IMServerConfigDidLoadNotification object:nil];
        }
    }];
}

- (BOOL)applyServerConfig:(NSDictionary *)data {
    // 老三项：缺失 / null / 非数字 → 0 / NO，与原 integerValue 读缺失键的结果一致（不引入新默认；这三项本就只在 loaded 后有意义）。
    // 不能直接 integerValue：JSON null 是 NSNull，没有这个方法，会 unrecognized selector 崩。
    NSInteger maxMembers = IMConfigInt(data, @"max_group_members", NSIntegerMin, 0);
    BOOL superEnabled = IMConfigInt(data, @"supergroup_enabled", NSIntegerMin, 0) != 0;
    NSInteger maxSuper = IMConfigInt(data, @"max_supergroup_members", NSIntegerMin, 0);
    // 两个时间窗：0 合法（= 不限），负数当非法 → 默认。其余四项服务端范围下限都是 1，0/负数 → 默认。
    NSInteger recall = IMConfigInt(data, @"recall_window_sec", 0, IMServerConfigDefaultRecallWindowSec);
    NSInteger edit = IMConfigInt(data, @"edit_window_sec", 0, IMServerConfigDefaultEditWindowSec);
    NSInteger forward = IMConfigInt(data, @"forward_max_targets", 1, IMServerConfigDefaultForwardMaxTargets);
    NSInteger merge = MIN(IMServerConfigMultiSelectMax,
                          IMConfigInt(data, @"merge_forward_max", 1, IMServerConfigDefaultMergeForwardMax));
    NSInteger nameMax = IMConfigInt(data, @"group_name_max_len", 1, IMServerConfigDefaultGroupNameMaxLen);
    NSInteger annMax = IMConfigInt(data, @"group_announcement_max_len", 1, IMServerConfigDefaultAnnouncementMaxLen);
    // S3a 上传策略：缺失（老服务端）= 允许 / 2 GiB / 无禁止；上限 <=0 当非法 → 默认。
    BOOL uploadEnabled = IMConfigBool(data, @"upload_enabled", YES);
    id rawMax = data[@"upload_max_file_bytes"];
    long long uploadMax = [rawMax isKindOfClass:NSNumber.class] ? [rawMax longLongValue] : 0;
    if (uploadMax <= 0) { uploadMax = IMServerConfigDefaultUploadMaxFileBytes; }
    NSArray<NSString *> *blocked = IMConfigExtList(data, @"upload_blocked_extensions");

    BOOL changed = !_loaded || _maxGroupMembers != maxMembers || _supergroupEnabled != superEnabled
        || _maxSupergroupMembers != maxSuper || _recallWindowSec != recall || _editWindowSec != edit
        || _forwardMaxTargets != forward || _mergeForwardMax != merge
        || _groupNameMaxLen != nameMax || _groupAnnouncementMaxLen != annMax
        || _uploadEnabled != uploadEnabled || _uploadMaxFileBytes != uploadMax
        || ![_uploadBlockedExtensions isEqualToArray:blocked];

    _maxGroupMembers = maxMembers;
    _supergroupEnabled = superEnabled;
    _maxSupergroupMembers = maxSuper;
    _recallWindowSec = recall;
    _editWindowSec = edit;
    _forwardMaxTargets = forward;
    _mergeForwardMax = merge;
    _groupNameMaxLen = nameMax;
    _groupAnnouncementMaxLen = annMax;
    _uploadEnabled = uploadEnabled;
    _uploadMaxFileBytes = uploadMax;
    _uploadBlockedExtensions = [blocked copy];
    _loaded = YES;
    if (changed) {
        IMLogWithTag(IMLogTagHTTP, @"server_config_applied recall_sec=%ld edit_sec=%ld forward_max=%ld merge_max=%ld name_max=%ld ann_max=%ld upload_enabled=%d upload_max_bytes=%lld upload_blocked_count=%lu",
                         (long)recall, (long)edit, (long)forward, (long)merge, (long)nameMax, (long)annMax,
                         uploadEnabled, uploadMax, (unsigned long)blocked.count);
    }
    return changed;
}

- (BOOL)canRecallMessageSentAt:(int64_t)sentAtMs nowMs:(int64_t)nowMs {
    return IMServerConfigWithinWindow(sentAtMs, nowMs, _recallWindowSec);
}

- (BOOL)canEditMessageSentAt:(int64_t)sentAtMs nowMs:(int64_t)nowMs {
    return IMServerConfigWithinWindow(sentAtMs, nowMs, _editWindowSec);
}

@end
