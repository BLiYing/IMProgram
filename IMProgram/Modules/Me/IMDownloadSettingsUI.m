//  IMDownloadSettingsUI.m

#import "IMDownloadSettingsUI.h"
#import "IMMediaUtil.h" // IMFormatFileSize
#import "IMLocalization.h"

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
        case IMDownloadCategoryImage: return IMLocalized(@"common.image");
        case IMDownloadCategoryVideo: return IMLocalized(@"common.video");
        case IMDownloadCategoryFile:  return IMLocalized(@"common.file");
    }
    return IMLocalized(@"common.file");
}

NSString *IMDownloadNetworkTitle(IMDownloadNetworkKind net) {
    return net == IMDownloadNetworkCellular ? IMLocalized(@"download.network.cellular") : IMLocalized(@"download.network.wifi");
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
    return bytes <= 0 ? IMLocalized(@"download.size.off") : IMFormatFileSize(bytes);
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

IMTrafficPreset IMTrafficPresetForPolicy(IMDownloadNetworkPolicy *p) {
    int64_t v = p.video.maxBytes, f = p.file.maxBytes;
    if (v == 0 && f == 0) { return IMTrafficPresetLow; }
    if (v == 10 * kMB && f == 1 * kMB) { return IMTrafficPresetMedium; }
    if (v == 15 * kMB && f == 3 * kMB) { return IMTrafficPresetHigh; }
    return IMTrafficPresetCustom; // 视频/文件都精确命中才算某档，否则自定义（滑杆据此显第四档）
}

NSString *IMNetworkSummary(IMDownloadNetworkPolicy *p) {
    if (!p.enabled) { return IMLocalized(@"download.network.disabled"); }
    return IMLocalizedFormat(@"download.network.summary", IMDownloadSizeLabel(p.video.maxBytes), IMDownloadSizeLabel(p.file.maxBytes));
}
