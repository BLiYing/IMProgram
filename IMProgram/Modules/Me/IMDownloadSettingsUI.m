//  IMDownloadSettingsUI.m

#import "IMDownloadSettingsUI.h"
#import "IMMediaUtil.h" // IMFormatFileSize

static const int64_t kMB = 1LL << 20;

IMDownloadNetworkPolicy *IMPolicyForNetwork(IMDownloadSettings *s, IMDownloadNetworkKind net) {
    return net == IMDownloadNetworkCellular ? s.cellular : s.wifi;
}

IMDownloadCategoryRule *IMRuleForCategory(IMDownloadNetworkPolicy *p, IMDownloadCategoryKind cat) {
    switch (cat) {
        case IMDownloadCategoryImage: return p.image;
        case IMDownloadCategoryVideo: return p.video;
        case IMDownloadCategoryFile:  return p.file;
    }
    return p.file;
}

NSString *IMDownloadCategoryName(IMDownloadCategoryKind cat) {
    switch (cat) {
        case IMDownloadCategoryImage: return @"图片";
        case IMDownloadCategoryVideo: return @"视频";
        case IMDownloadCategoryFile:  return @"文件";
    }
    return @"文件";
}

NSString *IMDownloadNetworkTitle(IMDownloadNetworkKind net) {
    return net == IMDownloadNetworkCellular ? @"使用移动数据" : @"使用 Wi-Fi";
}

NSArray<NSNumber *> *IMDownloadSizeStops(void) {
    static NSArray<NSNumber *> *stops;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stops = @[ @0, @(512 * 1024), @(1 * kMB), @(3 * kMB), @(5 * kMB), @(10 * kMB), @(15 * kMB),
                   @(30 * kMB), @(50 * kMB), @(100 * kMB), @(500 * kMB), @(1024 * kMB), @(1536 * kMB) ];
    });
    return stops;
}

NSInteger IMDownloadSizeStopIndex(int64_t bytes) {
    NSArray<NSNumber *> *stops = IMDownloadSizeStops();
    NSInteger best = 0;
    int64_t bestDelta = INT64_MAX;
    for (NSInteger i = 0; i < (NSInteger)stops.count; i++) {
        int64_t delta = llabs(stops[i].longLongValue - bytes);
        if (delta < bestDelta) { bestDelta = delta; best = i; }
    }
    return best;
}

NSString *IMDownloadSizeLabel(int64_t bytes) {
    return bytes <= 0 ? @"关" : IMFormatFileSize(bytes);
}

void IMApplyTrafficPreset(IMDownloadNetworkPolicy *p, NSInteger preset) {
    int64_t video = 0, file = 0;
    switch (preset) {
        case 1: video = 10 * kMB; file = 1 * kMB; break; // 中
        case 2: video = 15 * kMB; file = 3 * kMB; break; // 高
        default: video = 0; file = 0; break;             // 低（手动）
    }
    p.video.maxBytes = video;
    p.file.maxBytes = file;
}

NSInteger IMTrafficPresetForPolicy(IMDownloadNetworkPolicy *p) {
    int64_t v = p.video.maxBytes;
    if (v <= 0) { return 0; }
    if (v <= 12 * kMB) { return 1; } // 中档（10MB 附近）
    return 2;                        // 高档（15MB 及以上）
}

NSString *IMNetworkSummary(IMDownloadNetworkPolicy *p) {
    if (!p.enabled) { return @"已停用"; }
    return [NSString stringWithFormat:@"视频 %@ · 文件 %@", IMDownloadSizeLabel(p.video.maxBytes), IMDownloadSizeLabel(p.file.maxBytes)];
}
