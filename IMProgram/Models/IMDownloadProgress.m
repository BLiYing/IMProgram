//  IMDownloadProgress.m

#import "IMDownloadProgress.h"
#import "IMLocalization.h"
#import "IMMediaFormat.h" // IMFormatUploadProgress（已下/总，与上传同格式）
#import "IMMediaUtil.h"   // IMFormatFileSize（纯尺寸）

@implementation IMDownloadProgress

+ (instancetype)notStartedWithTotalBytes:(int64_t)totalBytes {
    IMDownloadProgress *p = [IMDownloadProgress new];
    p->_phase = IMDownloadPhaseNotStarted;
    p->_totalBytes = MAX(0, totalBytes);
    return p;
}

+ (instancetype)downloadingWithReceived:(int64_t)received total:(int64_t)total pausable:(BOOL)pausable {
    IMDownloadProgress *p = [IMDownloadProgress new];
    p->_phase = IMDownloadPhaseDownloading;
    p->_totalBytes = MAX(0, total);
    p->_receivedBytes = MAX(0, MIN(received, p->_totalBytes ?: received)); // 已下不超过总（总未知时不夹）
    p->_pausable = pausable;
    return p;
}

+ (instancetype)pausedWithReceived:(int64_t)received total:(int64_t)total {
    IMDownloadProgress *p = [IMDownloadProgress new];
    p->_phase = IMDownloadPhasePaused;
    p->_totalBytes = MAX(0, total);
    p->_receivedBytes = MAX(0, received);
    p->_pausable = YES; // 能进暂停态本就是可暂停作业
    return p;
}

+ (instancetype)failedWithReceived:(int64_t)received total:(int64_t)total {
    IMDownloadProgress *p = [IMDownloadProgress new];
    p->_phase = IMDownloadPhaseFailed;
    p->_totalBytes = MAX(0, total);
    p->_receivedBytes = MAX(0, received);
    return p;
}

+ (instancetype)expiredWithTotalBytes:(int64_t)totalBytes {
    IMDownloadProgress *p = [IMDownloadProgress new];
    p->_phase = IMDownloadPhaseFailed;
    p->_totalBytes = MAX(0, totalBytes);
    p->_expired = YES;
    return p;
}

+ (instancetype)done {
    IMDownloadProgress *p = [IMDownloadProgress new];
    p->_phase = IMDownloadPhaseDone;
    return p;
}

- (double)fraction {
    if (_totalBytes <= 0) { return 0.0; }
    double f = (double)_receivedBytes / (double)_totalBytes;
    if (f < 0) { return 0.0; }
    if (f > 1) { return 1.0; }
    return f;
}

- (NSString *)displayText {
    switch (self.phase) {
        case IMDownloadPhaseNotStarted: return self.totalBytes > 0 ? IMFormatFileSize(self.totalBytes) : @"";
        case IMDownloadPhaseDownloading:
        case IMDownloadPhasePaused:     return IMFormatUploadProgress(self.fraction, self.totalBytes);
        case IMDownloadPhaseFailed:     return self.expired ? IMLocalized(@"fav.file.expired") : IMLocalized(@"media.download.failed");
        case IMDownloadPhaseDone:       return @"";
    }
}

- (NSString *)accessibilityText {
    switch (self.phase) {
        case IMDownloadPhaseNotStarted:
            return self.totalBytes > 0 ? IMLocalizedFormat(@"media.download.a11y_start_size", IMFormatFileSize(self.totalBytes)) : IMLocalized(@"media.download.a11y_start");
        case IMDownloadPhaseDownloading:
            return IMLocalizedFormat(@"media.download.a11y_progress", (long)round(self.fraction * 100));
        case IMDownloadPhasePaused:  return IMLocalized(@"media.download.a11y_paused");
        case IMDownloadPhaseFailed:  return self.expired ? IMLocalized(@"fav.file.expired") : IMLocalized(@"media.download.a11y_failed");
        case IMDownloadPhaseDone:    return IMLocalized(@"media.download.a11y_done");
    }
}

- (NSString *)fileLineText {
    switch (self.phase) {
        case IMDownloadPhaseNotStarted: return IMLocalized(@"media.download.tap_to_download");
        case IMDownloadPhaseDownloading:
        case IMDownloadPhasePaused:     return IMFormatUploadProgress(self.fraction, self.totalBytes);
        case IMDownloadPhaseFailed:     return self.expired ? IMLocalized(@"fav.file.expired") : IMLocalized(@"media.download.failed_tap_retry");
        case IMDownloadPhaseDone:       return IMLocalized(@"media.download.tap_to_open");
    }
}

@end

NSString *IMDownloadCenterSymbolName(IMDownloadProgress *progress) {
    if (progress == nil) { return nil; }
    switch (progress.phase) {
        case IMDownloadPhaseFailed:      return progress.expired ? nil : @"arrow.clockwise.circle.fill"; // 已失效：无从重试
        case IMDownloadPhasePaused:      return @"arrow.down.circle.fill";
        case IMDownloadPhaseNotStarted:  return @"arrow.down.circle.fill";
        case IMDownloadPhaseDownloading: return progress.pausable ? @"pause.circle.fill" : @"xmark.circle.fill";
        case IMDownloadPhaseDone:        return nil; // 就绪不给按钮：绝不自动打开/播放
    }
}
