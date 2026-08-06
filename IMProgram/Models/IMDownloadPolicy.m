//  IMDownloadPolicy.m

#import "IMDownloadPolicy.h"

BOOL IMShouldAutoDownload(IMDownloadSettings *settings,
                          NSString *contentType,
                          int64_t sizeBytes,
                          BOOL isGroup,
                          IMNetworkType network) {
    if (network == IMNetworkTypeNone) { return NO; } // 离线：无从下载
    if (settings == nil) { settings = [IMDownloadSettings defaultSettings]; }

    IMDownloadNetworkPolicy *policy = (network == IMNetworkTypeCellular) ? settings.cellular : settings.wifi;
    if (policy == nil || !policy.enabled) { return NO; } // 该网络总开关关

    IMDownloadCategoryRule *rule;
    BOOL isImage = [contentType isEqualToString:@"image"];
    if (isImage) {
        rule = policy.image;
    } else if ([contentType isEqualToString:@"video"]) {
        rule = policy.video;
    } else if ([contentType isEqualToString:@"file"]) {
        rule = policy.file;
    } else {
        return NO; // 其它类型（text/system/语音…）不走本策略；语音恒自动由调用方另处理
    }
    if (rule == nil) { return NO; }

    BOOL chatOn = isGroup ? rule.group : rule.single;
    if (!chatOn) { return NO; } // 该聊天类型下该类别关闭

    if (isImage) { return YES; } // 图片体积小，无大小闸

    // 视频/文件：大小已知且不超上限才自动。maxBytes=0（手动档）或大小未知一律 NO。
    return sizeBytes > 0 && rule.maxBytes > 0 && sizeBytes <= rule.maxBytes;
}
